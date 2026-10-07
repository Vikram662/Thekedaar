import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/db/audit.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/upi.dart';
import '../../../core/widgets/amount_pad.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../../lock/app_lock_controller.dart';
import '../../workers/data/workers_repository.dart';
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
      showMessage(context, tr('Choose a worker'));
      return;
    }
    if (paise == null || paise <= 0) {
      showMessage(context, tr('Enter the amount'));
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
      showMessage(context, tr('✓ {type} {amount} saved', {'type': ledgerTypeLabel(_type), 'amount': formatPaise(paise)}));
      context.pop();
    } on PeriodLockedException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, tr(e.message));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, tr('Could not save: {e}', {'e': errorText(e)}));
    }
  }

  /// PRD KH-08: open the worker's UPI in any UPI app with the amount filled
  /// in, then ask whether the money went before saving the entry.
  Future<void> _payWithUpi(String upiId, String workerName) async {
    final paise = parseRupeesToPaise(_amount);
    if (paise == null || paise <= 0) {
      showMessage(context, tr('Enter the amount'));
      return;
    }
    final uri = Uri.parse(upiPayUri(
      upiId: upiId,
      payeeName: workerName,
      amountPaise: paise,
      note: '${ledgerTypeLabel(_type)} $workerName',
    ));
    // Paying in the UPI app can take a while; don't lock the app meanwhile.
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!opened) {
        showMessage(context, tr('No UPI app found on this phone'));
        return;
      }
      final paid = await confirmDialog(
        context,
        title: tr('Payment done?'),
        message: tr('Did {amount} reach {workerName} in the UPI app? Tap Yes only after the app shows success.', {'amount': formatPaise(paise), 'workerName': workerName}),
        confirmLabel: tr('Yes, paid'),
      );
      if (paid && mounted) await _save();
    } finally {
      lock.suspendRelock = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final worker = _workerId == null
        ? null
        : ref.watch(workerProvider(_workerId!)).valueOrNull?.worker;
    final workerUpi = worker?.upiId?.trim();
    final canPayUpi = _type == LedgerType.advance &&
        _mode != PaymentMode.cash &&
        _mode != PaymentMode.bank &&
        workerUpi != null &&
        isValidUpiId(workerUpi);
    final isToday = DateUtils.isSameDay(_at, DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text(tr('New {type}', {'type': ledgerTypeLabel(_type).toLowerCase()}))),
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
            if (canPayUpi) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () => _payWithUpi(workerUpi!, worker!.name),
                icon: const Icon(Icons.qr_code_2),
                label: Text(tr('Pay with UPI app ({workerUpi})', {'workerUpi': workerUpi})),
              ),
            ],
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(labelText: tr('Note (optional)')),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(isToday
                ? tr('Today, {time}', {'time': TimeOfDay.fromDateTime(_at).format(context)})
                : dayTimeFormat.format(_at)),
            trailing: Text(tr('Change')),
            onTap: _pickDateTime,
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        label: tr('Save'),
        busy: _saving,
        onPressed: _save,
      ),
    );
  }
}
