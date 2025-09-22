import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/blocks/providers.dart';
import '../../core/loading.dart';
import '../../theme/tokens.dart';
import 'widgets/suggestion_card.dart';

class ResidentMetricsScreen extends ConsumerWidget {
  const ResidentMetricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocksAsync = ref.watch(blocksListProvider);
    final selected = ref.watch(selectedBlocksProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('User Metrics', style: Theme.of(context).textTheme.displayMedium),
            TextButton.icon(onPressed: () => _openBlocksSheet(context, ref), icon: const Icon(Icons.filter_list), label: const Text('Select Blocks')),
          ],
        ),
        const SizedBox(height: 8),
        blocksAsync.when(
          loading: () => const ShimmerBox(width: 220, height: 28, borderRadius: BorderRadius.all(Radius.circular(8))),
          error: (e, _) => Text('Blocks error: $e'),
          data: (blocks) {
            final chips = blocks.map((b) => Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: FilterChip(
                label: Text(b.name ?? b.id),
                selected: selected.contains(b.id),
                onSelected: (_) => ref.read(selectedBlocksProvider.notifier).toggle(b.id),
              ),
            ));
            return Wrap(children: chips.toList());
          },
        ),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('Evaluation Completion Rate', style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          ShimmerBox(width: 220, height: 20),
          SizedBox(height: 8),
          Text('Attendings Range: 0% – 100%', style: TextStyle(color: AppColors.textSecondary)),
        ]))),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: const [
          _MetricCard(title: 'Average Self-Evaluation Score'),
          _MetricCard(title: 'Average Attending Evaluation Score'),
          _MetricCard(title: 'Evaluations Completed: Incomplete'),
          _MetricCard(title: 'Percentile Rank within PGY cohort'),
        ]),
        const SizedBox(height: 24),
        Text('General Suggestions from Attending', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const SuggestionShimmers(),
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
                subtitle: Text('${b.start.toLocal().toString().split(' ').first} → ${b.end.toLocal().toString().split(' ').first}'),
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
  const _MetricCard({required this.title});
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
            const ShimmerBox(width: 100, height: 24),
            const SizedBox(height: 4),
            const ShimmerBox(width: 160, height: 14),
          ]),
        ),
      ),
    );
  }
}
