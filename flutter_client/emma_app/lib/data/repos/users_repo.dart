import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';

class UsersRepo {
  final _col = FirebaseFirestore.instance.collection('users').withConverter<AppUser>(
        fromFirestore: (doc, _) => AppUser.fromFirestore(doc),
        toFirestore: (user, _) => {
          'name': user.name,
          'email': user.email,
          'display_photo': user.photoUrl,
          'role': user.role.name,
          if (user.pgy != null) 'PGY': user.pgy,
          if (user.department != null) 'department': user.department,
        },
      );

  Stream<AppUser?> watchById(String uid) => _col.doc(uid).snapshots().map((s) => s.data());
  Future<AppUser?> getById(String uid) async => (await _col.doc(uid).get()).data();
  Future<void> createOrUpdate(AppUser user) => _col.doc(user.uid).set(user, SetOptions(merge: true));
}

