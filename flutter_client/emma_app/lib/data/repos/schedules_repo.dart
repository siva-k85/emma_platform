import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/schedule.dart';

class SchedulesRepo {
  final _col = FirebaseFirestore.instance.collection('Schedules').withConverter<Schedule>(
        fromFirestore: (doc, _) => Schedule.fromFirestore(doc),
        toFirestore: (s, _) => {},
      );
  final _raw = FirebaseFirestore.instance.collection('Schedules');

  Stream<QuerySnapshot<Schedule>> streamUpcomingForResident(String residentId, DateTime from, DateTime to) {
    return _col
        .where('resident_ref', isEqualTo: FirebaseFirestore.instance.doc('users/$residentId'))
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(to))
        .orderBy('date')
        .snapshots();
  }

  Stream<QuerySnapshot<Schedule>> streamPendingForAttending(String attendingId) {
    return _col
        .where('attending_ref', isEqualTo: FirebaseFirestore.instance.doc('users/$attendingId'))
        .where('attendee_evaluation_status', isNotEqualTo: 'done')
        .orderBy('attendee_evaluation_status')
        .orderBy('date', descending: true)
        .snapshots();
  }

  Future<void> submitResidentEval(String scheduleId, Map<String, dynamic> payload) async {
    await _raw.doc(scheduleId).set({
      'resident_evaluation': payload,
      'resident_evaluation_status': 'done',
      'evaluation_status': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> submitAttendingEval(String scheduleId, Map<String, dynamic> payload) async {
    await _raw.doc(scheduleId).set({
      'attendee_evaluation': payload,
      'attendee_evaluation_status': 'done',
      'evaluation_status': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
