import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/providers.dart';
import '../../data/repos/schedules_repo.dart';
import '../../data/models/schedule.dart';
import 'widgets/shift_cell.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final _schedulesRepoProvider = Provider((ref) => SchedulesRepo());

class ResidentHomeList extends ConsumerWidget {
  const ResidentHomeList({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fbUser = ref.watch(firebaseAuthProvider).currentUser;
    if (fbUser == null) return const Center(child: Text('Not signed in'));
    final now = DateTime.now();
    final fromUpcoming = now;
    final toUpcoming = now.add(const Duration(days: 7));
    final fromPast = now.subtract(const Duration(days: 14));
    final toPast = now;
    final upcomingStream = ref.watch(_schedulesStreamProvider((fbUser.uid, fromUpcoming, toUpcoming)));
    final pastStream = ref.watch(_schedulesStreamProvider((fbUser.uid, fromPast, toPast)));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text("Active Shifts", style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        upcomingStream.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (snap) {
            final docs = snap.docs.map((d) => d.data()).toList();
            if (docs.isEmpty) return const Text('No upcoming shifts');
            return Column(children: [
              for (final s in docs)
                ShiftCell(
                  s: s,
                  onTap: () => context.push('/evaluation/${s.id}')
                ),
            ]);
          },
        ),
        const SizedBox(height: 16),
        Text("Past Shifts", style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        pastStream.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (snap) {
            final docs = snap.docs.map((d) => d.data()).toList();
            if (docs.isEmpty) return const Text('No recent shifts');
            return Column(children: [
              for (final s in docs)
                ShiftCell(
                  s: s,
                  onTap: () => context.push('/evaluation/${s.id}')
                ),
            ]);
          },
        ),
      ],
    );
  }
}

final _schedulesStreamProvider = StreamProvider.family.autoDispose<QuerySnapshot<Schedule>, (String, DateTime, DateTime)>((ref, args) {
  final (uid, from, to) = args;
  return ref.read(_schedulesRepoProvider).streamUpcomingForResident(uid, from, to);
});
