import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_user.dart';
import '../../data/repos/users_repo.dart';

final firebaseAuthProvider = Provider<fb_auth.FirebaseAuth>(
  (ref) => fb_auth.FirebaseAuth.instance,
);
final usersRepoProvider = Provider((ref) => UsersRepo());

final authStateProvider = StreamProvider<fb_auth.User?>(
  (ref) => ref.watch(firebaseAuthProvider).authStateChanges(),
);

AppRole _defaultRoleForEmail(String email) {
  final normalized = email.toLowerCase();
  if (normalized.contains('attending+')) return AppRole.attending;
  if (normalized.contains('admin+')) return AppRole.admin;
  return AppRole.resident;
}

final appUserProvider = StreamProvider<AppUser?>((ref) {
  final fbUser = ref.watch(authStateProvider).value;
  if (fbUser == null) return const Stream.empty();
  final repo = ref.watch(usersRepoProvider);
  // Watch the user doc; if missing, auto-provision a minimal one for smoother auth.
  return repo.watchById(fbUser.uid).map((user) {
    if (user != null) return user;
    final email = fbUser.email ?? '';
    final fallback = AppUser(
      uid: fbUser.uid,
      role: _defaultRoleForEmail(email),
      email: email,
    );
    unawaited(repo.createOrUpdate(fallback));
    return fallback;
  });
});

final roleProvider = Provider<AppRole?>(
  (ref) => ref.watch(appUserProvider).value?.role,
);
