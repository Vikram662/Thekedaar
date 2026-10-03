import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/widgets/common.dart';

/// PRD I-S1 / I-T4: monthly salary divisor and weekly off.
class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key});

  static const _weekdays = {
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
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
      appBar: AppBar(title: const Text('Work rules')),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          const SectionTitle('Monthly salary → per-day rate'),
          const Text(
            'Used for new monthly workers. Each worker can be changed from '
            'their wage screen.',
            style: TextStyle(color: AppColors.slate600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: AppSizes.gap,
            children: [
              for (final (value, label) in const [
                (30, 'Salary ÷ 30'),
                (26, 'Salary ÷ 26'),
                (0, 'Salary ÷ days in month'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: settings.monthlyDivisor == value,
                  onSelected: (_) =>
                      save(settings.copyWith(monthlyDivisor: value)),
                ),
            ],
          ),
          const SectionTitle('Weekly off'),
          const Text(
            'On this day "Mark all" marks Off. Weekly off is paid for '
            'monthly workers, unpaid for daily workers.',
            style: TextStyle(color: AppColors.slate600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: AppSizes.gap,
            runSpacing: AppSizes.gap,
            children: [
              ChoiceChip(
                label: const Text('None'),
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
