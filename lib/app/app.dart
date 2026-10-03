import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/backup/backup_providers.dart';
import '../features/lock/lock_screens.dart';
import 'router.dart';
import 'theme.dart';

class ThekedaarApp extends ConsumerStatefulWidget {
  const ThekedaarApp({super.key, required this.needsOnboarding});

  /// True on first launch, before the business profile exists.
  final bool needsOnboarding;

  @override
  ConsumerState<ThekedaarApp> createState() => _ThekedaarAppState();
}

class _ThekedaarAppState extends ConsumerState<ThekedaarApp> {
  late final GoRouter _router = buildRouter(
    initialLocation:
        widget.needsOnboarding ? Routes.onboarding : Routes.dashboard,
  );

  @override
  void initState() {
    super.initState();
    // Auto backup triggers live as long as this app scope (PRD D3.1).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(backupCoordinatorProvider).start();
    });
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Thekedaar',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      routerConfig: _router,
      builder: (context, child) => LockGate(child: child ?? const SizedBox()),
    );
  }
}
