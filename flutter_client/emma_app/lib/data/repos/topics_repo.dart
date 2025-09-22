import 'package:cloud_firestore/cloud_firestore.dart';

class TopicsRepo {
  final _topics = FirebaseFirestore.instance.collection('Topics');
  final _subtopics = FirebaseFirestore.instance.collection('Subtopics');

  Future<Map<String, dynamic>?> getTopicById(String id) async {
    final doc = await _topics.doc(id).get();
    return doc.data();
  }

  Future<List<Map<String, dynamic>>> getSubtopics(String topicId) async {
    final q = await _subtopics.where('topic_id', isEqualTo: topicId).get();
    return q.docs.map((d) => d.data()).toList();
  }
}

