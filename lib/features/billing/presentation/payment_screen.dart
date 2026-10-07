import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_pad.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/billing_repository.dart';
import 'billing_widgets.dart';

/// PRD BL-13: payment received from a client, optionally against a bill.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key, this.clientId, this.documentId});

  final String? clientId;
  final String? documentId;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  late String? _clientId = widget.clientId;
  late String? _documentId = widget.documentId;
  String _amount = '';
  PaymentMode _mode = PaymentMode.cash;
  DateTime _date = dateOnly(DateTime.now());
  final _remarks = TextEditingController();
  bool _saving = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final paise = parseRupeesToPaise(_amount);
    if (_clientId == null) {
      showMessage(context, tr('Choose a client'));
      return;
    }
    if (paise == null || paise <= 0) {
      showMessage(context, tr('Enter the amount'));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(billingRepositoryProvider).recordPayment(
            clientId: _clientId!,
            documentId: _documentId,
            amountPaise: paise,
            mode: _mode,
            date: _date,
            remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context, tr('✓ {amount} received', {'amount': formatPaise(paise)}));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, tr('Could not save: {e}', {'e': errorText(e)}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bills = _clientId == null
        ? const <DocumentListItem>[]
        : (ref.watch(clientDocumentsProvider(_clientId!)).valueOrNull ?? const [])
            .where((b) =>
                b.document.status != DocumentStatus.cancelled &&
                b.document.status != DocumentStatus.draft &&
                (b.balancePaise > 0 || b.document.id == _documentId))
            .toList();
    final selectedBill =
        bills.where((b) => b.document.id == _documentId).firstOrNull;
    if (!_prefilled && selectedBill != null) {
      _prefilled = true;
      _amount = paiseToInputText(selectedBill.balancePaise);
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('Payment received'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          ClientPickerField(
            clientId: _clientId,
            onChanged: (id) => setState(() {
              _clientId = id;
              _documentId = null;
            }),
          ),
          const SizedBox(height: 12),
          PickerField(
            label: tr('Against bill (optional)'),
            icon: Icons.receipt_long,
            value: selectedBill == null
                ? null
                : tr('{number} · due {amount}', {'number': selectedBill.document.number, 'amount': formatPaise(selectedBill.balancePaise)}),
            onTap: () async {
              const none = '__none__';
              final picked = await showPickerSheet<String>(
                context,
                title: tr('Choose bill'),
                options: [none, for (final b in bills) b.document.id],
                label: (id) {
                  if (id == none) return tr('No specific bill');
                  final b = bills.firstWhere((b) => b.document.id == id);
                  return tr('{number} · due {amount}', {'number': b.document.number, 'amount': formatPaise(b.balancePaise)});
                },
                selected: _documentId ?? none,
              );
              if (picked == null) return;
              setState(() {
                _documentId = picked == none ? null : picked;
                final bill =
                    bills.where((b) => b.document.id == _documentId).firstOrNull;
                if (bill != null) _amount = paiseToInputText(bill.balancePaise);
              });
            },
          ),
          AmountDisplay(text: _amount),
          AmountPad(
            value: _amount,
            onChanged: (v) => setState(() => _amount = v),
          ),
          PaymentModeChips(
            value: _mode,
            onChanged: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remarks,
            decoration: InputDecoration(labelText: tr('Note (optional)')),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(dayFormat.format(_date)),
            trailing: Text(tr('Change')),
            onTap: () async {
              final picked =
                  await pickDate(context, initial: _date, last: DateTime.now());
              if (picked != null) setState(() => _date = dateOnly(picked));
            },
          ),
        ],
      ),
      bottomNavigationBar:
          BottomActionBar(label: tr('Save'), busy: _saving, onPressed: _save),
    );
  }
}
