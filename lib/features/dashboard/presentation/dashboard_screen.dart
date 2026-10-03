import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/widgets/coming_soon.dart';

/// PRD E2 Dashboard. Only "Add Worker" works so far; the rest are stubs.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    final textTheme = Theme.of(context).textTheme;
    final trades = profile == null ? <Trade>{} : Trade.decode(profile.trades);

    return Scaffold(
      appBar: AppBar(title: Text(profile?.name ?? 'Thekedaar')),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          const _BackupBanner(),
          const SizedBox(height: AppSizes.gutter),
          Text('Quick actions', style: textTheme.titleMedium),
          const SizedBox(height: AppSizes.gap),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSizes.gap,
            crossAxisSpacing: AppSizes.gap,
            childAspectRatio: 1.6,
            children: [
              _QuickAction(
                icon: Icons.receipt_long,
                label: '+ New Bill',
                onTap: () => showComingSoon(context),
              ),
              _QuickAction(
                icon: Icons.payments,
                label: '+ Advance',
                onTap: () => showComingSoon(context),
              ),
              _QuickAction(
                icon: Icons.fact_check,
                label: "Today's Attendance",
                onTap: () => showComingSoon(context),
              ),
              _QuickAction(
                icon: Icons.person_add,
                label: 'Add Worker',
                onTap: () => context.push(Routes.addWorker),
              ),
            ],
          ),
          if (trades.isNotEmpty) ...[
            const SizedBox(height: AppSizes.gutter),
            Card(
              child: ListTile(
                leading: const Icon(Icons.handyman),
                title: const Text('Your work'),
                subtitle: Text(trades.map((t) => t.label).join(', ')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Backup is not built yet, so say so plainly (PRD D1: red banner until set up).
class _BackupBanner extends StatelessWidget {
  const _BackupBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.dangerSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        side: const BorderSide(color: AppColors.dangerFill),
      ),
      child: ListTile(
        leading: const Icon(Icons.cloud_off, color: AppColors.dangerText),
        title: const Text(
          'Backup not set up',
          style: TextStyle(
            color: AppColors.dangerText,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: const Text('Your data is only on this phone.'),
        trailing: TextButton(
          onPressed: () => showComingSoon(context),
          child: const Text('Set up'),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSizes.radius),
      side: const BorderSide(color: AppColors.border),
    );
    return Material(
      color: AppColors.surface,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: AppColors.slate900),
              const SizedBox(height: AppSizes.gap),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
