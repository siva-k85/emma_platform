import 'package:cloud_firestore/cloud_firestore.dart';

class BlockTime {
  final String id;
  final String? name;
  final DateTime start;
  final DateTime end;
  final int? year;
  final bool? active;

  const BlockTime({required this.id, required this.start, required this.end, this.name, this.year, this.active});

  factory BlockTime.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final startTs = data['start'] as Timestamp?;
    final endTs = data['end'] as Timestamp?;
    return BlockTime(
      id: doc.id,
      name: data['name'] as String?,
      start: (startTs ?? Timestamp.fromDate(DateTime.now())).toDate(),
      end: (endTs ?? Timestamp.fromDate(DateTime.now())).toDate(),
      year: (data['year'] as num?)?.toInt(),
      active: data['active'] as bool?,
    );
  }
}

