import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/widgets/common.dart';

/// PRD I-S1 / I-T4: monthly salary divisor and weekly off.
class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key});

  static Map<int, String> get _weekdays => {
    DateTime.monday: tr('Monday'),
    DateTime.tuesday: tr('Tuesday'),
    DateTime.wednesday: tr('Wednesday'),
    DateTime.thursday: tr('Thursday'),
    DateTime.friday: tr('Friday'),
    DateTime.saturday: tr('Saturday'),
    DateTime.sunday: tr('Sunday'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    if (settings == null) {
      return const SkeletonPage();
    }
    Future<void> save(AppSettings s) =>
        ref.read(settingsRepositoryProvider).saveSettings(s);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Work rules'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          SectionTitle(tr('Monthly salary → per-day rate')),
          Text(
            tr('Used for new monthly workers. Each worker can be changed from their wage screen.'),
            style: TextStyle(color: AppColors.slate600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: AppSizes.gap,
            children: [
              for (final (value, label) in [
                (30, tr('Salary ÷ 30')),
                (26, tr('Salary ÷ 26')),
                (0, tr('Salary ÷ days in month')),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: settings.monthlyDivisor == value,
                  onSelected: (_) =>
                      save(settings.copyWith(monthlyDivisor: value)),
                ),
            ],
          ),
          SectionTitle(tr('Weekly off')),
          Text(
            tr('On this day "Mark all" marks Off. Weekly off is paid for monthly workers, unpaid for daily workers.'),
            style: TextStyle(color: AppColors.slate600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: AppSizes.gap,
            runSpacing: AppSizes.gap,
            children: [
              ChoiceChip(
                label: Text(tr('None')),
                selected: settings.weeklyOffDay == null,
                onSelected: (_) =>
                    save(settings.copyWith(weeklyOffDay: () => null)),
              ),
              for (final entry in _weekdays.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: settings.weeklyOffDay == entry.key,
                  onSelected: (_) =>
                      save(settings.copyWith(weeklyOffDay: () => entry.key)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
