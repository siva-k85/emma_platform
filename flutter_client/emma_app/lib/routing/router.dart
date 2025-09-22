import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/providers.dart';
import '../core/auth_gate.dart';
import '../data/models/app_user.dart';
import '../features/auth/auth_screen.dart';
import '../features/home/attending_home.dart';
import '../features/home/resident_home.dart';
import '../features/home/resident_home_list.dart';
import '../features/profile/profile_screen.dart';
import '../features/metrics/resident_metrics_screen.dart';
import '../features/metrics/attending_metrics_screen.dart';
import '../features/admin/admin_home.dart';
import '../features/evaluations/evaluation_form.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authStream = ref.watch(firebaseAuthProvider).authStateChanges();
  return GoRouter(
    initialLocation: '/auth',
    debugLogDiagnostics: false,
    refreshListenable: GoRouterRefreshStream(authStream),
    redirect: (context, state) {
      final fbUser = ref.read(firebaseAuthProvider).currentUser;
      final appUser = ref.read(appUserProvider).value;
      final loggingIn = state.uri.path == '/auth';
      if (fbUser == null) return loggingIn ? null : '/auth';
      if (appUser == null) return null; // still loading user doc
      final role = appUser.role;
      if (loggingIn) {
        switch (role) {
          case AppRole.resident:
            return '/home/resident/metrics';
          case AppRole.attending:
            return '/home/attending/metrics';
          case AppRole.admin:
            return '/admin';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/auth', builder: (c, s) => const AuthScreen()),
      // Resident shell
      ShellRoute(
        builder: (c, s, child) => ResidentHomeShell(child: child),
        routes: [
          GoRoute(path: '/home/resident/home', builder: (c, s) => const ResidentHomeList()),
          GoRoute(path: '/home/resident/metrics', builder: (c, s) => const ResidentMetricsScreen()),
          GoRoute(path: '/home/resident/profile', builder: (c, s) => const ProfileScreen()),
        ],
      ),
      // Attending shell
      ShellRoute(
        builder: (c, s, child) => AttendingHomeShell(child: child),
        routes: [
          GoRoute(path: '/home/attending/home', builder: (c, s) => const AttendingMetricsScreen()),
          GoRoute(path: '/home/attending/metrics', builder: (c, s) => const AttendingMetricsScreen()),
          GoRoute(path: '/home/attending/profile', builder: (c, s) => const ProfileScreen()),
        ],
      ),
      GoRoute(path: '/admin', builder: (c, s) => const AdminHome()),
      GoRoute(path: '/evaluation/:scheduleId', builder: (c, s) => EvaluationFormScreen(scheduleId: s.pathParameters['scheduleId']!)),
      // Fallback
      GoRoute(path: '/', builder: (c, s) => const AuthGate()),
    ],
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
