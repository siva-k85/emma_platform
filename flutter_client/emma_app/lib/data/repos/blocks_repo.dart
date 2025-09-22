import 'package:cloud_firestore/cloud_firestore.dart';

class BlocksRepo {
  final _col = FirebaseFirestore.instance.collection('block_time');

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> listAcademicBlocks(int year) async {
    final q = await _col.where('year', isEqualTo: year).orderBy('start').get();
    return q.docs;
  }
}

