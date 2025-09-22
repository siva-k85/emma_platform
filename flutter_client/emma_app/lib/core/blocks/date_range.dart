import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

class DateRange {
  final DateTime start;
  final DateTime end;
  const DateRange(this.start, this.end);
}

final selectedBlocksDateRangeProvider = Provider<DateRange?>((ref) {
  final blocksAsync = ref.watch(blocksListProvider);
  final selected = ref.watch(selectedBlocksProvider);
  return blocksAsync.maybeWhen(
    data: (blocks) {
      if (selected.isEmpty && blocks.isEmpty) return null;
      final chosen = selected.isEmpty ? blocks : blocks.where((b) => selected.contains(b.id)).toList();
      if (chosen.isEmpty) return null;
      chosen.sort((a, b) => a.start.compareTo(b.start));
      final start = chosen.first.start;
      final end = chosen.map((b) => b.end).reduce((a, b) => a.isAfter(b) ? a : b);
      return DateRange(start, end);
    },
    orElse: () => null,
  );
});

