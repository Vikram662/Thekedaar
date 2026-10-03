import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../attendance/presentation/attendance_widgets.dart';
import '../../khata/data/khata_repository.dart';
import '../../khata/presentation/khata_widgets.dart';
import '../../lock/lock_screens.dart';
import '../data/workers_repository.dart';

/// PRD E2 Worker Detail: summary card, actions, calendar, entries.
class WorkerDetailScreen extends ConsumerWidget {
  const WorkerDetailScreen({super.key, required this.workerId});

  final String workerId;

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    WorkerListItem item,
  ) async {
    final active = item.worker.isActive;
    final ok = await confirmDialog(
      context,
      title: active ? 'Mark as left?' : 'Make active again?',
      message: active
          ? '${item.worker.name} will move to inactive workers. '
              'All records and the pending balance stay.'
          : '${item.worker.name} will show in attendance again.',
      confirmLabel: active ? 'Mark as left' : 'Make active',
    );
    if (!ok) return;
    await ref.read(workersRepositoryProvider).setActive(workerId, !active);
  }

  Future<void> _reverseSettlement(
    BuildContext context,
    WidgetRef ref,
    String settlementId,
  ) async {
    final ok = await confirmDialog(
      context,
      title: 'Reverse settlement?',
      message: 'The period will be unlocked so it can be corrected. '
          'Money already paid stays recorded as a payment.',
      confirmLabel: 'Reverse',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    if (!await confirmIdentity(context, reason: 'Confirm to reverse')) return;
    try {
      await ref.read(khataRepositoryProvider).reverseSettlement(settlementId);
      if (context.mounted) showMessage(context, 'Settlement reversed');
    } catch (e) {
      if (context.mounted) showMessage(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(workerProvider(workerId));
    final item = itemAsync.valueOrNull;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: itemAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const NotFoundBody(),
      );
    }
    final worker = item.worker;
    final summary = ref.watch(workerSummaryProvider(workerId));
    final ledger = ref.watch(workerLedgerProvider(workerId)).valueOrNull ?? const [];
    final pieces = ref.watch(workerPieceWorkProvider(workerId)).valueOrNull ?? const [];
    final settlements =
        ref.watch(workerSettlementsProvider(workerId)).valueOrNull ?? const [];
    final latestLocked = settlements
        .where((s) => s.status == SettlementStatus.locked)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(worker.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit),
            onPressed: () => context.push(Routes.editWorker(workerId)),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'wage':
                  context.push(Routes.changeWage(workerId));
                case 'active':
                  _toggleActive(context, ref, item);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'wage', child: Text('Change wage')),
              PopupMenuItem(
                value: 'active',
                child: Text(worker.isActive ? 'Mark as left' : 'Make active'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.amber100,
                foregroundColor: AppColors.slate900,
                child: Text(initials(worker.name),
                    style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        if (item.roleName != null) item.roleName!,
                        wageLabel(item.wage),
                      ].join(' · '),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (worker.phone != null)
                      Text(formatIndianPhone(worker.phone!)),
                    if (!worker.isActive)
                      const Text('Inactive (left)',
                          style: TextStyle(color: AppColors.dangerText)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.gutter),
          summary.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Could not calculate: $e'),
            data: (s) => WorkerSummaryCard(summary: s),
          ),
          const SizedBox(height: AppSizes.gap),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.push(Routes.ledgerEntry(
                      workerId: workerId, type: LedgerType.advance)),
                  icon: const Icon(Icons.add),
                  label: const Text('Advance'),
                ),
              ),
              const SizedBox(width: AppSizes.gap),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, AppSizes.tapPrimary),
                  ),
                  onPressed: () => context.push(Routes.settle(workerId)),
                  icon: const Icon(Icons.task_alt),
                  label: const Text('Settle'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.gap),
          Wrap(
            spacing: AppSizes.gap,
            children: [
              ActionChip(
                avatar: const Icon(Icons.square_foot, size: 18),
                label: const Text('Piece work'),
                onPressed: () => context.push(Routes.pieceWork(workerId)),
              ),
              ActionChip(
                avatar: const Icon(Icons.card_giftcard, size: 18),
                label: const Text('Bonus'),
                onPressed: () => context.push(Routes.ledgerEntry(
                    workerId: workerId, type: LedgerType.bonus)),
              ),
              ActionChip(
                avatar: const Icon(Icons.remove_circle_outline, size: 18),
                label: const Text('Deduction'),
                onPressed: () => context.push(Routes.ledgerEntry(
                    workerId: workerId, type: LedgerType.deduction)),
              ),
            ],
          ),
          const SectionTitle('Attendance'),
          AttendanceCalendar(worker: worker),
          const SectionTitle('Khata entries'),
          if (ledger.isEmpty)
            const Text('No entries yet.',
                style: TextStyle(color: AppColors.slate600))
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final entry in ledger.take(20)) LedgerTile(item: entry),
                ],
              ),
            ),
          if (pieces.isNotEmpty) ...[
            const SectionTitle('Piece work'),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final p in pieces.take(20))
                    ListTile(
                      title: Text(p.work.description),
                      subtitle: Text(
                        '${dayFormat.format(parseIsoDate(p.work.date))} · '
                        '${formatMilli(p.work.qtyMilli)} ${p.unitCode ?? ''} × '
                        '${formatPaise(p.work.ratePaise)}'
                        '${p.work.settlementId != null ? ' · Settled' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(formatPaise(p.work.amountPaise),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (p.work.settlementId == null)
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final ok = await confirmDialog(
                                  context,
                                  title: 'Delete this piece work?',
                                  message: p.work.description,
                                  confirmLabel: 'Delete',
                                  destructive: true,
                                );
                                if (ok) {
                                  await ref
                                      .read(khataRepositoryProvider)
                                      .deletePieceWork(p.work.id);
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (settlements.isNotEmpty) ...[
            const SectionTitle('Settlements'),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final s in settlements)
                    ListTile(
                      title: Text(
                        '${dayFormat.format(parseIsoDate(s.periodFrom))} – '
                        '${dayFormat.format(parseIsoDate(s.periodTo))}',
                        style: s.status == SettlementStatus.reversed
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough)
                            : null,
                      ),
                      subtitle: Text(
                        'Paid ${formatPaise(s.paidPaise)} · '
                        'Carry forward ${formatPaise(s.carryForwardPaise)}'
                        '${s.status == SettlementStatus.reversed ? ' · Reversed' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (s.status == SettlementStatus.locked)
                            IconButton(
                              tooltip: 'Share pay slip',
                              icon: const Icon(Icons.share),
                              onPressed: () => sharePayslip(
                                context,
                                ref,
                                worker: worker,
                                settlement: s,
                                roleName: item.roleName,
                              ),
                            ),
                          if (s.id == latestLocked?.id)
                            IconButton(
                              tooltip: 'Reverse settlement',
                              icon: const Icon(Icons.undo),
                              onPressed: () =>
                                  _reverseSettlement(context, ref, s.id),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
