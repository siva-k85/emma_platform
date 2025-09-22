import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/providers.dart';
import '../../core/blocks/providers.dart';
import '../../core/blocks/date_range.dart';
import '../../core/loading.dart';

class AttendingMetricsScreen extends ConsumerWidget {
  const AttendingMetricsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final _blocks = ref.watch(blocksListProvider);
    final _selected = ref.watch(selectedBlocksProvider);
    final range = ref.watch(selectedBlocksDateRangeProvider);
    final statsAsync = ref.watch(_attendingStatsProvider((uid ?? '', range)));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Attending Metrics', style: Theme.of(context).textTheme.displayMedium),
          TextButton.icon(onPressed: () => _openBlocksSheet(context, ref), icon: const Icon(Icons.filter_list), label: const Text('Select Blocks')),
        ]),
        const SizedBox(height: 12),
        statsAsync.when(
          loading: () => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('Current Block Completion %'), SizedBox(height: 8), ShimmerBox(width: 120, height: 24),
          ]))),
          error: (e, _) => Text('Error: $e'),
          data: (s) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Current Block Completion %'), const SizedBox(height: 8), Text('${s.completionPct.toStringAsFixed(0)}%'),
          ]))),
        ),
        const SizedBox(height: 12),
        statsAsync.when(
          data: (s) => Wrap(spacing: 12, runSpacing: 12, children: [
            _MetricCard(title: 'Completed Reviews', value: s.completed.toString()),
            _MetricCard(title: 'Pending Reviews', value: s.pending.toString()),
          ]),
          loading: () => const Wrap(spacing: 12, runSpacing: 12, children: [
            _MetricCard(title: 'Completed Reviews'), _MetricCard(title: 'Pending Reviews'),
          ]),
          error: (e, _) => Text('Error: $e'),
        ),
        const SizedBox(height: 24),
        Text('Assigned Residents', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        statsAsync.when(
          data: (s) => Column(children: [
            for (final r in s.byResident.entries)
              ListTile(
                title: Text(r.key),
                subtitle: LinearProgressIndicator(value: r.value.total == 0 ? 0.0 : r.value.done / r.value.total),
                trailing: Text('${r.value.done}/${r.value.total}'),
              ),
          ]),
          loading: () => const ShimmerBox(width: 200, height: 24),
          error: (e, _) => Text('Error: $e'),
        ),
      ],
    );
  }

  void _openBlocksSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final blocks = ref.read(blocksListProvider).maybeWhen(data: (b) => b, orElse: () => <dynamic>[]);
        final selected = ref.read(selectedBlocksProvider);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final b in blocks)
              CheckboxListTile(
                value: selected.contains(b.id),
                onChanged: (_) => ref.read(selectedBlocksProvider.notifier).toggle(b.id),
                title: Text(b.name ?? b.id),
              ),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Apply')),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String? value;
  const _MetricCard({required this.title, this.value});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            value == null ? const ShimmerBox(width: 100, height: 24) : Text(value!, style: Theme.of(context).textTheme.titleLarge),
          ]),
        ),
      ),
    );
  }
}

class _AttendingStats {
  final int total;
  final int completed;
  final int pending;
  final double completionPct;
  final Map<String, _ResidentProgress> byResident;
  _AttendingStats({required this.total, required this.completed, required this.pending, required this.completionPct, required this.byResident});
}

class _ResidentProgress { final int total; final int done; const _ResidentProgress(this.total, this.done); }

final _attendingStatsProvider = FutureProvider.family<_AttendingStats, (String, DateRange?)>((ref, args) async {
  final (uid, range) = args;
  if (uid.isEmpty) return _AttendingStats(total: 0, completed: 0, pending: 0, completionPct: 0, byResident: {});
  Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('Schedules')
    .where('attending_ref', isEqualTo: FirebaseFirestore.instance.doc('users/$uid'));
  if (range != null) {
    q = q.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(range.start)).where('date', isLessThanOrEqualTo: Timestamp.fromDate(range.end));
  }
  q = q.orderBy('date', descending: true);
  final snap = await q.get();
  int total = snap.docs.length;
  int done = 0;
  final map = <String, _ResidentProgress>{};
  for (final d in snap.docs) {
    final data = d.data();
    final isDone = data['attendee_evaluation_status'] == 'done';
    if (isDone) done++;
    final residentName = data['resident_name']?.toString() ?? (data['resident_ref'] as DocumentReference?)?.id ?? 'Resident';
    final prev = map[residentName] ?? const _ResidentProgress(0, 0);
    map[residentName] = _ResidentProgress(prev.total + 1, prev.done + (isDone ? 1 : 0));
  }
  final pending = total - done;
  final pct = total == 0 ? 0.0 : (done / total) * 100.0;
  return _AttendingStats(total: total, completed: done, pending: pending, completionPct: pct, byResident: map);
});
