import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../workers/data/workers_repository.dart';
import '../data/khata_repository.dart';
import 'khata_widgets.dart';

/// Khata tab (PRD E1): balances per worker, and recent entries.
class KhataScreen extends StatefulWidget {
  const KhataScreen({super.key, this.tab});

  /// Sub-tab requested by the drawer (0 balances, 1 entries).
  final int? tab;

  @override
  State<KhataScreen> createState() => _KhataScreenState();
}

class _KhataScreenState extends State<KhataScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: (widget.tab ?? 0).clamp(0, 1),
  );

  @override
  void didUpdateWidget(KhataScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tab = widget.tab;
    if (tab != null && tab != oldWidget.tab) _tabs.animateTo(tab.clamp(0, 1));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(tr('Khata')),
        bottom: TabBar(
          controller: _tabs,
          tabs: [Tab(text: tr('Balances')), Tab(text: tr('Entries'))],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.ledgerEntry()),
        icon: const Icon(Icons.add),
        label: Text(tr('Advance')),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_BalancesTab(), _EntriesTab()],
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
      return EmptyState(
        icon: Icons.account_balance_wallet,
        title: tr('No workers yet'),
        message: tr('Add workers to keep their khata.'),
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
            : tr('Earned {earned} · Advance {advance}', {
                  'earned': formatPaise(summary.result.earningPaise),
                  'advance': formatPaise(summary.result.advancePaise),
                }) +
                (item.worker.isActive ? '' : tr(' · Left')),
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
                  balance >= 0 ? tr('to pay') : tr('owes you'),
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
      loading: () => const ListSkeleton(),
      error: (e, _) => Center(child: Text(errorText(e))),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.receipt,
              title: tr('No entries yet'),
              message: tr('Advances, bonuses and payments show here.'),
              actionLabel: tr('Add advance'),
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
