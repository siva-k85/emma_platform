import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 5, vsync: this);
  static const tabs = ['Users', 'Schedules', 'Reviews', 'Blocks', 'Topics'];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin'), bottom: TabBar(controller: _tab, tabs: [for (final t in tabs) Tab(text: t)])),
      body: TabBarView(
        controller: _tab,
        children: const [
          _UsersTab(),
          _SchedulesTab(),
          _ReviewsTab(),
          _BlocksTab(),
          _TopicsTab(),
        ],
      ),
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab();
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search users'), onChanged: (v) => setState(() => q = v.trim().toLowerCase())),
      ),
      Expanded(
        child: StreamBuilder(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final items = snap.data!.docs.map((d) => d.data()).where((u) {
              final name = (u['name'] ?? '').toString().toLowerCase();
              final email = (u['email'] ?? '').toString().toLowerCase();
              return q.isEmpty || name.contains(q) || email.contains(q);
            }).toList();
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (c, i) {
                final u = items[i];
                return ListTile(
                  title: Text(u['name']?.toString() ?? u['email']?.toString() ?? 'User'),
                  subtitle: Text('Role: ${u['role'] ?? 'resident'}${u['PGY'] != null ? ' • PGY ${u['PGY']}' : ''}'),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

class _SchedulesTab extends StatelessWidget {
  const _SchedulesTab();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('Schedules').orderBy('date', descending: true).limit(100).snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (c, i) {
            final d = docs[i].data();
            final ts = (d['date'] as Timestamp?)?.toDate();
            final topics = (d['topics'] as List?)?.join(', ') ?? '';
            final conflict = d['isConflict'] == true;
            return ListTile(
              title: Text('${ts?.toLocal().toString().split(' ').first ?? ''} • ${d['resident_name'] ?? d['resident_ref'] ?? ''}'),
              subtitle: Text('Attending: ${d['attending_name'] ?? ''}\nTopics: $topics'),
              isThreeLine: true,
              trailing: conflict ? const Chip(label: Text('Conflict'), backgroundColor: Color(0xFFFFEBEE)) : null,
            );
          },
        );
      },
    );
  }
}

class _ReviewsTab extends StatefulWidget {
  const _ReviewsTab();
  @override
  State<_ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends State<_ReviewsTab> {
  final _selection = <String>{};
  bool _approving = false;

  Future<void> _approveSelected() async {
    setState(() => _approving = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('api');
      for (final id in _selection) {
        await callable.call({'callName': 'approveReview', 'variables': {'reviewId': id}});
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Approved selected reviews')));
      setState(() => _selection.clear());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approve failed: $e')));
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unapprovedQuery = FirebaseFirestore.instance.collection('evaluations').where('approved', isEqualTo: false);
    final approvedQuery = FirebaseFirestore.instance.collection('evaluations').where('approved', isEqualTo: true);
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const TabBar(tabs: [Tab(text: 'Unapproved'), Tab(text: 'Approved')]),
        Expanded(
          child: TabBarView(children: [
            Column(children: [
              if (_selection.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: FilledButton.icon(onPressed: _approving ? null : _approveSelected, icon: const Icon(Icons.check), label: Text(_approving ? 'Approving...' : 'Approve Selected')),
                ),
              Expanded(
                child: StreamBuilder(
                  stream: unapprovedQuery.snapshots(),
                  builder: (context, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) return const Center(child: Text('No unapproved reviews'));
                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (c, i) {
                        final d = docs[i]; final data = d.data();
                        final checked = _selection.contains(d.id);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (v) => setState(() => v == true ? _selection.add(d.id) : _selection.remove(d.id)),
                          title: Text('Eval ${d.id} • ${data['evaluator_type'] ?? ''}'),
                          subtitle: Text(data['additional_comments']?.toString() ?? ''),
                          secondary: IconButton(icon: const Icon(Icons.check), onPressed: _approving ? null : () async { setState(() => _selection.add(d.id)); await _approveSelected(); }),
                        );
                      },
                    );
                  },
                ),
              ),
            ]),
            // Approved
            StreamBuilder(
              stream: approvedQuery.snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Center(child: Text('No approved reviews'));
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (c, i) {
                    final d = docs[i]; final data = d.data();
                    return ListTile(
                      title: Text('Eval ${d.id} • ${data['evaluator_type'] ?? ''}'),
                      subtitle: Text(data['additional_comments']?.toString() ?? ''),
                    );
                  },
                );
              },
            ),
          ]),
        ),
      ]),
    );
  }
}

class _BlocksTab extends StatelessWidget {
  const _BlocksTab();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('block_time').orderBy('start').snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (c, i) {
            final d = docs[i].data();
            final start = (d['start'] as Timestamp?)?.toDate();
            final end = (d['end'] as Timestamp?)?.toDate();
            return ListTile(
              title: Text(d['name']?.toString() ?? docs[i].id),
              subtitle: Text('${start?.toLocal().toString().split(' ').first ?? ''} → ${end?.toLocal().toString().split(' ').first ?? ''}'),
            );
          },
        );
      },
    );
  }
}

class _TopicsTab extends StatelessWidget {
  const _TopicsTab();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('Topics').orderBy('title').snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (c, i) {
            final d = docs[i].data();
            return ListTile(title: Text(d['title']?.toString() ?? 'Topic'), subtitle: Text(d['description']?.toString() ?? ''));
          },
        );
      },
    );
  }
}
