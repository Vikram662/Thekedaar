import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_pad.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/expenses_repository.dart';

/// PRD EX-01: amount → category → mode → Save.
class ExpenseEntryScreen extends ConsumerStatefulWidget {
  const ExpenseEntryScreen({super.key});

  @override
  ConsumerState<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

class _ExpenseEntryScreenState extends ConsumerState<ExpenseEntryScreen> {
  String _amount = '';
  String? _categoryId;
  PaymentMode _mode = PaymentMode.cash;
  DateTime _date = dateOnly(DateTime.now());
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _newCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final id = await ref.read(expensesRepositoryProvider).addCategory(name);
    setState(() => _categoryId = id);
  }

  Future<void> _save() async {
    final paise = parseRupeesToPaise(_amount);
    if (paise == null || paise <= 0) {
      showMessage(context, 'Enter the amount');
      return;
    }
    if (_categoryId == null) {
      showMessage(context, 'Choose a category');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(expensesRepositoryProvider).addExpense(
            categoryId: _categoryId!,
            amountPaise: paise,
            mode: _mode,
            date: _date,
            remarks: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context, '✓ Expense ${formatPaise(paise)} saved');
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoriesProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('New expense')),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          AmountDisplay(text: _amount),
          AmountPad(
            value: _amount,
            onChanged: (v) => setState(() => _amount = v),
          ),
          SectionTitle(
            'Category',
            trailing: TextButton.icon(
              onPressed: _newCategory,
              icon: const Icon(Icons.add),
              label: const Text('New'),
            ),
          ),
          Wrap(
            spacing: AppSizes.gap,
            runSpacing: AppSizes.gap,
            children: [
              for (final c in categories)
                ChoiceChip(
                  label: Text(c.name),
                  selected: _categoryId == c.id,
                  onSelected: (_) => setState(() => _categoryId = c.id),
                ),
            ],
          ),
          const SectionTitle('Paid by'),
          PaymentModeChips(
            value: _mode,
            onChanged: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(dayFormat.format(_date)),
            trailing: const Text('Change'),
            onTap: () async {
              final picked =
                  await pickDate(context, initial: _date, last: DateTime.now());
              if (picked != null) setState(() => _date = dateOnly(picked));
            },
          ),
        ],
      ),
      bottomNavigationBar:
          BottomActionBar(label: 'Save', busy: _saving, onPressed: _save),
    );
  }
}
