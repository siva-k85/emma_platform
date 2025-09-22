import 'package:flutter/material.dart';

class LikertSelector extends StatelessWidget {
  final int? value;
  final void Function(int) onChanged;
  final List<String> labels; // 1..5 labels
  const LikertSelector({super.key, required this.value, required this.onChanged, required this.labels});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 1; i <= 5; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                selected: value == i,
                onSelected: (_) => onChanged(i),
                label: Column(children: [Text('$i'), if (labels.length >= i) Text(labels[i - 1], style: const TextStyle(fontSize: 10))]),
              ),
            ),
          ),
      ],
    );
  }
}

