import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/billing_repository.dart';
import '../../jobs/presentation/job_picker.dart';
import '../domain/document_totals.dart';
import 'billing_widgets.dart';
import 'line_editor_screen.dart';

/// Create or edit a bill / quotation (PRD BL-02..BL-07).
class DocumentEditorScreen extends ConsumerStatefulWidget {
  const DocumentEditorScreen({
    super.key,
    required this.kind,
    this.documentId,
    this.clientId,
    this.jobId,
  });

  final DocumentKind kind;
  final String? documentId;
  final String? clientId;
  final String? jobId;

  @override
  ConsumerState<DocumentEditorScreen> createState() =>
      _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends ConsumerState<DocumentEditorScreen> {
  late DocumentKind _kind = widget.kind;
  late String? _clientId = widget.clientId;
  late String? _jobId = widget.jobId;
  DateTime _date = dateOnly(DateTime.now());
  DateTime? _dueDate;
  final List<DraftLine> _lines = [];
  bool _percentDiscount = false;
  final _discount = TextEditingController();
  bool _roundOff = true;
  final _notes = TextEditingController();
  final _terms = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _number;

  @override
  void initState() {
    super.initState();
    _discount.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    for (final c in [_discount, _notes, _terms]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(billingRepositoryProvider);
    if (widget.documentId == null) {
      _terms.text = await repo.defaultTerms();
    } else {
      final detail = await repo.watchDocument(widget.documentId!).first;
      if (detail != null) {
        final d = detail.document;
        _kind = d.kind;
        _number = d.number;
        _clientId = d.clientId;
        _jobId = d.jobId;
        _date = parseIsoDate(d.date);
        _dueDate = d.dueDate == null ? null : parseIsoDate(d.dueDate!);
        _lines.addAll(detail.lines.map((l) => l.toDraft()));
        _percentDiscount = d.discountPercentBp != null;
        _discount.text = d.discountPercentBp != null
            ? paiseToInputText(d.discountPercentBp!)
            : (d.discountPaise == 0 ? '' : paiseToInputText(d.discountPaise));
        _roundOff = d.roundOff;
        _notes.text = d.notes ?? '';
        _terms.text = d.terms ?? '';
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  DocumentDraft _draft() {
    final discountValue = parseScaledDiscount(_discount.text);
    return DocumentDraft(
      id: widget.documentId,
      kind: _kind,
      clientId: _clientId ?? '',
      jobId: _jobId,
      date: _date,
      dueDate: _dueDate,
      lines: List.of(_lines),
      discountPercentBp: _percentDiscount ? discountValue : null,
      discountPaise: _percentDiscount ? 0 : discountValue,
      roundOff: _roundOff,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      terms: _terms.text.trim().isEmpty ? null : _terms.text.trim(),
    );
  }

  /// Rupees or percent, both with 2 decimals → integer (paise / basis points).
  static int parseScaledDiscount(String text) =>
      parseRupeesToPaise(text.trim().isEmpty ? '0' : text) ?? 0;

  Future<void> _addLine() async {
    final result = await editLine(context);
    if (result?.line != null) setState(() => _lines.add(result!.line!));
  }

  Future<void> _editLine(int index) async {
    final result = await editLine(context, initial: _lines[index]);
    if (result == null) return;
    setState(() {
      if (result.delete) {
        _lines.removeAt(index);
      } else {
        _lines[index] = result.line!;
      }
    });
  }

  Future<void> _useTemplate() async {
    final templates = ref.read(templatesProvider).valueOrNull ?? const [];
    final picked = await showPickerSheet<BillTemplate>(
      context,
      title: 'Start from template',
      options: templates,
      label: (t) => t.name,
    );
    if (picked == null) return;
    final lines =
        await ref.read(billingRepositoryProvider).linesFromTemplate(picked);
    setState(() => _lines.addAll(lines));
    if (mounted && lines.any((l) => l.qtyMilli == 0)) {
      showMessage(context, 'Template added. Tap each line to enter quantity.');
    }
  }

  Future<void> _save() async {
    if (_clientId == null) {
      showMessage(context, 'Choose a client');
      return;
    }
    if (_lines.isEmpty) {
      showMessage(context, 'Add at least one line');
      return;
    }
    final blank = _lines.indexWhere((l) => l.qtyMilli <= 0 || l.ratePaise <= 0);
    if (blank >= 0) {
      showMessage(context, 'Line ${blank + 1}: enter quantity and rate');
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref.read(billingRepositoryProvider).saveDocument(_draft());
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (widget.documentId == null) {
        context.pushReplacement(Routes.document(id));
      } else {
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInvoice = _kind == DocumentKind.invoice;
    final title = widget.documentId == null
        ? (isInvoice ? 'New Bill' : 'New Quotation')
        : 'Edit ${_number ?? ''}';
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const ListSkeleton(),
      );
    }
    final totals = _draft().totals;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          ClientPickerField(
            clientId: _clientId,
            onChanged: (id) => setState(() {
              if (id != _clientId) _jobId = null;
              _clientId = id;
            }),
          ),
          if (_clientId != null) ...[
            const SizedBox(height: 12),
            JobPickerField(
              clientId: _clientId,
              jobId: _jobId,
              onChanged: (id) => setState(() => _jobId = id),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PickerField(
                  label: 'Date',
                  icon: Icons.event,
                  value: dayFormat.format(_date),
                  onTap: () async {
                    final picked = await pickDate(context, initial: _date);
                    if (picked != null) setState(() => _date = dateOnly(picked));
                  },
                ),
              ),
              if (isInvoice) ...[
                const SizedBox(width: AppSizes.gap),
                Expanded(
                  child: PickerField(
                    label: 'Due date',
                    value: _dueDate == null ? null : dayFormat.format(_dueDate!),
                    onTap: () async {
                      final picked =
                          await pickDate(context, initial: _dueDate ?? _date);
                      if (picked != null) {
                        setState(() => _dueDate = dateOnly(picked));
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
          SectionTitle(
            'Items & work',
            trailing: _lines.isEmpty
                ? TextButton.icon(
                    onPressed: _useTemplate,
                    icon: const Icon(Icons.auto_awesome_motion),
                    label: const Text('Template'),
                  )
                : null,
          ),
          if (_lines.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('No lines yet.',
                  style: TextStyle(color: AppColors.slate600)),
            ),
          for (var i = 0; i < _lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.gap),
              child: _LineCard(
                index: i + 1,
                line: _lines[i],
                onTap: () => _editLine(i),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _addLine,
            icon: const Icon(Icons.add),
            label: const Text('Add line'),
          ),
          const SectionTitle('Discount & total'),
          Row(
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('₹')),
                  ButtonSegment(value: true, label: Text('%')),
                ],
                selected: {_percentDiscount},
                onSelectionChanged: (s) =>
                    setState(() => _percentDiscount = s.first),
              ),
              const SizedBox(width: AppSizes.gap),
              Expanded(
                child: TextField(
                  controller: _discount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _percentDiscount ? 'Discount %' : 'Discount ₹',
                  ),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Round off to nearest rupee'),
            value: _roundOff,
            onChanged: (v) => setState(() => _roundOff = v),
          ),
          Panel(
            child: Column(
              children: [
                AmountRow(label: 'Subtotal', paise: totals.subtotalPaise),
                if (totals.discountPaise != 0)
                  AmountRow(
                    label: 'Discount',
                    paise: totals.discountPaise,
                    prefix: '− ',
                  ),
                if (totals.roundOffPaise != 0)
                  AmountRow(label: 'Round off', paise: totals.roundOffPaise),
                const Divider(),
                AmountRow(label: 'Total', paise: totals.totalPaise, bold: true),
              ],
            ),
          ),
          const SectionTitle('Notes & terms'),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _terms,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Terms & conditions (one per line)',
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        label: 'Save ${formatPaise(totals.totalPaise)}',
        busy: _saving,
        onPressed: _save,
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.index,
    required this.line,
    required this.onTap,
  });

  final int index;
  final DraftLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final incomplete = line.qtyMilli <= 0 || line.ratePaise <= 0;
    final detail = line.lineType == LineType.lumpSum
        ? 'Lump-sum'
        : '${formatMilli(line.qtyMilli)} ${line.unitCode ?? ''} × '
            '${formatPaise(line.ratePaise)}';
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        side: BorderSide(
          color: incomplete ? AppColors.warningFill : AppColors.border,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(radius: 14, child: Text('$index')),
        title: Text(line.name),
        subtitle: Text(incomplete ? 'Tap to enter quantity and rate' : detail),
        trailing: Text(
          formatPaise(line.amountPaise),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
