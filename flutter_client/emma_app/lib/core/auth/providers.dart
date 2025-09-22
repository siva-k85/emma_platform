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
  return ref.watch(usersRepoProvider).watchById(fbUser.uid);
});

final roleProvider = Provider<AppRole?>((ref) => ref.watch(appUserProvider).value?.role);
