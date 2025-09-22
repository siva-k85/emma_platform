import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/theme.dart';
import 'routing/router.dart';

class EmmaApp extends ConsumerWidget {
  const EmmaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'EMMA',
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}

