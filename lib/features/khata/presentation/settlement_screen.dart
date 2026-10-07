import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../../workers/data/workers_repository.dart';
import '../data/khata_repository.dart';
import 'khata_widgets.dart';

/// PRD KH-06: Earning − Advance − EMI = Net. Enter what is paid; the rest
/// carries forward and the period is locked.
class SettlementScreen extends ConsumerStatefulWidget {
  const SettlementScreen({super.key, required this.workerId});

  final String workerId;

  @override
  ConsumerState<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends ConsumerState<SettlementScreen> {
  DateTime? _periodTo;
  WorkerSummary? _summary;
  final _paid = TextEditingController();
  PaymentMode _mode = PaymentMode.cash;
  bool _saving = false;
  Settlement? _done;

  @override
  void initState() {
    super.initState();
    _paid.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  /// Default: end of last month if the open period reaches it, else today.
  Future<void> _load({DateTime? to}) async {
    final repo = ref.read(khataRepositoryProvider);
    var periodTo = to;
    if (periodTo == null) {
      final start = await repo.openPeriodStart(widget.workerId);
      final now = DateTime.now();
      final lastMonthEnd = DateTime(now.year, now.month, 0);
      periodTo = lastMonthEnd.isBefore(start) ? dateOnly(now) : lastMonthEnd;
    }
    final summary =
        await repo.computeSummary(widget.workerId, periodTo: periodTo);
    if (!mounted) return;
    setState(() {
      _periodTo = periodTo;
      _summary = summary;
      final net = summary.balancePaise;
      _paid.text = net > 0 ? paiseToInputText(net) : '0';
    });
  }

  Future<void> _settle(WorkerSummary summary) async {
    final paid = parseRupeesToPaise(_paid.text);
    if (paid == null || paid < 0) {
      showMessage(context, tr('Enter the paid amount (0 if nothing paid)'));
      return;
    }
    final carry = summary.balancePaise - paid;
    final ok = await confirmDialog(
      context,
      title: tr('Settle and lock?'),
      message:
          tr('{date} – {date2}\nPaid: {amount}\nCarry forward: {amount2}\n\nAttendance and entries in this period will be locked.', {'date': dayFormat.format(summary.periodFrom), 'date2': dayFormat.format(summary.periodTo), 'amount': formatPaise(paid), 'amount2': formatPaise(carry)}),
      confirmLabel: tr('Settle'),
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      final settlement = await ref.read(khataRepositoryProvider).settle(
            workerId: widget.workerId,
            periodTo: summary.periodTo,
            paidPaise: paid,
            mode: _mode,
          );
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _done = settlement);
    } catch (e) {
      if (mounted) showMessage(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final worker = ref.watch(workerProvider(widget.workerId)).valueOrNull;
    final summary = _summary;
    final done = _done;

    if (done != null && worker != null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Settled'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    size: 72, color: AppColors.successText),
                const SizedBox(height: 16),
                Text(tr('{name} settled', {'name': worker.worker.name}),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(tr('Paid {amount} · Carry forward {amount2}', {'amount': formatPaise(done.paidPaise), 'amount2': formatPaise(done.carryForwardPaise)})),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => sharePayslip(
                    context,
                    ref,
                    worker: worker.worker,
                    settlement: done,
                    roleName: worker.roleName,
                  ),
                  icon: const Icon(Icons.share),
                  label: Text(tr('Share pay slip')),
                ),
                TextButton(
                  onPressed: () => context.pop(),
                  child: Text(tr('Done')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (summary != null && summary.periodFrom.isAfter(summary.periodTo)) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Settle'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              summary.lastSettlement == null
                  ? tr('Already settled up to today. Nothing new to settle yet.')
                  : tr('Already settled up to {date}. Nothing new to settle yet.', {
                      'date': dayFormat.format(
                          parseIsoDate(summary.lastSettlement!.periodTo)),
                    }),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('Settle {name}', {'name': worker?.worker.name ?? ''}))),
      body: summary == null
          ? const ListSkeleton()
          : ListView(
              padding: const EdgeInsets.all(AppSizes.gutter),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.date_range),
                  title: Text('${dayFormat.format(summary.periodFrom)} – '
                      '${dayFormat.format(summary.periodTo)}'),
                  subtitle: Text(tr('Settle up to this date')),
                  trailing: Text(tr('Change')),
                  onTap: () async {
                    final picked = await pickDate(
                      context,
                      initial: _periodTo ?? DateTime.now(),
                      first: summary.periodFrom,
                      last: DateTime.now(),
                    );
                    if (picked != null) await _load(to: dateOnly(picked));
                  },
                ),
                _Breakdown(summary: summary),
                SectionTitle(tr('Payment')),
                TextField(
                  controller: _paid,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 24),
                  decoration: InputDecoration(
                    labelText: tr('Paid now'),
                    prefixText: '₹ ',
                  ),
                ),
                const SizedBox(height: 12),
                PaymentModeChips(
                  value: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
                const SizedBox(height: 12),
                Builder(builder: (context) {
                  final paid = parseRupeesToPaise(_paid.text) ?? 0;
                  final carry = summary.balancePaise - paid;
                  return Panel(
                    child: AmountRow(
                      label: carry >= 0
                          ? tr('Carry forward (to worker)')
                          : tr('Carry forward (worker owes)'),
                      paise: carry.abs(),
                      bold: true,
                      color: carry >= 0
                          ? AppColors.successText
                          : AppColors.dangerText,
                    ),
                  );
                }),
              ],
            ),
      bottomNavigationBar: summary == null
          ? null
          : BottomActionBar(
              label: tr('Settle & lock'),
              busy: _saving,
              onPressed: () => _settle(summary),
            ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.summary});

  final WorkerSummary summary;

  @override
  Widget build(BuildContext context) {
    final r = summary.result;
    final c = summary.counts;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Present {present} · Half {half} · Absent {absent}', {
                  'present': c.present,
                  'half': c.half,
                  'absent': c.absent,
                }) +
                (c.off > 0 ? tr(' · Off {count}', {'count': c.off}) : '') +
                (c.leave > 0 ? tr(' · Leave {count}', {'count': c.leave}) : ''),
            style: const TextStyle(color: AppColors.slate600),
          ),
          const Divider(),
          AmountRow(label: tr('Wages'), paise: r.basePaise),
          if (r.otPaise > 0) AmountRow(label: 'OT', paise: r.otPaise),
          if (r.piecePaise > 0)
            AmountRow(label: tr('Piece work'), paise: r.piecePaise),
          if (r.bonusPaise > 0) AmountRow(label: tr('Bonus'), paise: r.bonusPaise),
          if (r.deductionPaise > 0)
            AmountRow(
                label: tr('Deduction'), paise: r.deductionPaise, prefix: '− '),
          AmountRow(label: tr('Earning'), paise: r.earningPaise, bold: true),
          const Divider(),
          AmountRow(
            label: tr('Advance taken'),
            paise: r.advancePaise,
            prefix: '− ',
            color: AppColors.warningText,
          ),
          if (r.previousBalancePaise != 0)
            AmountRow(
              label: r.previousBalancePaise > 0
                  ? tr('Previous balance (to worker)')
                  : tr('Previous balance (worker owes)'),
              paise: r.previousBalancePaise.abs(),
              prefix: r.previousBalancePaise > 0 ? '+ ' : '− ',
            ),
          const Divider(),
          AmountRow(
            label: summary.balancePaise >= 0 ? tr('Net payable') : tr('Worker owes'),
            paise: summary.balancePaise.abs(),
            bold: true,
            color: summary.balancePaise >= 0
                ? AppColors.successText
                : AppColors.dangerText,
          ),
        ],
      ),
    );
  }
}
