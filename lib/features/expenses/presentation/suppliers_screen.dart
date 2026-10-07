import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/amount_pad.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pickers.dart';
import '../data/expenses_repository.dart';

/// PRD EX-02: suppliers with their due balance.
class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Suppliers'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.addSupplier),
        icon: const Icon(Icons.add_business),
        label: Text(tr('Supplier')),
      ),
      body: suppliers.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => Center(child: Text(errorText(e))),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.store,
              title: tr('No suppliers yet'),
              message: tr('Add the shops you buy material from on credit.'),
              actionLabel: tr('Add supplier'),
              onAction: () => context.push(Routes.addSupplier),
            );
          }
          final totalDue = list.fold(
            0,
            (sum, s) => s.duePaise > 0 ? sum + s.duePaise : sum,
          );
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSizes.gutter),
                child: Panel(
                  child: AmountRow(
                    label: tr('Total to pay suppliers'),
                    paise: totalDue,
                    bold: true,
                    color: AppColors.successText,
                  ),
                ),
              ),
              for (final s in list) ...[
                ListTile(
                  minVerticalPadding: 12,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.amber100,
                    foregroundColor: AppColors.slate900,
                    child: Icon(Icons.store),
                  ),
                  title: Text(s.supplier.name),
                  subtitle: s.supplier.phone == null
                      ? null
                      : Text(formatIndianPhone(s.supplier.phone!)),
                  trailing: Text(
                    s.duePaise == 0
                        ? tr('Settled')
                        : s.duePaise > 0
                            ? formatPaise(s.duePaise)
                            : tr('Advance {amount}', {'amount': formatPaise(-s.duePaise)}),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: s.duePaise > 0
                          ? AppColors.successText
                          : AppColors.slate600,
                    ),
                  ),
                  onTap: () => context.push(Routes.supplier(s.supplier.id)),
                ),
                const Divider(height: 1),
              ],
            ],
          );
        },
      ),
    );
  }
}

class SupplierFormScreen extends ConsumerStatefulWidget {
  const SupplierFormScreen({super.key, this.supplierId});

  final String? supplierId;

  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final address = _address.text.trim();
    await ref.read(expensesRepositoryProvider).saveSupplier(
          id: widget.supplierId,
          name: _name.text.trim(),
          phone: normalizeIndianPhone(_phone.text),
          address: address.isEmpty ? null : address,
        );
    if (!mounted) return;
    showMessage(context, tr('Supplier saved'));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.supplierId != null && !_loaded) {
      final s = ref.watch(supplierProvider(widget.supplierId!)).valueOrNull;
      if (s == null) {
        return const SkeletonPage();
      }
      _loaded = true;
      _name.text = s.supplier.name;
      _phone.text =
          s.supplier.phone == null ? '' : formatIndianPhone(s.supplier.phone!);
      _address.text = s.supplier.address ?? '';
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplierId == null ? tr('New supplier') : tr('Edit supplier')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.gutter),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Shop / supplier name')),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? tr('Enter name') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: tr('Mobile number (optional)'),
                prefixText: '+91 ',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty || normalizeIndianPhone(v) != null)
                      ? null
                      : tr('Enter a valid 10-digit mobile number'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              maxLines: 2,
              decoration: InputDecoration(labelText: tr('Address (optional)')),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          BottomActionBar(label: tr('Save'), busy: _saving, onPressed: _save),
    );
  }
}

/// Supplier khata: balance, purchases and payments.
class SupplierDetailScreen extends ConsumerWidget {
  const SupplierDetailScreen({super.key, required this.supplierId});

  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(supplierProvider(supplierId));
    final balance = async.valueOrNull;
    if (balance == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const ListSkeleton()
            : const NotFoundBody(),
      );
    }
    final entries = ref.watch(supplierEntriesProvider(supplierId)).valueOrNull ??
        const [];
    final due = balance.duePaise;

    return Scaffold(
      appBar: AppBar(
        title: Text(balance.supplier.name),
        actions: [
          IconButton(
            tooltip: tr('Edit'),
            icon: const Icon(Icons.edit),
            onPressed: () => context.push(Routes.editSupplier(supplierId)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          if (balance.supplier.phone != null)
            Text(formatIndianPhone(balance.supplier.phone!)),
          const SizedBox(height: 8),
          Panel(
            child: Column(
              children: [
                AmountRow(label: tr('Purchased'), paise: balance.purchasedPaise),
                AmountRow(label: tr('Paid'), paise: balance.paidPaise),
                const Divider(),
                AmountRow(
                  label: due >= 0 ? tr('Due to supplier') : tr('Advance with supplier'),
                  paise: due.abs(),
                  bold: true,
                  color: due > 0 ? AppColors.successText : AppColors.slate600,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push(Routes.supplierEntry(
                      supplierId, SupplierEntryType.purchase)),
                  icon: const Icon(Icons.shopping_cart),
                  label: Text(tr('Purchase')),
                ),
              ),
              const SizedBox(width: AppSizes.gap),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, AppSizes.tapMin),
                  ),
                  onPressed: () => context.push(Routes.supplierEntry(
                      supplierId, SupplierEntryType.payment)),
                  icon: const Icon(Icons.payments),
                  label: Text(tr('Payment')),
                ),
              ),
            ],
          ),
          SectionTitle(tr('Entries')),
          if (entries.isEmpty)
            Text(tr('No entries yet.'),
                style: TextStyle(color: AppColors.slate600))
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final e in entries)
                    ListTile(
                      leading: Icon(
                        e.entryType == SupplierEntryType.purchase
                            ? Icons.shopping_cart
                            : Icons.payments,
                      ),
                      title: Text(e.entryType == SupplierEntryType.purchase
                          ? (e.billNo == null
                              ? tr('Purchase')
                              : tr('Purchase · Bill {billNo}', {'billNo': e.billNo}))
                          : tr('Payment')),
                      subtitle: Text([
                        dayFormat.format(parseIsoDate(e.date)),
                        if (e.mode != null) paymentModeLabel(e.mode!),
                        if (e.remarks != null && e.remarks!.isNotEmpty)
                          e.remarks!,
                      ].join(' · ')),
                      trailing: Text(
                        '${e.entryType == SupplierEntryType.purchase ? '+' : '−'}'
                        '${formatPaise(e.amountPaise)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onLongPress: () async {
                        final ok = await confirmDialog(
                          context,
                          title: tr('Delete this entry?'),
                          message: formatPaise(e.amountPaise),
                          confirmLabel: tr('Delete'),
                          destructive: true,
                        );
                        if (ok) {
                          await ref
                              .read(expensesRepositoryProvider)
                              .deleteSupplierEntry(e.id);
                        }
                      },
                    ),
                ],
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Purchase on credit (udhaar) or payment to a supplier.
class SupplierEntryScreen extends ConsumerStatefulWidget {
  const SupplierEntryScreen({
    super.key,
    required this.supplierId,
    required this.type,
  });

  final String supplierId;
  final SupplierEntryType type;

  @override
  ConsumerState<SupplierEntryScreen> createState() =>
      _SupplierEntryScreenState();
}

class _SupplierEntryScreenState extends ConsumerState<SupplierEntryScreen> {
  late SupplierEntryType _type = widget.type;
  String _amount = '';
  PaymentMode _mode = PaymentMode.cash;
  DateTime _date = dateOnly(DateTime.now());
  final _billNo = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _billNo.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final paise = parseRupeesToPaise(_amount);
    if (paise == null || paise <= 0) {
      showMessage(context, tr('Enter the amount'));
      return;
    }
    setState(() => _saving = true);
    final isPayment = _type == SupplierEntryType.payment;
    await ref.read(expensesRepositoryProvider).addSupplierEntry(
          supplierId: widget.supplierId,
          type: _type,
          amountPaise: paise,
          date: _date,
          mode: isPayment ? _mode : null,
          billNo: !isPayment && _billNo.text.trim().isNotEmpty
              ? _billNo.text.trim()
              : null,
          remarks: _note.text.trim().isEmpty ? null : _note.text.trim(),
        );
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    showMessage(
        context, isPayment ? tr('✓ Payment saved') : tr('✓ Purchase saved'));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final supplier =
        ref.watch(supplierProvider(widget.supplierId)).valueOrNull?.supplier;
    final isPayment = _type == SupplierEntryType.payment;
    return Scaffold(
      appBar: AppBar(title: Text(supplier?.name ?? tr('Supplier'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          SegmentedButton<SupplierEntryType>(
            segments: [
              ButtonSegment(
                value: SupplierEntryType.purchase,
                label: Text(tr('Purchase (udhaar)')),
              ),
              ButtonSegment(
                value: SupplierEntryType.payment,
                label: Text(tr('Payment')),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          AmountDisplay(text: _amount),
          AmountPad(
            value: _amount,
            onChanged: (v) => setState(() => _amount = v),
          ),
          if (isPayment)
            PaymentModeChips(
              value: _mode,
              onChanged: (m) => setState(() => _mode = m),
            )
          else
            TextField(
              controller: _billNo,
              decoration:
                  InputDecoration(labelText: tr('Supplier bill no. (optional)')),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(
              labelText: tr('Note (optional)'),
              hintText: tr('e.g. 20 bags cement'),
            ),
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
