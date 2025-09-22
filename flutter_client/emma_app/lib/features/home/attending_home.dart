import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/providers.dart';
import '../../data/repos/schedules_repo.dart';
import '../../data/models/schedule.dart';
import 'widgets/shift_cell.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AttendingHomeShell extends StatelessWidget {
  final Widget? child;
  const AttendingHomeShell({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    final currentIndex = loc.contains('/metrics') ? 0 : loc.contains('/profile') ? 2 : 1;
    return Scaffold(
      body: child ?? const _PendingReviews(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/home/attending/metrics');
              break;
            case 1:
              context.go('/home/attending/home');
              break;
            case 2:
              context.go('/home/attending/profile');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Metrics'),
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _PendingReviews extends ConsumerWidget {
  const _PendingReviews();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return const Center(child: Text('Not signed in'));
    final repo = SchedulesRepo();
    return StreamBuilder(
      stream: repo.streamPendingForAttending(uid),
      builder: (context, AsyncSnapshot<QuerySnapshot<Schedule>> snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs.map((d) => d.data()).toList();
        if (docs.isEmpty) return const Center(child: Text('No pending reviews'));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text("Pending Reviews", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final s in docs)
              ShiftCell(s: s, onTap: () => context.push('/evaluation/${s.id}')),
          ],
        );
      },
    );
  }
}
