import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/pdf/pdf_common.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../../lock/app_lock_controller.dart';
import '../data/khata_repository.dart';
import '../domain/payslip_pdf.dart';

String ledgerTypeLabel(LedgerType type) => switch (type) {
      LedgerType.advance => 'Advance',
      LedgerType.payment => 'Payment',
      LedgerType.bonus => 'Bonus',
      LedgerType.deduction => 'Deduction',
      LedgerType.emi => 'EMI',
      LedgerType.reversal => 'Reversal',
      LedgerType.carryForward => 'Carry forward',
    };

/// PRD KH-03 worker summary card: days, earned, advance, balance.
class WorkerSummaryCard extends StatelessWidget {
  const WorkerSummaryCard({super.key, required this.summary});

  final WorkerSummary summary;

  @override
  Widget build(BuildContext context) {
    final r = summary.result;
    final balance = summary.balancePaise;
    final counts = summary.counts;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Since ${dayFormat.format(summary.periodFrom)}',
            style: const TextStyle(color: AppColors.slate600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('Paid days', style: Theme.of(context).textTheme.bodyLarge),
              ),
              Text(
                _days(r.paidDays),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Text(
            'P ${counts.present} · ½ ${counts.half} · A ${counts.absent}'
            '${counts.off > 0 ? ' · Off ${counts.off}' : ''}',
            style: const TextStyle(color: AppColors.slate600),
          ),
          const Divider(),
          AmountRow(label: 'Earned', paise: r.earningPaise),
          if (r.piecePaise > 0)
            AmountRow(label: '  incl. piece work', paise: r.piecePaise),
          if (r.otPaise > 0) AmountRow(label: '  incl. OT', paise: r.otPaise),
          AmountRow(
            label: 'Advance taken',
            paise: r.advancePaise,
            color: AppColors.warningText,
          ),
          if (r.previousBalancePaise != 0)
            AmountRow(
              label: 'Previous balance',
              paise: r.previousBalancePaise,
            ),
          const Divider(),
          AmountRow(
            label: balance >= 0 ? 'Balance to pay' : 'Worker owes',
            paise: balance.abs(),
            bold: true,
            color: balance >= 0 ? AppColors.successText : AppColors.dangerText,
          ),
        ],
      ),
    );
  }

  static String _days(double days) =>
      days == days.roundToDouble() ? '${days.toInt()}' : days.toStringAsFixed(1);
}

/// One khata entry. Long press offers Reverse (PRD KH-02).
class LedgerTile extends ConsumerWidget {
  const LedgerTile({super.key, required this.item, this.showWorker = false});

  final LedgerItem item;
  final bool showWorker;

  Future<void> _reverse(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Reverse this entry?',
      message:
          '${ledgerTypeLabel(item.entry.entryType)} of ${formatPaise(item.entry.amountPaise)} '
          'will be cancelled with a reversal entry. The original stays in the record.',
      confirmLabel: 'Reverse',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(khataRepositoryProvider).reverseEntry(item.entry.id);
      if (context.mounted) showMessage(context, 'Entry reversed');
    } catch (e) {
      if (context.mounted) showMessage(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = item.entry;
    final type = entry.entryType;
    final isMoneyOut = type == LedgerType.advance || type == LedgerType.payment;
    final canReverse = !item.reversed &&
        type != LedgerType.reversal &&
        !(type == LedgerType.payment && entry.refId != null);
    final title = showWorker
        ? '${item.workerName} · ${ledgerTypeLabel(type)}'
        : ledgerTypeLabel(type);
    final subtitle = [
      dayTimeFormat.format(item.at),
      if (entry.mode != null) paymentModeLabel(entry.mode!),
      if (entry.remarks != null && entry.remarks!.isNotEmpty) entry.remarks!,
    ].join(' · ');

    return ListTile(
      title: Text(
        title,
        style: item.reversed
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(item.reversed ? 'Reversed · $subtitle' : subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${isMoneyOut ? '−' : type == LedgerType.bonus ? '+' : ''}'
            '${formatPaise(entry.amountPaise)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: item.reversed
                  ? AppColors.slate600
                  : isMoneyOut
                      ? AppColors.warningText
                      : AppColors.slate900,
            ),
          ),
          if (canReverse)
            IconButton(
              tooltip: 'Reverse',
              icon: const Icon(Icons.undo),
              onPressed: () => _reverse(context, ref),
            ),
        ],
      ),
    );
  }
}

/// Builds and shares the pay-slip PDF for a settlement (PRD KH-09).
Future<void> sharePayslip(
  BuildContext context,
  WidgetRef ref, {
  required Worker worker,
  required Settlement settlement,
  String? roleName,
}) async {
  final profile = await ref.read(businessProfileProvider.future);
  if (profile == null) return;
  final bytes = await buildPayslipPdf(
    profile: profile,
    worker: worker,
    settlement: settlement,
    roleName: roleName,
  );
  final lock = ref.read(appLockProvider);
  lock.suspendRelock = true;
  try {
    await sharePdf(
      bytes,
      fileName: 'Payslip-${worker.name}-${settlement.periodTo}.pdf',
      text: 'Pay slip for ${worker.name}',
    );
  } finally {
    lock.suspendRelock = false;
  }
}
