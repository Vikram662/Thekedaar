import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/utils/measurement.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/billing_repository.dart';
import '../domain/document_totals.dart';
import 'measurement_sheet.dart';

class LineEditResult {
  const LineEditResult.save(DraftLine this.line) : delete = false;
  const LineEditResult.delete()
      : line = null,
        delete = true;

  final DraftLine? line;
  final bool delete;
}

String lineTypeLabel(LineType type) => switch (type) {
      LineType.material => 'Material',
      LineType.labour => 'Labour',
      LineType.workRate => 'Work-rate',
      LineType.lumpSum => 'Lump-sum',
    };

Future<LineEditResult?> editLine(BuildContext context, {DraftLine? initial}) =>
    Navigator.of(context).push<LineEditResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _LineEditorScreen(initial: initial),
      ),
    );

/// PRD BL-03 / BL-04 / BL-06 / BL-16: one bill line.
class _LineEditorScreen extends ConsumerStatefulWidget {
  const _LineEditorScreen({this.initial});

  final DraftLine? initial;

  @override
  ConsumerState<_LineEditorScreen> createState() => _LineEditorScreenState();
}

class _LineEditorScreenState extends ConsumerState<_LineEditorScreen> {
  late LineType _type = widget.initial?.lineType ?? LineType.workRate;
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _qty = TextEditingController(
    text: widget.initial == null || widget.initial!.qtyMilli == 0
        ? ''
        : formatMilli(widget.initial!.qtyMilli),
  );
  late final _rate = TextEditingController(
    text: widget.initial == null || widget.initial!.ratePaise == 0
        ? ''
        : paiseToInputText(widget.initial!.ratePaise),
  );
  late String? _itemId = widget.initial?.itemId;
  late String? _unitId = widget.initial?.unitId;
  late String? _unitCode = widget.initial?.unitCode;
  late List<MeasurementEntry> _measurement =
      widget.initial?.measurement ?? const [];

  @override
  void initState() {
    super.initState();
    for (final c in [_qty, _rate]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _qty, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isLumpSum => _type == LineType.lumpSum;

  int get _qtyMilli =>
      _isLumpSum ? milliPerUnit : (parseQtyToMilli(_qty.text) ?? 0);

  int get _ratePaise => parseRupeesToPaise(_rate.text) ?? 0;

  ItemKind? get _kind => switch (_type) {
        LineType.material => ItemKind.material,
        LineType.labour => ItemKind.labour,
        LineType.workRate => ItemKind.workRate,
        LineType.lumpSum => null,
      };

  Future<void> _pickItem() async {
    final kind = _kind;
    final items = (ref.read(itemsProvider).valueOrNull ?? const [])
        .where((i) => kind == null || i.item.kind == kind)
        .toList();
    final picked = await showPickerSheet<ItemWithUnit>(
      context,
      title: 'Choose ${lineTypeLabel(_type).toLowerCase()} item',
      options: items,
      label: (i) => i.item.name,
      subtitle: (i) => [
        'per ${i.unit.name}',
        if (i.item.defaultRatePaise != null)
          'last rate ${formatPaise(i.item.defaultRatePaise!)}',
      ].join(' · '),
    );
    if (picked == null) return;
    setState(() {
      _itemId = picked.item.id;
      _name.text = picked.item.name;
      _unitId = picked.unit.id;
      _unitCode = picked.unit.code;
      if (picked.item.defaultRatePaise != null && _rate.text.isEmpty) {
        _rate.text = paiseToInputText(picked.item.defaultRatePaise!);
      }
    });
  }

  Future<void> _pickUnit() async {
    final units = ref.read(unitsProvider).valueOrNull ?? const <Unit>[];
    final picked = await showPickerSheet<Unit>(
      context,
      title: 'Unit',
      options: units,
      label: (u) => u.name,
      selected: units.where((u) => u.id == _unitId).firstOrNull,
    );
    if (picked != null) {
      setState(() {
        _unitId = picked.id;
        _unitCode = picked.code;
      });
    }
  }

  Future<void> _measure() async {
    final result = await showMeasurementSheet(context, _measurement);
    if (result == null) return;
    setState(() {
      _measurement = result.entries;
      _qty.text = formatMilli(result.totalMilli);
    });
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, 'Enter the item or work name');
      return;
    }
    if (!_isLumpSum && _qtyMilli <= 0) {
      showMessage(context, 'Enter quantity');
      return;
    }
    if (_ratePaise <= 0) {
      showMessage(context, _isLumpSum ? 'Enter amount' : 'Enter rate');
      return;
    }
    Navigator.of(context).pop(LineEditResult.save(DraftLine(
      lineType: _type,
      name: name,
      qtyMilli: _qtyMilli,
      ratePaise: _ratePaise,
      itemId: _itemId,
      unitId: _isLumpSum ? null : _unitId,
      unitCode: _isLumpSum ? null : _unitCode,
      measurement: _isLumpSum ? const [] : _measurement,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(unitsProvider).valueOrNull ?? const <Unit>[];
    final unitName = units.where((u) => u.id == _unitId).firstOrNull?.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Add line' : 'Edit line'),
        actions: [
          if (widget.initial != null)
            IconButton(
              tooltip: 'Delete line',
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  Navigator.of(context).pop(const LineEditResult.delete()),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          SegmentedButton<LineType>(
            showSelectedIcon: false,
            segments: [
              for (final t in LineType.values)
                ButtonSegment(value: t, label: Text(lineTypeLabel(t))),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _itemId = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _isLumpSum ? 'Description' : 'Item / work',
              suffixIcon: _isLumpSum
                  ? null
                  : IconButton(
                      tooltip: 'Choose from rate list',
                      icon: const Icon(Icons.list),
                      onPressed: _pickItem,
                    ),
            ),
            onChanged: (_) => _itemId = null,
          ),
          const SizedBox(height: 12),
          if (!_isLumpSum) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qty,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      suffixIcon: IconButton(
                        tooltip: 'Measure (L × W × H)',
                        icon: const Icon(Icons.straighten),
                        onPressed: _measure,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSizes.gap),
                Expanded(
                  child: PickerField(
                    label: 'Unit',
                    value: unitName,
                    onTap: _pickUnit,
                  ),
                ),
              ],
            ),
            if (_measurement.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'From measurement: ${_measurement.length} rows',
                  style: const TextStyle(color: AppColors.slate600),
                ),
              ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
              labelText: _isLumpSum
                  ? 'Amount'
                  : 'Rate${unitName == null ? '' : ' per $unitName'}',
              prefixText: '₹ ',
            ),
          ),
          const SizedBox(height: 16),
          Panel(
            child: AmountRow(
              label: 'Line amount',
              paise: lineAmountPaise(_qtyMilli, _ratePaise),
              bold: true,
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(label: 'Done', onPressed: _save),
    );
  }
}
