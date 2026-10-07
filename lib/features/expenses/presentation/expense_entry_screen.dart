import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/photos.dart';
import '../../../core/widgets/amount_pad.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../../jobs/presentation/job_picker.dart';
import '../../lock/app_lock_controller.dart';
import '../data/expenses_repository.dart';

/// PRD EX-01: amount → category → mode → Save.
class ExpenseEntryScreen extends ConsumerStatefulWidget {
  const ExpenseEntryScreen({super.key, this.jobId});

  final String? jobId;

  @override
  ConsumerState<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

class _ExpenseEntryScreenState extends ConsumerState<ExpenseEntryScreen> {
  String _amount = '';
  String? _categoryId;
  late String? _jobId = widget.jobId;
  String? _photoName;
  PaymentMode _mode = PaymentMode.cash;
  DateTime _date = dateOnly(DateTime.now());
  final _note = TextEditingController();
  bool _saving = false;

  bool _saved = false;

  @override
  void dispose() {
    _note.dispose();
    // Photo taken but expense not saved: do not leave the file behind.
    if (!_saved) deletePhoto(_photoName);
    super.dispose();
  }

  Future<void> _takePhoto(bool fromCamera) async {
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    try {
      final name = await captureBillPhoto(fromCamera: fromCamera);
      if (name == null) return;
      await deletePhoto(_photoName); // replace the previous one
      setState(() => _photoName = name);
    } catch (e) {
      if (mounted) showMessage(context, tr('Could not take photo: {e}', {'e': errorText(e)}));
    } finally {
      lock.suspendRelock = false;
    }
  }

  Future<void> _newCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('New category')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: tr('Category name')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(tr('Add')),
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
      showMessage(context, tr('Enter the amount'));
      return;
    }
    if (_categoryId == null) {
      showMessage(context, tr('Choose a category'));
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
            jobId: _jobId,
            photoName: _photoName,
          );
      _saved = true;
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context, tr('✓ Expense {amount} saved', {'amount': formatPaise(paise)}));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, tr('Could not save: {e}', {'e': errorText(e)}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoriesProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(tr('New expense'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          AmountDisplay(text: _amount),
          AmountPad(
            value: _amount,
            onChanged: (v) => setState(() => _amount = v),
          ),
          SectionTitle(
            tr('Category'),
            trailing: TextButton.icon(
              onPressed: _newCategory,
              icon: const Icon(Icons.add),
              label: Text(tr('New')),
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
          SectionTitle(tr('Paid by')),
          PaymentModeChips(
            value: _mode,
            onChanged: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: 12),
          JobPickerField(
            jobId: _jobId,
            onChanged: (id) => setState(() => _jobId = id),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(labelText: tr('Note (optional)')),
          ),
          SectionTitle(tr('Bill photo (optional)')),
          Row(
            children: [
              if (_photoName != null) ...[
                InkWell(
                  onTap: () => showPhoto(context, _photoName!),
                  child: PhotoThumb(name: _photoName!, size: 72),
                ),
                const SizedBox(width: AppSizes.gap),
              ],
              Expanded(
                child: Wrap(
                  spacing: AppSizes.gap,
                  runSpacing: AppSizes.gap,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _takePhoto(true),
                      icon: const Icon(Icons.photo_camera),
                      label: Text(_photoName == null ? tr('Camera') : tr('Retake')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _takePhoto(false),
                      icon: const Icon(Icons.photo_library),
                      label: Text(tr('Gallery')),
                    ),
                    if (_photoName != null)
                      IconButton(
                        tooltip: tr('Remove photo'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await deletePhoto(_photoName);
                          setState(() => _photoName = null);
                        },
                      ),
                  ],
                ),
              ),
            ],
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
