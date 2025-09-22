import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'resident_home_list.dart';

class ResidentHomeShell extends StatelessWidget {
  final Widget? child;
  const ResidentHomeShell({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    final currentIndex = loc.contains('/metrics') ? 0 : loc.contains('/profile') ? 2 : 1;
    return Scaffold(
      body: child ?? const ResidentHomeList(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/home/resident/metrics');
              break;
            case 1:
              context.go('/home/resident/home');
              break;
            case 2:
              context.go('/home/resident/profile');
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Metrics'),
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
