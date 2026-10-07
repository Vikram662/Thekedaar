import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/audit.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../../billing/data/billing_repository.dart';
import '../../billing/presentation/measurement_sheet.dart';
import '../../jobs/presentation/job_picker.dart';
import '../../workers/presentation/worker_picker.dart';
import '../data/khata_repository.dart';

/// PRD WK-05: piece-rate / theka work — kaam × qty × rate.
class PieceWorkScreen extends ConsumerStatefulWidget {
  const PieceWorkScreen({super.key, this.workerId});

  final String? workerId;

  @override
  ConsumerState<PieceWorkScreen> createState() => _PieceWorkScreenState();
}

class _PieceWorkScreenState extends ConsumerState<PieceWorkScreen> {
  late String? _workerId = widget.workerId;
  final _description = TextEditingController();
  final _qty = TextEditingController();
  final _rate = TextEditingController();
  String? _itemId;
  String? _jobId;
  Unit? _unit;
  DateTime _date = dateOnly(DateTime.now());
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_qty, _rate]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_description, _qty, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _amount {
    final qty = parseQtyToMilli(_qty.text);
    final rate = parseRupeesToPaise(_rate.text);
    return qty == null || rate == null ? 0 : lineAmountPaise(qty, rate);
  }

  Future<void> _pickItem() async {
    final items = (ref.read(itemsProvider).valueOrNull ?? const [])
        .where((i) => i.item.kind != ItemKind.material)
        .toList();
    final picked = await showPickerSheet<ItemWithUnit>(
      context,
      title: tr('Choose work'),
      options: items,
      label: (i) => i.item.name,
      subtitle: (i) => tr('per {name}', {'name': i.unit.name}),
    );
    if (picked == null) return;
    setState(() {
      _itemId = picked.item.id;
      _description.text = picked.item.name;
      _unit = picked.unit;
    });
  }

  Future<void> _pickUnit() async {
    final units = ref.read(unitsProvider).valueOrNull ?? const [];
    final picked = await showPickerSheet<Unit>(
      context,
      title: tr('Unit'),
      options: units,
      label: (u) => u.name,
      selected: _unit,
    );
    if (picked != null) setState(() => _unit = picked);
  }

  Future<void> _measure() async {
    final total = await showMeasurementSheet(context, const []);
    if (total != null) _qty.text = formatMilli(total.totalMilli);
  }

  Future<void> _save() async {
    final qty = parseQtyToMilli(_qty.text);
    final rate = parseRupeesToPaise(_rate.text);
    final description = _description.text.trim();
    final problem = _workerId == null
        ? tr('Choose a worker')
        : description.isEmpty
            ? tr('Enter the work')
            : qty == null || qty <= 0
                ? tr('Enter quantity')
                : rate == null || rate <= 0
                    ? tr('Enter rate')
                    : null;
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(khataRepositoryProvider).addPieceWork(
            workerId: _workerId!,
            date: _date,
            description: description,
            qtyMilli: qty!,
            ratePaise: rate!,
            itemId: _itemId,
            unitId: _unit?.id,
            jobId: _jobId,
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context, tr('Piece work saved: {amount}', {'amount': formatPaise(_amount)}));
      context.pop();
    } on PeriodLockedException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Piece work'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          WorkerPickerField(
            workerId: _workerId,
            onChanged: (w) => setState(() => _workerId = w.worker.id),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: InputDecoration(
              labelText: tr('Work'),
              hintText: tr('e.g. Floor tiling'),
              suffixIcon: IconButton(
                tooltip: tr('Choose from list'),
                icon: const Icon(Icons.list),
                onPressed: _pickItem,
              ),
            ),
            onChanged: (_) => _itemId = null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 20),
                  decoration: InputDecoration(
                    labelText: tr('Quantity'),
                    suffixIcon: IconButton(
                      tooltip: tr('Measure (L × W × H)'),
                      icon: const Icon(Icons.straighten),
                      onPressed: _measure,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.gap),
              Expanded(
                child: PickerField(
                  label: tr('Unit'),
                  value: _unit?.name,
                  onTap: _pickUnit,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
              labelText: _unit == null
                  ? tr('Rate')
                  : tr('Rate per {unit}', {'unit': _unit!.name}),
              prefixText: '₹ ',
            ),
          ),
          const SizedBox(height: 12),
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
          JobPickerField(
            jobId: _jobId,
            onChanged: (id) => setState(() => _jobId = id),
          ),
          const SizedBox(height: 8),
          Panel(
            child: AmountRow(label: tr('Amount'), paise: _amount, bold: true),
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
