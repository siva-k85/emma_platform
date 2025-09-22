import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../data/repos/topics_repo.dart';
import '../../data/models/schedule.dart';
import 'likert_selector.dart';

class EvaluationFormScreen extends ConsumerStatefulWidget {
  final String scheduleId;
  const EvaluationFormScreen({super.key, required this.scheduleId});
  @override
  ConsumerState<EvaluationFormScreen> createState() => _EvaluationFormScreenState();
}

class _EvaluationFormScreenState extends ConsumerState<EvaluationFormScreen> {
  Map<String, int> scores = {}; // topicId/subtopicId -> 1..5
  final residentComment = TextEditingController();
  final attendingComment = TextEditingController();
  final attendingSuggestion = TextEditingController();
  bool verbalFeedback = false;
  bool feedbackUtilized = false;
  Timer? _debounce;
  bool _submitted = false;
  bool _loading = true;
  Schedule? _schedule;
  List<Map<String, dynamic>> _rubrics = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await FirebaseFirestore.instance.collection('Schedules').doc(widget.scheduleId).get();
    final schedule = Schedule.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>);
    final topicsRepo = TopicsRepo();
    final List<Map<String, dynamic>> rubrics = [];
    for (final t in schedule.topics) {
      final topic = await topicsRepo.getTopicById(t);
      if (topic != null) {
        rubrics.add({'id': t, 'title': topic['title'] ?? t, 'labels': (topic['likert_labels'] as List?)?.map((e) => e.toString()).toList() ?? const ['Novice', '2', '3', '4', 'Expert'], 'description': topic['description']});
        final subs = await topicsRepo.getSubtopics(t);
        for (final s in subs) {
          rubrics.add({'id': s['id']?.toString() ?? '${t}_${s['title']}', 'title': s['title']?.toString() ?? 'Subtopic', 'labels': (s['likert_labels'] as List?)?.map((e) => e.toString()).toList() ?? const ['1','2','3','4','5'], 'description': s['description']});
        }
      }
    }
    setState(() {
      _schedule = schedule;
      _rubrics = rubrics;
      _loading = false;
    });
  }

  void _autoSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () async {
      final mode = _mode();
      final payload = _payload(mode, draft: true);
      await FirebaseFirestore.instance.collection('Schedules').doc(widget.scheduleId).set(payload, SetOptions(merge: true));
      if (mounted) setState(() {});
    });
  }

  String _mode() {
    final u = ref.read(firebaseAuthProvider).currentUser;
    // If current user matches resident_ref, treat as resident self eval, else attending
    if (_schedule?.residentRef.id == u?.uid) return 'resident';
    return 'attending';
  }

  Map<String, dynamic> _payload(String mode, {bool draft = false}) {
    if (mode == 'resident') {
      return {
        'resident_evaluation': {
          'scores': scores,
          'interesting_cases': residentComment.text,
          'verbal_feedback_delivered': verbalFeedback,
          'feedback_utilized': feedbackUtilized,
          'updated_at': FieldValue.serverTimestamp(),
        },
        if (!draft) 'resident_evaluation_status': 'done',
      };
    }
    return {
      'attendee_evaluation': {
        'scores': scores,
        'performance_comment': attendingComment.text,
        'suggestion_comment': attendingSuggestion.text,
        'verbal_feedback_delivered': verbalFeedback,
        'updated_at': FieldValue.serverTimestamp(),
      },
      if (!draft) 'attendee_evaluation_status': 'done',
    };
  }

  Future<void> _submit() async {
    final mode = _mode();
    final payload = _payload(mode, draft: false);
    await FirebaseFirestore.instance.collection('Schedules').doc(widget.scheduleId).set(payload, SetOptions(merge: true));
    setState(() => _submitted = true);
  }

  @override
  void dispose() {
    residentComment.dispose();
    attendingComment.dispose();
    attendingSuggestion.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _schedule == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final mode = _mode();
    final isResident = mode == 'resident';
    final schedule = _schedule!;
    final submittedReadOnly = (isResident && schedule.attendingEvalStatus == 'done') || (!isResident && schedule.residentEvalStatus == 'done') || _submitted;
    return Scaffold(
      appBar: AppBar(title: const Text('Evaluation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${schedule.date.toLocal().toString().split(' ').first} • ${(schedule.shiftStart ?? schedule.date).toLocal().toString().substring(11,16)}–${(schedule.shiftEnd ?? schedule.date).toLocal().toString().substring(11,16)}'),
                const SizedBox(height: 4),
                Text('Resident: ${schedule.residentName ?? schedule.residentRef.id}'),
                Text('Attending: ${schedule.attendingName ?? schedule.attendingRef?.id ?? 'TBD'}'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [for (final t in schedule.topics) Chip(label: Text(t))]),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          for (final r in _rubrics)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r['title']?.toString() ?? 'Topic', style: Theme.of(context).textTheme.titleLarge),
                  if (r['description'] != null) ...[
                    const SizedBox(height: 4),
                    Text(r['description'].toString()),
                  ],
                  const SizedBox(height: 12),
                  LikertSelector(
                    value: scores[r['id']?.toString()],
                    labels: (r['labels'] as List).map((e) => e.toString()).toList(),
                    onChanged: submittedReadOnly ? (_) {} : (v) { setState(() => scores[r['id']!.toString()] = v); _autoSave(); },
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 8),
          if (isResident) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Interesting cases'),
                  TextField(controller: residentComment, onChanged: (_) => _autoSave(), maxLines: 3, minLines: 2),
                  const SizedBox(height: 12),
                  CheckboxListTile(value: verbalFeedback, onChanged: submittedReadOnly ? null : (v) { setState(() => verbalFeedback = v ?? false); _autoSave(); }, title: const Text('Verbal feedback delivered')),
                  CheckboxListTile(value: feedbackUtilized, onChanged: submittedReadOnly ? null : (v) { setState(() => feedbackUtilized = v ?? false); _autoSave(); }, title: const Text('Feedback utilized')),
                ]),
              ),
            ),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Performance comment'),
                  TextField(controller: attendingComment, onChanged: (_) => _autoSave(), maxLines: 3, minLines: 2),
                  const SizedBox(height: 12),
                  const Text('Suggestion comment'),
                  TextField(controller: attendingSuggestion, onChanged: (_) => _autoSave(), maxLines: 3, minLines: 2),
                  const SizedBox(height: 12),
                  CheckboxListTile(value: verbalFeedback, onChanged: submittedReadOnly ? null : (v) { setState(() => verbalFeedback = v ?? false); _autoSave(); }, title: const Text('Verbal feedback delivered')),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: submittedReadOnly ? null : _submit,
            child: Text(_submitted ? 'Submitted' : 'Submit'),
          ),
        ],
      ),
    );
  }
}
