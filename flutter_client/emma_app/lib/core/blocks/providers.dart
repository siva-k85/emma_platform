import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/repos/blocks_repo.dart';
import '../../data/models/block.dart';

final blocksRepoProvider = Provider((ref) => BlocksRepo());

final blocksListProvider = FutureProvider<List<BlockTime>>((ref) async {
  final now = DateTime.now();
  // If block_time has year field, use it; otherwise load all and filter by dates
  final docs = await ref.read(blocksRepoProvider).listAcademicBlocks(now.year).catchError((_) => <QueryDocumentSnapshot<Map<String, dynamic>>>[]);
  if (docs.isNotEmpty) {
    return docs.map(BlockTime.fromFirestore).toList();
  }
  // Fallback: fetch all without year filter
  final snap = await FirebaseFirestore.instance.collection('block_time').orderBy('start').get();
  return snap.docs.map((d) => BlockTime.fromFirestore(d)).toList();
});

class SelectedBlocksNotifier extends StateNotifier<Set<String>> {
  SelectedBlocksNotifier() : super({});
  void setAll(Iterable<String> ids) => state = {...ids};
  void toggle(String id) {
    if (state.contains(id)) {
      final ns = Set<String>.from(state);
      ns.remove(id);
      state = ns;
    } else {
      state = {...state, id};
    }
  }
  void clear() => state = {};
}

final selectedBlocksProvider = StateNotifierProvider<SelectedBlocksNotifier, Set<String>>((ref) => SelectedBlocksNotifier());

final currentBlockProvider = Provider<BlockTime?>((ref) {
  final blocks = ref.watch(blocksListProvider).maybeWhen(data: (b) => b, orElse: () => <BlockTime>[]);
  final now = DateTime.now();
  BlockTime? current = blocks.firstWhere((b) => !now.isBefore(b.start) && !now.isAfter(b.end), orElse: () => blocks.isNotEmpty ? blocks.first : BlockTime(id: 'N/A', start: now, end: now));
  if (current.id == 'N/A') return null;
  return current;
});
