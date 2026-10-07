import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/measurement.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';

class MeasurementResult {
  const MeasurementResult(this.entries);

  final List<MeasurementEntry> entries;

  int get totalMilli => measurementTotalMilli(entries);
}

/// PRD BL-16: rows of nos × L × W × H, with deductions (doors, windows).
/// Returns null if cancelled.
Future<MeasurementResult?> showMeasurementSheet(
  BuildContext context,
  List<MeasurementEntry> initial,
) {
  return Navigator.of(context).push<MeasurementResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _MeasurementPage(initial: initial),
    ),
  );
}

class _Row {
  _Row({MeasurementEntry? entry, this.isDeduction = false})
      : label = TextEditingController(text: entry?.label ?? ''),
        nos = TextEditingController(text: '${entry?.nos ?? 1}'),
        length = TextEditingController(
            text: entry == null ? '' : formatMilli(entry.lengthMilli)),
        width = TextEditingController(
            text: entry?.widthMilli == null ? '' : formatMilli(entry!.widthMilli!)),
        height = TextEditingController(
            text: entry?.heightMilli == null
                ? ''
                : formatMilli(entry!.heightMilli!)) {
    if (entry != null) isDeduction = entry.isDeduction;
  }

  final TextEditingController label;
  final TextEditingController nos;
  final TextEditingController length;
  final TextEditingController width;
  final TextEditingController height;
  bool isDeduction;

  Iterable<TextEditingController> get controllers =>
      [label, nos, length, width, height];

  MeasurementEntry? toEntry() {
    final l = parseQtyToMilli(length.text);
    if (l == null || l <= 0) return null;
    return MeasurementEntry(
      label: label.text.trim(),
      nos: int.tryParse(nos.text.trim()) ?? 1,
      lengthMilli: l,
      widthMilli: parseQtyToMilli(width.text),
      heightMilli: parseQtyToMilli(height.text),
      isDeduction: isDeduction,
    );
  }

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
  }
}

class _MeasurementPage extends StatefulWidget {
  const _MeasurementPage({required this.initial});

  final List<MeasurementEntry> initial;

  @override
  State<_MeasurementPage> createState() => _MeasurementPageState();
}

class _MeasurementPageState extends State<_MeasurementPage> {
  late final List<_Row> _rows = widget.initial.isEmpty
      ? [_Row()]
      : [for (final e in widget.initial) _Row(entry: e)];

  @override
  void initState() {
    super.initState();
    for (final row in _rows) {
      _listen(row);
    }
  }

  void _listen(_Row row) {
    for (final c in row.controllers) {
      c.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _add({bool deduction = false}) {
    final row = _Row(isDeduction: deduction);
    _listen(row);
    setState(() => _rows.add(row));
  }

  List<MeasurementEntry> get _entries =>
      [for (final r in _rows) r.toEntry()].whereType<MeasurementEntry>().toList();

  @override
  Widget build(BuildContext context) {
    final total = measurementTotalMilli(_entries);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Measurement'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          Text(
            tr('Enter length, and width or height as needed. Use the same unit (ft or m) for all rows.'),
            style: TextStyle(color: AppColors.slate600),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _rows.length; i++) _rowCard(i),
          Wrap(
            spacing: AppSizes.gap,
            children: [
              OutlinedButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: Text(tr('Add row')),
              ),
              OutlinedButton.icon(
                onPressed: () => _add(deduction: true),
                icon: const Icon(Icons.remove),
                label: Text(tr('Add deduction')),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        label: tr('Use total {total}', {'total': formatMilli(total)}),
        onPressed: total <= 0
            ? null
            : () => Navigator.of(context).pop(MeasurementResult(_entries)),
      ),
    );
  }

  Widget _rowCard(int index) {
    final row = _rows[index];
    final entry = row.toEntry();
    InputDecoration dec(String label) => InputDecoration(
          labelText: label,
          isDense: true,
        );
    TextField number(TextEditingController c, String label) => TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: dec(label),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.gap),
      child: Panel(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.label,
                    decoration: dec(row.isDeduction
                        ? tr('Deduction (e.g. Door)')
                        : tr('Label (e.g. Hall wall)')),
                  ),
                ),
                IconButton(
                  tooltip: tr('Remove row'),
                  onPressed: _rows.length == 1
                      ? null
                      : () {
                          final removed = _rows.removeAt(index);
                          setState(() {});
                          // Fields still hold the controllers until rebuilt.
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) => removed.dispose());
                        },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(width: 56, child: number(row.nos, tr('Nos'))),
                const SizedBox(width: 6),
                Expanded(child: number(row.length, 'L')),
                const SizedBox(width: 6),
                Expanded(child: number(row.width, 'W')),
                const SizedBox(width: 6),
                Expanded(child: number(row.height, 'H')),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                entry == null
                    ? '—'
                    : '${row.isDeduction ? '− ' : ''}${formatMilli(entry.qtyMilli)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: row.isDeduction ? AppColors.dangerText : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
