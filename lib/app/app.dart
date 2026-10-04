import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/backup/backup_providers.dart';
import '../core/db/providers.dart';
import '../core/notify/notifications.dart';
import '../core/update/app_update.dart';
import '../features/lock/lock_screens.dart';
import '../features/subscription/subscription_controller.dart';
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
    ref: ref,
    initialLocation:
        widget.needsOnboarding ? Routes.onboarding : Routes.dashboard,
  );

  @override
  void initState() {
    super.initState();
    // Auto backup triggers live as long as this app scope (PRD D3.1).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(backupCoordinatorProvider).start();
      ref.read(subscriptionControllerProvider.notifier).refresh();
      ref.read(subscriptionServiceProvider).startFcmTokenSync();
      const AppUpdateChecker().check(context);
    });
    final notifications = AppNotifications.instance;
    notifications.tapped.addListener(_onNotificationTapped);
    notifications.initForApp().then((_) => _openTappedNotification());
  }

  /// Opens the screen a notification is about. Behind the lock screen the
  /// page is already open when the user unlocks.
  void _onNotificationTapped() => _openTappedNotification();

  Future<void> _openTappedNotification() async {
    final kind = AppNotifications.instance.tapped.value;
    if (kind == null || !mounted) return;
    // On a cold start the profile may still be loading; before onboarding
    // there is nothing to open.
    final profile = await ref.read(businessProfileProvider.future);
    if (profile == null || !mounted) return;
    if (AppNotifications.instance.tapped.value != kind) return;
    AppNotifications.instance.tapped.value = null;
    final route = switch (kind) {
      NotificationKind.backupFailed ||
      NotificationKind.backupPending ||
      NotificationKind.clockWrong ||
      NotificationKind.backupProgress =>
        Routes.backup,
      NotificationKind.overdueBills => Routes.dues(),
      NotificationKind.monthEnd => Routes.khataTab(0),
      NotificationKind.holiday => Routes.attendanceMonth,
      NotificationKind.taskReminder => Routes.tasks,
    };
    // Tabs (khata, attendance) are switched with go; others open on top.
    if (route.startsWith('/khata') || route.startsWith('/attendance')) {
      _router.go(route);
    } else {
      _router.go(Routes.dashboard);
      _router.push(route);
    }
  }

  @override
  void dispose() {
    AppNotifications.instance.tapped.removeListener(_onNotificationTapped);
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
      builder: (context, child) => LockGate(
        // Pull down on any screen's list to refresh it (all screens re-read
        // the database). Only vertical scrolling triggers it.
        child: RefreshIndicator(
          color: AppColors.blue700,
          edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
          notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
          onRefresh: () => ref.read(backupCoordinatorProvider).refreshAll(),
          child: child ?? const SizedBox(),
        ),
      ),
    );
  }
}
