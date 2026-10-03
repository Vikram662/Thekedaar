import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/audit.dart';
import '../../../core/db/enums.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_pad.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../../workers/presentation/worker_picker.dart';
import '../data/khata_repository.dart';
import 'khata_widgets.dart';

/// PRD KH-01 / E2 Advance Entry: worker → big numpad → mode → Save.
/// Also used for bonus and deduction entries.
class LedgerEntryScreen extends ConsumerStatefulWidget {
  const LedgerEntryScreen({
    super.key,
    this.workerId,
    this.type = LedgerType.advance,
  });

  final String? workerId;
  final LedgerType type;

  @override
  ConsumerState<LedgerEntryScreen> createState() => _LedgerEntryScreenState();
}

class _LedgerEntryScreenState extends ConsumerState<LedgerEntryScreen> {
  late String? _workerId = widget.workerId;
  late LedgerType _type = widget.type;
  String _amount = '';
  PaymentMode _mode = PaymentMode.cash;
  DateTime _at = DateTime.now();
  final _note = TextEditingController();
  bool _saving = false;

  static const _types = [
    LedgerType.advance,
    LedgerType.bonus,
    LedgerType.deduction,
  ];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await pickDate(context, initial: _at, last: DateTime.now());
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    setState(() => _at = DateTime(
          date.year,
          date.month,
          date.day,
          time?.hour ?? _at.hour,
          time?.minute ?? _at.minute,
        ));
  }

  Future<void> _save() async {
    final paise = parseRupeesToPaise(_amount);
    if (_workerId == null) {
      showMessage(context, 'Choose a worker');
      return;
    }
    if (paise == null || paise <= 0) {
      showMessage(context, 'Enter the amount');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(khataRepositoryProvider).addEntry(
            workerId: _workerId!,
            type: _type,
            amountPaise: paise,
            at: _at,
            mode: _type == LedgerType.advance ? _mode : null,
            remarks: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context, '✓ ${ledgerTypeLabel(_type)} ${formatPaise(paise)} saved');
      context.pop();
    } on PeriodLockedException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(_at, DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text('New ${ledgerTypeLabel(_type).toLowerCase()}')),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          WorkerPickerField(
            workerId: _workerId,
            onChanged: (w) => setState(() => _workerId = w.worker.id),
          ),
          const SizedBox(height: 12),
          SegmentedButton<LedgerType>(
            segments: [
              for (final t in _types)
                ButtonSegment(value: t, label: Text(ledgerTypeLabel(t))),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          AmountDisplay(text: _amount),
          AmountPad(
            value: _amount,
            onChanged: (v) => setState(() => _amount = v),
          ),
          if (_type == LedgerType.advance) ...[
            const SizedBox(height: 4),
            PaymentModeChips(
              value: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(isToday
                ? 'Today, ${TimeOfDay.fromDateTime(_at).format(context)}'
                : dayTimeFormat.format(_at)),
            trailing: const Text('Change'),
            onTap: _pickDateTime,
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        label: 'Save',
        busy: _saving,
        onPressed: _save,
      ),
    );
  }
}
