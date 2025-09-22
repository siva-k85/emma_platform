import 'package:flutter/material.dart';

class SuggestionCard extends StatelessWidget {
  final String text;
  final DateTime? timestamp;
  final String? author;
  const SuggestionCard({super.key, required this.text, this.timestamp, this.author});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (author != null || timestamp != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (author != null) Text(author!, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (timestamp != null) Text(timestamp!.toLocal().toString().split('.').first, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          if (author != null || timestamp != null) const SizedBox(height: 8),
          Text(text),
        ]),
      ),
    );
  }
}

class SuggestionShimmers extends StatelessWidget {
  const SuggestionShimmers();
  @override
  Widget build(BuildContext context) {
    return Column(children: const [
      _LineBox(),
      _LineBox(),
    ]);
  }
}

class _LineBox extends StatelessWidget {
  const _LineBox();
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          SizedBox(height: 6),
          _GreyBox(width: 240, height: 14),
          SizedBox(height: 6),
          _GreyBox(width: 180, height: 14),
        ]),
      ),
    );
  }
}

class _GreyBox extends StatelessWidget {
  final double width;
  final double height;
  const _GreyBox({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(width: width, height: height, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)));
  }
}
