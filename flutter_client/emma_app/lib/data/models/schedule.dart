import 'package:cloud_firestore/cloud_firestore.dart';

enum EvalStatus { pending, selfDone, attendingDone, complete }

class Schedule {
  final String id;
  final DocumentReference residentRef;
  final DocumentReference? attendingRef;
  final DateTime date;
  final DateTime? shiftStart;
  final DateTime? shiftEnd;
  final List<String> topics;
  final String? residentEvalStatus;
  final String? attendingEvalStatus;
  final bool isConflict;
  final String? attendingName;
  final String? residentName;
  final String? suggestionLatest;
  final DateTime? suggestionLatestTime;

  const Schedule({
    required this.id,
    required this.residentRef,
    this.attendingRef,
    required this.date,
    this.shiftStart,
    this.shiftEnd,
    this.topics = const [],
    this.residentEvalStatus,
    this.attendingEvalStatus,
    this.isConflict = false,
    this.attendingName,
    this.residentName,
    this.suggestionLatest,
    this.suggestionLatestTime,
  });

  factory Schedule.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    DateTime? _ts(dynamic v) => (v is Timestamp) ? v.toDate() : null;
    return Schedule(
      id: doc.id,
      residentRef: (d['resident_ref'] as DocumentReference?) ?? FirebaseFirestore.instance.doc('users/missing'),
      attendingRef: d['attending_ref'] as DocumentReference?,
      date: _ts(d['date']) ?? DateTime.now(),
      shiftStart: _ts(d['shift_start']),
      shiftEnd: _ts(d['shift_end']),
      topics: (d['topics'] as List?)?.map((e) => e.toString()).toList().cast<String>() ?? const [],
      residentEvalStatus: (d['resident_evaluation_status'] ?? d['resident_status']) as String?,
      attendingEvalStatus: (d['attendee_evaluation_status'] ?? d['attending_status']) as String?,
      isConflict: d['isConflict'] as bool? ?? false,
      attendingName: d['attending_name'] as String?,
      residentName: d['resident_name'] as String?,
      suggestionLatest: d['attendee_evaluation_suggestions'] is List && (d['attendee_evaluation_suggestions'] as List).isNotEmpty
          ? (d['attendee_evaluation_suggestions'] as List).last.toString()
          : d['attendee_evaluation_suggestion'] as String?,
      suggestionLatestTime: _ts(d['attendee_evaluation_suggestion_time']),
    );
  }

  EvalStatus derivedStatus() {
    final r = residentEvalStatus == 'done';
    final a = attendingEvalStatus == 'done';
    if (r && a) return EvalStatus.complete;
    if (a) return EvalStatus.attendingDone;
    if (r) return EvalStatus.selfDone;
    return EvalStatus.pending;
  }
}

