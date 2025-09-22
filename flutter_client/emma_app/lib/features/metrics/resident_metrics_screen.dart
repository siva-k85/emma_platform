import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/blocks/providers.dart';
import '../../core/loading.dart';
import '../../theme/tokens.dart';
import 'resident_metrics_provider.dart';
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
        Consumer(builder: (context, ref, _) {
          final metrics = ref.watch(residentMetricsProvider);
          return metrics.when(
            loading: () => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('Evaluation Completion Rate', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              ShimmerBox(width: 220, height: 20),
              SizedBox(height: 8),
              Text('Attendings Range: 0% – 100%', style: TextStyle(color: AppColors.textSecondary)),
            ]))),
            error: (e, _) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Error loading metrics: $e'))),
            data: (m) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Evaluation Completion Rate', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('Your Completion Rate: ${m.completionPct.toStringAsFixed(0)}%'),
                  const SizedBox(height: 8),
                  const Text('Attendings Range: 0% – 100%', style: TextStyle(color: AppColors.textSecondary)),
                ]),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        Consumer(builder: (context, ref, _) {
          final metrics = ref.watch(residentMetricsProvider);
          return metrics.when(
            loading: () => const Wrap(spacing: 12, runSpacing: 12, children: [
              _MetricCard(title: 'Average Self-Evaluation Score'),
              _MetricCard(title: 'Average Attending Evaluation Score'),
              _MetricCard(title: 'Evaluations Completed: Incomplete'),
              _MetricCard(title: 'Percentile Rank within PGY cohort'),
            ]),
            error: (e, _) => Text('Error: $e'),
            data: (m) => Wrap(spacing: 12, runSpacing: 12, children: [
              _MetricCard(title: 'Average Self-Evaluation Score', value: m.avgSelf?.toStringAsFixed(2) ?? '—'),
              _MetricCard(title: 'Average Attending Evaluation Score', value: m.avgAttending?.toStringAsFixed(2) ?? '—'),
              _MetricCard(title: 'Evaluations Completed: Incomplete', value: '${m.residentCompletedCount} : ${m.pendingCount}'),
              _MetricCard(title: 'Percentile Rank within PGY cohort', value: m.pgyPercentile == null ? '—' : '${m.pgyPercentile!.toStringAsFixed(0)}%'),
            ]),
          );
        }),
        const SizedBox(height: 24),
        Text('Topic-wise Metrics', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Consumer(builder: (context, ref, _) {
          final metrics = ref.watch(residentMetricsProvider);
          return metrics.when(
            loading: () => const _TopicListShimmer(),
            error: (e, _) => Text('Error: $e'),
            data: (m) {
              final entries = m.topicAvgs.entries.toList()
                ..sort((a, b) => (a.key).compareTo(b.key));
              if (entries.isEmpty) return const Text('No topics in selected range');
              return Column(children: [
                for (final e in entries)
                  ListTile(
                    title: Text(e.key),
                    subtitle: Text('Self: ${e.value.selfAvg?.toStringAsFixed(2) ?? '—'}   Attending: ${e.value.attendingAvg?.toStringAsFixed(2) ?? '—'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pushNamed('/topic/${e.key}'),
                  ),
              ]);
            },
          );
        }),
        const SizedBox(height: 24),
        Text('General Suggestions from Attending', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Consumer(builder: (context, ref, _) {
          final metrics = ref.watch(residentMetricsProvider);
          return metrics.when(
            loading: () => const SuggestionShimmers(),
            error: (e, _) => Text('Error: $e'),
            data: (m) {
              if (m.suggestions.isEmpty) return const Text('No suggestions yet');
              return Column(children: [
                for (final s in m.suggestions)
                  SuggestionCard(text: s.text, timestamp: s.timestamp, author: s.author),
              ]);
            },
          );
        }),
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
            const SizedBox(height: 4),
            const ShimmerBox(width: 160, height: 14),
          ]),
        ),
      ),
    );
  }
}

class _TopicListShimmer extends StatelessWidget {
  const _TopicListShimmer();
  @override
  Widget build(BuildContext context) {
    return Column(children: const [
      ShimmerBox(width: 240, height: 16),
      SizedBox(height: 8),
      ShimmerBox(width: 260, height: 16),
    ]);
  }
}
