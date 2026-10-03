import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/notify/notifications.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/widgets/common.dart';

final _notificationsEnabledProvider = FutureProvider.autoDispose<bool>(
  (ref) => AppNotifications.instance.enabled(),
);

/// PRD DB-07: choose which reminder notifications to get.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final enabled = ref.watch(_notificationsEnabledProvider).valueOrNull;
    if (settings == null) {
      return const SkeletonPage();
    }
    final r = settings.reminders;
    Future<void> save(ReminderSettings value) => ref
        .read(settingsRepositoryProvider)
        .saveSettings(settings.copyWith(reminders: value));

    Widget toggle(
      IconData icon,
      String title,
      String subtitle,
      bool value,
      ReminderSettings Function(bool) update,
    ) =>
        SwitchListTile(
          secondary: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: (v) => save(update(v)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: ListView(
        children: [
          if (enabled == false)
            Padding(
              padding: const EdgeInsets.all(AppSizes.gutter),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.notifications_off,
                            color: AppColors.warningText),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Notifications are off for this app',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Turn them on to get the reminders below. If nothing '
                      'happens, allow notifications in phone Settings → Apps '
                      '→ Thekedaar.',
                      style: TextStyle(color: AppColors.slate600),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await AppNotifications.instance.requestPermission();
                        ref.invalidate(_notificationsEnabledProvider);
                      },
                      icon: const Icon(Icons.notifications_active),
                      label: const Text('Turn on notifications'),
                    ),
                  ],
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Reminders come at most once a day, between 9 am and 9 pm.',
              style: TextStyle(color: AppColors.slate600),
            ),
          ),
          toggle(
            Icons.cloud_off,
            'Backup problems',
            'Backup failed twice, not done for 24 hours, or phone time wrong',
            r.backup,
            (v) => r.copyWith(backup: v),
          ),
          toggle(
            Icons.request_quote,
            'Overdue bills',
            'Bills past their due date that are not fully paid',
            r.overdueBills,
            (v) => r.copyWith(overdueBills: v),
          ),
          toggle(
            Icons.event_available,
            'Month-end settlement',
            'Last day of the month: settle workers\' khata',
            r.monthEnd,
            (v) => r.copyWith(monthEnd: v),
          ),
          toggle(
            Icons.celebration,
            'Holidays',
            'The day before a holiday you added',
            r.holidays,
            (v) => r.copyWith(holidays: v),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Send a test notification'),
            onTap: () async {
              await AppNotifications.instance.requestPermission();
              await AppNotifications.instance.show(
                NotificationKind.monthEnd,
                'Thekedaar',
                'Reminders are working.',
              );
              ref.invalidate(_notificationsEnabledProvider);
              if (context.mounted) showMessage(context, 'Test sent');
            },
          ),
        ],
      ),
    );
  }
}
