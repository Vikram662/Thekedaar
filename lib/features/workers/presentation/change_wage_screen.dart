import 'package:flutter/material.dart';
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
import '../data/workers_repository.dart';

/// PRD WK-03: new wage from a date; history is kept.
class ChangeWageScreen extends ConsumerStatefulWidget {
  const ChangeWageScreen({super.key, required this.workerId});

  final String workerId;

  @override
  ConsumerState<ChangeWageScreen> createState() => _ChangeWageScreenState();
}

class _ChangeWageScreenState extends ConsumerState<ChangeWageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rate = TextEditingController();
  final _otRate = TextEditingController();
  WageModel _model = WageModel.daily;
  int _divisor = 30;
  DateTime _from = dateOnly(DateTime.now());
  bool _saving = false;
  bool _loaded = false;

  @override
  void dispose() {
    _rate.dispose();
    _otRate.dispose();
    super.dispose();
  }

  void _fill(WageHistory? current) {
    if (_loaded || current == null) return;
    _loaded = true;
    _model = current.model;
    _divisor = current.monthlyDivisor;
    if (current.ratePaise > 0) _rate.text = paiseToInputText(current.ratePaise);
    if (current.otRatePaise > 0) {
      _otRate.text = paiseToInputText(current.otRatePaise);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(workersRepositoryProvider).changeWage(
            workerId: widget.workerId,
            model: _model,
            ratePaise:
                _model == WageModel.piece ? 0 : parseRupeesToPaise(_rate.text)!,
            otRatePaise: parseRupeesToPaise(_otRate.text) ?? 0,
            monthlyDivisor: _divisor,
            effectiveFrom: _from,
          );
      if (!mounted) return;
      showMessage(context, tr('Wage updated'));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final history =
        ref.watch(wageHistoryProvider(widget.workerId)).valueOrNull ?? const [];
    final today = isoDate(DateTime.now());
    _fill(history.where((w) => w.effectiveFrom.compareTo(today) <= 0).firstOrNull);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Change wage'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.gutter),
          children: [
            SegmentedButton<WageModel>(
              segments: [
                ButtonSegment(value: WageModel.daily, label: Text(tr('Daily'))),
                ButtonSegment(value: WageModel.monthly, label: Text(tr('Monthly'))),
                ButtonSegment(value: WageModel.piece, label: Text(tr('Piece-rate'))),
              ],
              selected: {_model},
              onSelectionChanged: (s) => setState(() => _model = s.first),
            ),
            const SizedBox(height: 12),
            if (_model != WageModel.piece)
              TextFormField(
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 20),
                decoration: InputDecoration(
                  labelText: _model == WageModel.daily
                      ? tr('Rate per day')
                      : tr('Salary per month'),
                  prefixText: '₹ ',
                ),
                validator: (v) {
                  final p = parseRupeesToPaise(v ?? '');
                  return p == null || p <= 0 ? tr('Enter amount') : null;
                },
              ),
            if (_model == WageModel.monthly) ...[
              SectionTitle(tr('Per-day rate for monthly salary')),
              Wrap(
                spacing: AppSizes.gap,
                children: [
                  for (final (value, label) in [
                    (30, '÷ 30'),
                    (26, '÷ 26'),
                    (0, tr('÷ days in month')),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _divisor == value,
                      onSelected: (_) => setState(() => _divisor = value),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _otRate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr('OT rate per hour (optional)'),
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(tr('New wage from')),
              subtitle: Text(dayFormat.format(_from)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await pickDate(context, initial: _from);
                if (picked != null) setState(() => _from = dateOnly(picked));
              },
            ),
            SectionTitle(tr('History')),
            for (final w in history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(wageLabel(w)),
                subtitle: Text(tr('From {date}', {'date': dayFormat.format(parseIsoDate(w.effectiveFrom))})),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        label: tr('Save new wage'),
        busy: _saving,
        onPressed: _save,
      ),
    );
  }
}
