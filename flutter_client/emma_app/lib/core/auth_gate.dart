import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/app_user.dart';
import 'auth/providers.dart';
import '../features/auth/auth_screen.dart';
import '../features/home/resident_home.dart';
import '../features/home/attending_home.dart';
import '../features/admin/admin_home.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    return auth.when(
      loading: () => const _Splash(),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (user) {
        if (user == null) return const AuthScreen();
        final appUser = ref.watch(appUserProvider).value;
        if (appUser == null) return const _Splash();
        switch (appUser.role) {
          case AppRole.resident:
            return const ResidentHomeShell();
          case AppRole.attending:
            return const AttendingHomeShell();
          case AppRole.admin:
            return const AdminHome();
        }
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

