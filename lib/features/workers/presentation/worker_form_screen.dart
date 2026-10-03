import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/workers_repository.dart';

/// PRD WK-01 / WK-02: add a worker, or edit name/phone/role/UPI.
/// Wage changes go through [ChangeWageScreen] to keep history.
class WorkerFormScreen extends ConsumerStatefulWidget {
  const WorkerFormScreen({super.key, this.workerId});

  final String? workerId;

  @override
  ConsumerState<WorkerFormScreen> createState() => _WorkerFormScreenState();
}

class _WorkerFormScreenState extends ConsumerState<WorkerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _upi = TextEditingController();
  final _rate = TextEditingController();
  final _otRate = TextEditingController();
  String? _roleId;
  WageModel _model = WageModel.daily;
  DateTime _joinDate = dateOnly(DateTime.now());
  bool _saving = false;
  bool _loaded = false;

  bool get _isEdit => widget.workerId != null;

  @override
  void dispose() {
    for (final c in [_name, _phone, _upi, _rate, _otRate]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fillFrom(WorkerListItem item) {
    if (_loaded) return;
    _loaded = true;
    final w = item.worker;
    _name.text = w.name;
    _phone.text = w.phone == null ? '' : formatIndianPhone(w.phone!);
    _upi.text = w.upiId ?? '';
    _roleId = w.roleId;
    _joinDate = parseIsoDate(w.joinDate);
  }

  String? _validateAmount(String? value, {required bool isRequired}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return isRequired ? 'Enter amount' : null;
    final paise = parseRupeesToPaise(text);
    if (paise == null || paise < 0) return 'Enter a valid amount';
    if (isRequired && paise == 0) return 'Enter amount';
    return null;
  }

  Future<void> _addRole() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New role'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Role name'),
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
    final id = await ref.read(workersRepositoryProvider).addRole(name);
    setState(() => _roleId = id);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(workersRepositoryProvider);
    final name = _name.text.trim();
    final upi = _upi.text.trim();
    try {
      if (_isEdit) {
        await repo.updateWorker(
          id: widget.workerId!,
          name: name,
          phone: normalizeIndianPhone(_phone.text),
          roleId: _roleId,
          upiId: upi.isEmpty ? null : upi,
        );
      } else {
        final settings = await ref.read(appSettingsProvider.future);
        await repo.addWorker(NewWorker(
          name: name,
          phone: normalizeIndianPhone(_phone.text),
          roleId: _roleId,
          upiId: upi.isEmpty ? null : upi,
          joinDate: _joinDate,
          wageModel: _model,
          ratePaise:
              _model == WageModel.piece ? 0 : parseRupeesToPaise(_rate.text)!,
          otRatePaise: parseRupeesToPaise(_otRate.text) ?? 0,
          monthlyDivisor: settings.monthlyDivisor,
        ));
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context, _isEdit ? 'Saved' : '$name added');
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'Could not save. Please try again. ($error)');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEdit) {
      final item = ref.watch(workerProvider(widget.workerId!)).valueOrNull;
      if (item == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      _fillFrom(item);
    }
    final roles = ref.watch(rolesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Worker' : 'Add Worker')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.gutter),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Enter name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile number (optional)',
                prefixText: '+91 ',
              ),
              validator: (value) => (value == null ||
                      value.trim().isEmpty ||
                      normalizeIndianPhone(value) != null)
                  ? null
                  : 'Enter a valid 10-digit mobile number',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _upi,
              decoration: const InputDecoration(
                labelText: 'UPI ID (optional)',
                hintText: 'name@bank',
              ),
            ),
            SectionTitle(
              'Role',
              trailing: TextButton.icon(
                onPressed: _addRole,
                icon: const Icon(Icons.add),
                label: const Text('New role'),
              ),
            ),
            roles.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('Could not load roles: $error'),
              data: (list) => Wrap(
                spacing: AppSizes.gap,
                runSpacing: AppSizes.gap,
                children: [
                  for (final role in list)
                    ChoiceChip(
                      label: Text(role.name),
                      selected: _roleId == role.id,
                      onSelected: (selected) =>
                          setState(() => _roleId = selected ? role.id : null),
                    ),
                ],
              ),
            ),
            if (!_isEdit) ...[
              const SectionTitle('Wage'),
              SegmentedButton<WageModel>(
                segments: const [
                  ButtonSegment(value: WageModel.daily, label: Text('Daily')),
                  ButtonSegment(
                      value: WageModel.monthly, label: Text('Monthly')),
                  ButtonSegment(
                      value: WageModel.piece, label: Text('Piece-rate')),
                ],
                selected: {_model},
                onSelectionChanged: (selection) =>
                    setState(() => _model = selection.first),
              ),
              const SizedBox(height: 12),
              if (_model == WageModel.piece)
                Text(
                  'Rate is entered with each piece-work entry (e.g. per sq.ft).',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.slate600),
                )
              else
                TextFormField(
                  controller: _rate,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 20),
                  decoration: InputDecoration(
                    labelText: _model == WageModel.daily
                        ? 'Rate per day'
                        : 'Salary per month',
                    prefixText: '₹ ',
                  ),
                  validator: (v) => _validateAmount(v, isRequired: true),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _otRate,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'OT rate per hour (optional)',
                  prefixText: '₹ ',
                ),
                validator: (v) => _validateAmount(v, isRequired: false),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Joining date'),
                subtitle: Text(dayFormat.format(_joinDate)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await pickDate(
                    context,
                    initial: _joinDate,
                    last: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _joinDate = dateOnly(picked));
                  }
                },
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        label: 'Save',
        busy: _saving,
        onPressed: _save,
      ),
    );
  }
}
