import 'package:cloud_firestore/cloud_firestore.dart';

class ResidentMetricsRepo {
  final _col = FirebaseFirestore.instance.collection('ResidentMetrics');

  Future<DocumentSnapshot<Map<String, dynamic>>?> fetchForResident(String residentId, {List<String>? blockIds}) async {
    // Allow multiple block scope; backend may denormalize by block
    if (blockIds != null && blockIds.isNotEmpty) {
      // Example: combined doc id pattern residentId_blockId; adjust at runtime
      // Try the first provided block for now; caller can merge.
      return _col.doc('${residentId}_${blockIds.first}').get();
    }
    return _col.doc(residentId).get();
  }
}

