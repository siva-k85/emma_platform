import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/providers.dart';
import '../../core/blocks/date_range.dart';
import '../../data/models/resident_metrics.dart';

final residentMetricsProvider = FutureProvider<ResidentMetricsView>((ref) async {
  final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
  if (uid == null) throw StateError('Not signed in');
  final range = ref.watch(selectedBlocksDateRangeProvider);
  final start = range?.start;
  final end = range?.end;

  // 1) Try ResidentMetrics aggregated doc(s)
  final agg = await _tryFetchAggregates(uid, start: start, end: end);
  if (agg != null) return agg;

  // 2) Fallback – derive from Schedules + Evaluations
  return _computeFromSchedules(uid, start: start, end: end);
});

Future<ResidentMetricsView?> _tryFetchAggregates(String uid, {DateTime? start, DateTime? end}) async {
  try {
    final col = FirebaseFirestore.instance.collection('ResidentMetrics');
    // Allow block scope doc id like `${uid}_${blockId}` but without block IDs we try base doc
    final snap = await col.doc(uid).get();
    if (!snap.exists) return null;
    final d = snap.data() as Map<String, dynamic>;
    double? _d(v) => (v is num) ? v.toDouble() : null;
    final Map<String, TopicAverages> topicAvgs = {};
    final t = (d['topic_averages'] as Map?)?.cast<String, dynamic>() ?? {};
    t.forEach((k, v) {
      topicAvgs[k] = TopicAverages(
        selfAvg: _d(v['self_avg']),
        attendingAvg: _d(v['attending_avg']),
        selfCount: (v['self_count'] as num?)?.toInt() ?? 0,
        attendingCount: (v['attending_count'] as num?)?.toInt() ?? 0,
      );
    });
    final total = (d['total_shifts'] as num?)?.toInt() ?? 0;
    final completed = (d['completed_shifts'] as num?)?.toInt() ?? 0;
    final comp = total == 0 ? 0.0 : completed / total * 100.0;
    final suggestions = <ResidentSuggestion>[]; // aggregated doc may not hold suggestions
    return ResidentMetricsView(
      totalShifts: total,
      completedShifts: completed,
      completionPct: comp,
      avgSelf: _d(d['avg_self']),
      avgAttending: _d(d['avg_attending']),
      residentCompletedCount: (d['resident_completed'] as num?)?.toInt() ?? 0,
      pendingCount: (d['pending'] as num?)?.toInt() ?? 0,
      pgyPercentile: _d(d['pgy_percentile']),
      topicAvgs: topicAvgs,
      suggestions: suggestions,
    );
  } catch (_) {
    return null;
  }
}

Future<ResidentMetricsView> _computeFromSchedules(String uid, {DateTime? start, DateTime? end}) async {
  Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('Schedules');
  // fallback to lowercase if needed
  final upperExists = await q.limit(1).get().then((s) => s.docs.isNotEmpty).catchError((_) => false);
  if (!upperExists) {
    q = FirebaseFirestore.instance.collection('schedules');
  }
  // Most datasets use either DocumentReference or string '/users/{id}' for resident_ref
  if (start != null) q = q.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start));
  if (end != null) q = q.where('date', isLessThanOrEqualTo: Timestamp.fromDate(end));
  q = q.orderBy('date');
  final snap = await q.get();
  // Filter client-side by resident id against both types
  final docs = snap.docs.where((d) {
    final v = d.data()['resident_ref'];
    if (v is DocumentReference) return v.path.endsWith(uid);
    if (v is String) return v.endsWith(uid);
    return false;
  }).toList();

  int total = docs.length;
  int completedShifts = 0;
  int residentDone = 0;
  int pending = 0;
  double sumSelf = 0;
  double sumAttn = 0;
  int countSelf = 0;
  int countAttn = 0;
  final topicMap = <String, List<double>>{}; // self
  final topicMapAttn = <String, List<double>>{};
  final suggestions = <ResidentSuggestion>[];

  double? avgFromScores(dynamic scores) {
    if (scores is Map) {
      final vals = scores.values.whereType<num>().map((e) => e.toDouble()).toList();
      if (vals.isEmpty) return null;
      return vals.reduce((a, b) => a + b) / vals.length;
    }
    return null;
  }

  for (final d in docs) {
    final data = d.data();
    final residentStatus = data['resident_evaluation_status'] ?? data['resident_status'] ?? (data['resident_evaluation_completed'] == true ? 'done' : null) ??
        ((data['evaluation_data']?['resident_evaluation']?['status']?['status']) ?? '');
    final attnStatus = data['attendee_evaluation_status'] ?? data['attending_status'] ?? (data['attending_evaluation_completed'] == true ? 'done' : null) ??
        ((data['evaluation_data']?['attendee_evaluation']?['status']?['status']) ?? '');
    final eitherDone = residentStatus == 'done' || attnStatus == 'done';
    if (eitherDone) completedShifts++; else pending++;
    if (residentStatus == 'done') residentDone++;

    // Self avg
    final selfScores = data['resident_evaluation']?['scores'] ?? data['evaluation_data']?['resident_evaluation']?['scores'];
    final sAvg = avgFromScores(selfScores);
    if (sAvg != null) { sumSelf += sAvg; countSelf++; }
    // Attending avg
    final attnScores = data['attendee_evaluation']?['scores'] ?? data['evaluation_data']?['attendee_evaluation']?['scores'];
    final aAvg = avgFromScores(attnScores);
    if (aAvg != null) { sumAttn += aAvg; countAttn++; }

    // Topic-wise avgs – assume topics array and per-topic scores if provided; otherwise, use overall scores equally
    final topics = (data['topics'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    if (topics.isNotEmpty) {
      for (final t in topics) {
        if (sAvg != null) topicMap.putIfAbsent(t, () => []).add(sAvg);
        if (aAvg != null) topicMapAttn.putIfAbsent(t, () => []).add(aAvg);
      }
    }

    // Suggestions (attending)
    final sList = data['attendee_evaluation_suggestions'];
    if (sList is List) {
      for (final s in sList) {
        if (s == null) continue;
        suggestions.add(ResidentSuggestion(text: s.toString(), timestamp: (data['updated_at'] as Timestamp?)?.toDate(), author: data['attending_name']?.toString()));
      }
    } else {
      final single = data['evaluation_data']?['attendee_evaluation']?['feedback'] ?? data['attendee_evaluation']?['suggestion_comment'];
      if (single is String && single.trim().isNotEmpty) {
        suggestions.add(ResidentSuggestion(text: single.trim(), timestamp: (data['updated_at'] as Timestamp?)?.toDate(), author: data['attending_name']?.toString()));
      }
    }
  }

  double? avgSelf = countSelf == 0 ? null : (sumSelf / countSelf);
  double? avgAttn = countAttn == 0 ? null : (sumAttn / countAttn);
  final topicAvgs = <String, TopicAverages>{};
  for (final e in topicMap.entries) {
    final selfList = e.value;
    final attnList = topicMapAttn[e.key] ?? const [];
    final selfAvg = selfList.isEmpty ? null : (selfList.reduce((a, b) => a + b) / selfList.length);
    final attnAvg = attnList.isEmpty ? null : (attnList.reduce((a, b) => a + b) / attnList.length);
    topicAvgs[e.key] = TopicAverages(selfAvg: selfAvg, attendingAvg: attnAvg, selfCount: selfList.length, attendingCount: attnList.length);
  }

  final pct = total == 0 ? 0.0 : (completedShifts / total) * 100.0;
  // Percentile rank within PGY cohort – optional, skip client-side heavy calc for now (null)
  return ResidentMetricsView(
    totalShifts: total,
    completedShifts: completedShifts,
    completionPct: pct,
    avgSelf: avgSelf,
    avgAttending: avgAttn,
    residentCompletedCount: residentDone,
    pendingCount: pending,
    pgyPercentile: null,
    topicAvgs: topicAvgs,
    suggestions: suggestions..sort((a, b) => (b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0))),
  );
}

