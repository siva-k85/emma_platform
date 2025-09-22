import 'package:cloud_firestore/cloud_firestore.dart';

class EvaluationsRepo {
  final _col = FirebaseFirestore.instance.collection('Evaluations');

  Future<Map<String, dynamic>?> getByScheduleId(String scheduleId) async {
    final q = await _col.where('schedule_id', isEqualTo: scheduleId).limit(1).get();
    if (q.docs.isEmpty) return null;
    return q.docs.first.data();
  }
}

