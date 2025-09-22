import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/app_user.dart';
import '../../data/repos/users_repo.dart';

final firebaseAuthProvider = Provider<fb_auth.FirebaseAuth>((ref) => fb_auth.FirebaseAuth.instance);
final usersRepoProvider = Provider((ref) => UsersRepo());

final authStateProvider = StreamProvider<fb_auth.User?>((ref) => ref.watch(firebaseAuthProvider).authStateChanges());

final appUserProvider = StreamProvider<AppUser?>((ref) {
  final fbUser = ref.watch(authStateProvider).value;
  if (fbUser == null) return const Stream.empty();
  final repo = ref.watch(usersRepoProvider);
  // Watch the user doc; if missing, auto-provision a minimal one for smoother auth.
  return repo.watchById(fbUser.uid).map((user) {
    if (user == null) {
      // Default role selection: if the test email is used, provision as attending; else resident.
      final email = fbUser.email ?? '';
      final defaultRole = email.contains('attending+dev@ahn.org') ? AppRole.attending : AppRole.resident;
      repo.createOrUpdate(AppUser(uid: fbUser.uid, role: defaultRole, email: email));
    }
    return user;
  });
});

final roleProvider = Provider<AppRole?>((ref) => ref.watch(appUserProvider).value?.role);
