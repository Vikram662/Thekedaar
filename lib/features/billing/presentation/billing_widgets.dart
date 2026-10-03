import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../data/billing_repository.dart';

/// Status pill with icon + label (PRD BL-15, I-D3).
StatusChip documentStatusChip(DocumentStatus status, DocumentKind kind) {
  final (label, color, icon) = switch (status) {
    DocumentStatus.draft => ('Draft', AppColors.slate600, Icons.edit_note),
    DocumentStatus.sent => (
        kind == DocumentKind.invoice ? 'Unpaid' : 'Sent',
        AppColors.warningText,
        Icons.send,
      ),
    DocumentStatus.partiallyPaid =>
      ('Part paid', AppColors.blue700, Icons.timelapse),
    DocumentStatus.paid => ('Paid', AppColors.successText, Icons.check_circle),
    DocumentStatus.cancelled =>
      ('Cancelled', AppColors.dangerText, Icons.block),
  };
  return StatusChip(label: label, color: color, icon: icon);
}

class DocumentTile extends StatelessWidget {
  const DocumentTile({super.key, required this.item});

  final DocumentListItem item;

  @override
  Widget build(BuildContext context) {
    final doc = item.document;
    final showBalance = doc.kind == DocumentKind.invoice &&
        doc.status != DocumentStatus.cancelled &&
        item.paidPaise > 0 &&
        item.balancePaise > 0;
    return ListTile(
      minVerticalPadding: 12,
      title: Text(item.clientName),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            documentStatusChip(doc.status, doc.kind),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${doc.number} · ${dayFormat.format(parseIsoDate(doc.date))}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatPaise(doc.totalPaise),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (showBalance)
            Text(
              'Due ${formatPaise(item.balancePaise)}',
              style: const TextStyle(fontSize: 12, color: AppColors.warningText),
            ),
        ],
      ),
      onTap: () => context.push(Routes.document(doc.id)),
    );
  }
}

/// Field to choose a client, with "+ New client" inline (PRD BL-01).
class ClientPickerField extends ConsumerWidget {
  const ClientPickerField({
    super.key,
    required this.clientId,
    required this.onChanged,
  });

  final String? clientId;
  final ValueChanged<String> onChanged;

  Future<void> _newClient(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New client'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile (optional)',
                prefixText: '+91 ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final clientName = name.text.trim();
    final clientPhone = normalizeIndianPhone(phone.text);
    name.dispose();
    phone.dispose();
    if (created != true || clientName.isEmpty) return;
    final id = await ref.read(billingRepositoryProvider).saveClient(
          name: clientName,
          phone: clientPhone,
        );
    onChanged(id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider).valueOrNull ?? const [];
    final selected = clients.where((c) => c.client.id == clientId).firstOrNull;
    return PickerField(
      label: 'Client',
      icon: Icons.person_outline,
      value: selected?.client.name,
      onTap: () async {
        const newClient = '__new__';
        final picked = await showPickerSheet<String>(
          context,
          title: 'Choose client',
          options: [newClient, for (final c in clients) c.client.id],
          label: (id) => id == newClient
              ? '+ New client'
              : clients.firstWhere((c) => c.client.id == id).client.name,
          selected: clientId,
        );
        if (picked == null || !context.mounted) return;
        if (picked == newClient) {
          await _newClient(context, ref);
        } else {
          onChanged(picked);
        }
      },
    );
  }
}
