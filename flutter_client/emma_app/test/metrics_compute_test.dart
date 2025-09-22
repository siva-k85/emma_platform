import 'package:flutter_test/flutter_test.dart';
import 'package:emma_app/data/models/resident_metrics.dart';

ResidentMetricsView computeFromFake(List<Map<String, dynamic>> schedules) {
  int total = schedules.length;
  int completed = 0;
  int resDone = 0;
  int pending = 0;
  double sumSelf = 0;
  double sumAttn = 0;
  int countSelf = 0;
  int countAttn = 0;
  final topicMap = <String, List<double>>{};
  final topicMapAttn = <String, List<double>>{};
  final suggestions = <ResidentSuggestion>[];
  double? avg(Map? m) { if (m == null) return null; final vals = m.values.whereType<num>().map((e)=>e.toDouble()).toList(); if (vals.isEmpty) return null; return vals.reduce((a,b)=>a+b)/vals.length; }

  for (final data in schedules) {
    final residentStatus = data['resident_evaluation_status'] ?? (data['resident_evaluation_completed'] == true ? 'done' : '');
    final attnStatus = data['attendee_evaluation_status'] ?? (data['attending_evaluation_completed'] == true ? 'done' : '');
    final eitherDone = residentStatus == 'done' || attnStatus == 'done';
    if (eitherDone) completed++; else pending++;
    if (residentStatus == 'done') resDone++;

    final sAvg = avg(data['resident_evaluation']?['scores'] as Map<String, dynamic>?);
    final aAvg = avg(data['attendee_evaluation']?['scores'] as Map<String, dynamic>?);
    if (sAvg != null) { sumSelf += sAvg; countSelf++; }
    if (aAvg != null) { sumAttn += aAvg; countAttn++; }
    final topics = (data['topics'] as List?)?.map((e)=>e.toString()).toList() ?? const [];
    for (final t in topics) {
      if (sAvg != null) topicMap.putIfAbsent(t, ()=>[]).add(sAvg);
      if (aAvg != null) topicMapAttn.putIfAbsent(t, ()=>[]).add(aAvg);
    }
  }

  final topicAvgs = <String, TopicAverages>{};
  topicMap.forEach((k, v) {
    final a = topicMapAttn[k] ?? const [];
    topicAvgs[k] = TopicAverages(
      selfAvg: v.isEmpty ? null : v.reduce((a,b)=>a+b)/v.length,
      attendingAvg: a.isEmpty ? null : a.reduce((x,y)=>x+y)/a.length,
      selfCount: v.length,
      attendingCount: a.length,
    );
  });

  return ResidentMetricsView(
    totalShifts: total,
    completedShifts: completed,
    completionPct: total == 0 ? 0 : (completed/total)*100.0,
    avgSelf: countSelf==0?null:sumSelf/countSelf,
    avgAttending: countAttn==0?null:sumAttn/countAttn,
    residentCompletedCount: resDone,
    pendingCount: pending,
    pgyPercentile: null,
    topicAvgs: topicAvgs,
    suggestions: suggestions,
  );
}

void main() {
  test('Resident metrics compute basic', () {
    final schedules = [
      {
        'resident_evaluation_status': 'done',
        'attendee_evaluation_status': 'pending',
        'resident_evaluation': {'scores': {'a': 4, 'b': 5}},
        'attendee_evaluation': {'scores': {'a': 3, 'b': 4}},
        'topics': ['T1', 'T2']
      },
      {
        'resident_evaluation_status': 'pending',
        'attendee_evaluation_status': 'done',
        'resident_evaluation': {'scores': {'a': 2, 'b': 3}},
        'attendee_evaluation': {'scores': {'a': 4, 'b': 4}},
        'topics': ['T1']
      }
    ];
    final v = computeFromFake(schedules);
    expect(v.totalShifts, 2);
    expect(v.completedShifts, 2); // either side done on both
    expect(v.residentCompletedCount, 1);
    expect(v.pendingCount, 0);
    expect(v.avgSelf, closeTo(3.5, 0.001)); // (4.5 + 2.5)/2
    expect(v.avgAttending, closeTo(3.75, 0.001)); // (3.5 + 4.0)/2
    expect(v.topicAvgs['T1']!.selfAvg, isNotNull);
  });
}

