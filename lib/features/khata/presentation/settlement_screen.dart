import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
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
      showMessage(context, 'Enter the paid amount (0 if nothing paid)');
      return;
    }
    final carry = summary.balancePaise - paid;
    final ok = await confirmDialog(
      context,
      title: 'Settle and lock?',
      message:
          '${dayFormat.format(summary.periodFrom)} – ${dayFormat.format(summary.periodTo)}\n'
          'Paid: ${formatPaise(paid)}\n'
          'Carry forward: ${formatPaise(carry)}\n\n'
          'Attendance and entries in this period will be locked.',
      confirmLabel: 'Settle',
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
        appBar: AppBar(title: const Text('Settled')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    size: 72, color: AppColors.successText),
                const SizedBox(height: 16),
                Text('${worker.worker.name} settled',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Paid ${formatPaise(done.paidPaise)} · '
                    'Carry forward ${formatPaise(done.carryForwardPaise)}'),
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
                  label: const Text('Share pay slip'),
                ),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (summary != null && summary.periodFrom.isAfter(summary.periodTo)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settle')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Already settled up to '
              '${summary.lastSettlement == null ? 'today' : dayFormat.format(parseIsoDate(summary.lastSettlement!.periodTo))}. '
              'Nothing new to settle yet.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Settle ${worker?.worker.name ?? ''}')),
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
                  subtitle: const Text('Settle up to this date'),
                  trailing: const Text('Change'),
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
                const SectionTitle('Payment'),
                TextField(
                  controller: _paid,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 24),
                  decoration: const InputDecoration(
                    labelText: 'Paid now',
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
                          ? 'Carry forward (to worker)'
                          : 'Carry forward (worker owes)',
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
              label: 'Settle & lock',
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
            'Present ${c.present} · Half ${c.half} · Absent ${c.absent}'
            '${c.off > 0 ? ' · Off ${c.off}' : ''}'
            '${c.leave > 0 ? ' · Leave ${c.leave}' : ''}',
            style: const TextStyle(color: AppColors.slate600),
          ),
          const Divider(),
          AmountRow(label: 'Wages', paise: r.basePaise),
          if (r.otPaise > 0) AmountRow(label: 'OT', paise: r.otPaise),
          if (r.piecePaise > 0)
            AmountRow(label: 'Piece work', paise: r.piecePaise),
          if (r.bonusPaise > 0) AmountRow(label: 'Bonus', paise: r.bonusPaise),
          if (r.deductionPaise > 0)
            AmountRow(
                label: 'Deduction', paise: r.deductionPaise, prefix: '− '),
          AmountRow(label: 'Earning', paise: r.earningPaise, bold: true),
          const Divider(),
          AmountRow(
            label: 'Advance taken',
            paise: r.advancePaise,
            prefix: '− ',
            color: AppColors.warningText,
          ),
          if (r.previousBalancePaise != 0)
            AmountRow(
              label: r.previousBalancePaise > 0
                  ? 'Previous balance (to worker)'
                  : 'Previous balance (worker owes)',
              paise: r.previousBalancePaise.abs(),
              prefix: r.previousBalancePaise > 0 ? '+ ' : '− ',
            ),
          const Divider(),
          AmountRow(
            label: summary.balancePaise >= 0 ? 'Net payable' : 'Worker owes',
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
