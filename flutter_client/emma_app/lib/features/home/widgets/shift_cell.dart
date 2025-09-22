import 'package:flutter/material.dart';
import '../../../data/models/schedule.dart';

class ShiftCell extends StatelessWidget {
  final Schedule s;
  final VoidCallback? onTap;
  const ShiftCell({super.key, required this.s, this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = s.derivedStatus();
    final statusText = () {
      switch (status) {
        case EvalStatus.pending:
          return 'Pending';
        case EvalStatus.selfDone:
          return 'Self Done';
        case EvalStatus.attendingDone:
          return 'Attending Done';
        case EvalStatus.complete:
          return 'Complete';
      }
    }();
    final statusColor = () {
      switch (status) {
        case EvalStatus.pending:
          return Colors.orange;
        case EvalStatus.selfDone:
          return Colors.blue;
        case EvalStatus.attendingDone:
          return Colors.teal;
        case EvalStatus.complete:
          return Colors.green;
      }
    }();
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text('${s.date.toLocal().toString().split(" ").first} • ${(s.shiftStart ?? s.date).toLocal().toString().substring(11,16)}–${(s.shiftEnd ?? s.date).toLocal().toString().substring(11,16)}'),
        subtitle: Text('Attending: ${s.attendingName ?? s.attendingRef?.id ?? 'TBD'}\nTopics: ${s.topics.join(', ')}'),
        isThreeLine: true,
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Chip(label: Text(statusText), backgroundColor: statusColor.withOpacity(.15), labelStyle: TextStyle(color: statusColor)),
            if (s.isConflict) const SizedBox(height: 6),
            if (s.isConflict) const Chip(label: Text('Conflict'), backgroundColor: Color(0xFFFFEBEE), labelStyle: TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

