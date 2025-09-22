import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/providers.dart';
import '../../core/loading.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(appUserProvider);
    return appUser.when(
      loading: () => const Center(child: ShimmerBox(width: 120, height: 120, borderRadius: BorderRadius.all(Radius.circular(60)))),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (u) {
        if (u == null) return const Center(child: Text('No profile'));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CircleAvatar(radius: 40, backgroundImage: u.photoUrl != null ? NetworkImage(u.photoUrl!) : null, child: u.photoUrl == null ? const Icon(Icons.person) : null),
            const SizedBox(height: 12),
            Text(u.name ?? u.email ?? 'User', style: Theme.of(context).textTheme.titleLarge),
            if (u.pgy != null) Text('PGY ${u.pgy}'),
            if (u.department != null) Text(u.department!),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Notifications'),
              value: true,
              onChanged: (_) {},
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => fb_auth.FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout), label: const Text('Sign out')),
          ],
        );
      },
    );
  }
}

