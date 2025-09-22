import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/providers.dart';
import '../../core/blocks/date_range.dart';
import '../../data/repos/topics_repo.dart';

class TopicMetricsScreen extends ConsumerWidget {
  final String topicId;
  const TopicMetricsScreen({super.key, required this.topicId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final range = ref.watch(selectedBlocksDateRangeProvider);
    final async = ref.watch(_topicStatsProvider((uid ?? '', topicId, range)));
    return Scaffold(
      appBar: AppBar(title: Text('Topic: $topicId')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(spacing: 12, runSpacing: 12, children: [
              _TopMetricCard(title: 'Resident Evaluations Completed for Topic', value: s.selfCount.toString()),
              _TopMetricCard(title: 'Attendee Evaluations Completed for Topic', value: s.attnCount.toString()),
            ]),
            const SizedBox(height: 16),
            if (s.subtopics.isNotEmpty) ...[
              Text('Subtopic Averages', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final e in s.subtopics.entries)
                ListTile(title: Text(e.key), subtitle: Text('Self: ${e.value.self?.toStringAsFixed(2) ?? '—'}   Attending: ${e.value.attn?.toStringAsFixed(2) ?? '—'}')),
            ],
            const SizedBox(height: 16),
            Text('Relevant Comments', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (s.comments.isEmpty) const Text('No comments yet'),
            for (final c in s.comments) ListTile(title: Text(c)),
          ],
        ),
      ),
    );
  }
}

class _SubtopicAvg { final double? self; final double? attn; const _SubtopicAvg(this.self, this.attn); }
class _TopicStats { final int selfCount; final int attnCount; final Map<String, _SubtopicAvg> subtopics; final List<String> comments; _TopicStats(this.selfCount, this.attnCount, this.subtopics, this.comments); }

final _topicStatsProvider = FutureProvider.family<_TopicStats, (String, String, DateRange?)>((ref, args) async {
  final (uid, topicId, range) = args;
  if (uid.isEmpty) return _TopicStats(0, 0, {}, []);
  Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('Schedules');
  final upperExists = await q.limit(1).get().then((s) => s.docs.isNotEmpty).catchError((_) => false);
  if (!upperExists) q = FirebaseFirestore.instance.collection('schedules');
  if (range != null) {
    q = q.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(range.start)).where('date', isLessThanOrEqualTo: Timestamp.fromDate(range.end));
  }
  q = q.orderBy('date');
  final snap = await q.get();
  final docs = snap.docs.where((d) {
    final data = d.data();
    final v = data['resident_ref'];
    final topics = (data['topics'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final matchResident = (v is DocumentReference && v.path.endsWith(uid)) || (v is String && v.endsWith(uid));
    return matchResident && topics.contains(topicId);
  }).toList();

  int selfCount = 0;
  int attnCount = 0;
  final scoresSelf = <double>[];
  final scoresAttn = <double>[];
  final comments = <String>[];

  for (final d in docs) {
    final data = d.data();
    final selfScores = data['resident_evaluation']?['scores'] ?? data['evaluation_data']?['resident_evaluation']?['scores'];
    final attnScores = data['attendee_evaluation']?['scores'] ?? data['evaluation_data']?['attendee_evaluation']?['scores'];
    double? avg(Map? m) { if (m == null) return null; final vals = m.values.whereType<num>().map((e)=>e.toDouble()).toList(); if (vals.isEmpty) return null; return vals.reduce((a,b)=>a+b)/vals.length; }
    final sAvg = avg(selfScores is Map ? selfScores : null);
    final aAvg = avg(attnScores is Map ? attnScores : null);
    if (sAvg != null) { selfCount++; scoresSelf.add(sAvg); }
    if (aAvg != null) { attnCount++; scoresAttn.add(aAvg); }
    final c = data['evaluation_data']?['attendee_evaluation']?['feedback'] ?? data['attendee_evaluation']?['suggestion_comment'];
    if (c is String && c.trim().isNotEmpty) comments.add(c.trim());
  }

  // Subtopics (if any)
  final topicsRepo = TopicsRepo();
  final sub = await topicsRepo.getSubtopics(topicId);
  final subs = <String, _SubtopicAvg>{};
  for (final s in sub) {
    final id = s['id']?.toString() ?? s['title']?.toString() ?? 'sub';
    subs[id] = const _SubtopicAvg(null, null); // placeholder until per-subtopic scores exist
  }
  return _TopicStats(selfCount, attnCount, subs, comments);
});

class _TopMetricCard extends StatelessWidget {
  final String title;
  final String value;
  const _TopMetricCard({required this.title, required this.value});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ]),
        ),
      ),
    );
  }
}
