import 'package:cloud_firestore/cloud_firestore.dart';

enum AppRole { resident, attending, admin }

class AppUser {
  final String uid;
  final String? name;
  final String? email;
  final String? photoUrl;
  final AppRole role;
  final int? pgy;
  final String? department;

  const AppUser({
    required this.uid,
    required this.role,
    this.name,
    this.email,
    this.photoUrl,
    this.pgy,
    this.department,
  });

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final roleStr = (data['role'] as String?)?.toLowerCase() ?? 'resident';
    final role = AppRole.values.firstWhere(
      (r) => r.name == roleStr,
      orElse: () => AppRole.resident,
    );
    return AppUser(
      uid: doc.id,
      role: role,
      name: data['name'] as String?,
      email: data['email'] as String?,
      photoUrl: data['display_photo'] as String? ?? data['photoUrl'] as String?,
      pgy: (data['PGY'] as num?)?.toInt() ?? (data['pgy'] as num?)?.toInt(),
      department: data['department'] as String?,
    );
  }
}

