import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/empty_state.dart';
import '../../workers/data/workers_repository.dart';
import '../data/khata_repository.dart';
import 'khata_widgets.dart';

/// Khata tab (PRD E1): balances per worker, and recent entries.
class KhataScreen extends ConsumerWidget {
  const KhataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Khata'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFFCBD5E1),
            indicatorColor: AppColors.amber500,
            tabs: [Tab(text: 'Balances'), Tab(text: 'Entries')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push(Routes.ledgerEntry()),
          icon: const Icon(Icons.add),
          label: const Text('Advance'),
        ),
        body: const TabBarView(children: [_BalancesTab(), _EntriesTab()]),
      ),
    );
  }
}

class _BalancesTab extends ConsumerWidget {
  const _BalancesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeWorkersProvider).valueOrNull ?? const [];
    final inactive = ref.watch(inactiveWorkersProvider).valueOrNull ?? const [];
    final workers = [...active, ...inactive];
    if (workers.isEmpty) {
      return const EmptyState(
        icon: Icons.account_balance_wallet,
        title: 'No workers yet',
        message: 'Add workers to keep their khata.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: workers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _BalanceTile(item: workers[index]),
    );
  }
}

class _BalanceTile extends ConsumerWidget {
  const _BalanceTile({required this.item});

  final WorkerListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(workerSummaryProvider(item.worker.id)).valueOrNull;
    final balance = summary?.balancePaise;
    return ListTile(
      minVerticalPadding: 12,
      title: Text(item.worker.name),
      subtitle: Text(
        summary == null
            ? '…'
            : 'Earned ${formatPaise(summary.result.earningPaise)} · '
                'Advance ${formatPaise(summary.result.advancePaise)}'
                '${item.worker.isActive ? '' : ' · Left'}',
      ),
      trailing: balance == null
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatPaise(balance.abs()),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: balance >= 0
                        ? AppColors.successText
                        : AppColors.dangerText,
                  ),
                ),
                Text(
                  balance >= 0 ? 'to pay' : 'owes you',
                  style: const TextStyle(fontSize: 12, color: AppColors.slate600),
                ),
              ],
            ),
      onTap: () => context.push(Routes.worker(item.worker.id)),
    );
  }
}

class _EntriesTab extends ConsumerWidget {
  const _EntriesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(recentLedgerProvider);
    return entries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.receipt,
              title: 'No entries yet',
              message: 'Advances, bonuses and payments show here.',
              actionLabel: 'Add advance',
              onAction: () => context.push(
                  Routes.ledgerEntry(type: LedgerType.advance)),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  LedgerTile(item: list[index], showWorker: true),
            ),
    );
  }
}
