import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/pdf/pdf_common.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/photos.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/common.dart';
import '../../lock/app_lock_controller.dart';
import '../data/billing_repository.dart';
import '../domain/document_pdf.dart';
import 'billing_screen.dart';
import 'billing_widgets.dart';

class DocumentDetailScreen extends ConsumerWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    DocumentDetail detail,
  ) async {
    final profile = await ref.read(businessProfileProvider.future);
    if (profile == null) return;
    final bytes = await buildDocumentPdf(detail, profile);
    final doc = detail.document;
    final isInvoice = doc.kind == DocumentKind.invoice;
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    try {
      await sharePdf(
        bytes,
        fileName: '${doc.number}.pdf',
        text: '${isInvoice ? 'Bill' : 'Quotation'} ${doc.number} from '
            '${profile.name}: ${formatPaise(doc.totalPaise)}'
            '${isInvoice && detail.balancePaise > 0 && detail.paidPaise > 0 ? ' (due ${formatPaise(detail.balancePaise)})' : ''}',
      );
    } finally {
      lock.suspendRelock = false;
    }
    await ref.read(billingRepositoryProvider).markSentIfDraft(doc.id);
  }

  Future<void> _convert(BuildContext context, WidgetRef ref) async {
    final id =
        await ref.read(billingRepositoryProvider).convertToInvoice(documentId);
    if (context.mounted) context.pushReplacement(Routes.document(id));
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Cancel this document?',
      message: 'It stays in the list as Cancelled and is not counted '
          'in pending amounts.',
      confirmLabel: 'Cancel document',
      destructive: true,
    );
    if (ok) {
      await ref
          .read(billingRepositoryProvider)
          .setStatus(documentId, DocumentStatus.cancelled);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(documentDetailProvider(documentId));
    final detail = async.valueOrNull;
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const ListSkeleton()
            : const NotFoundBody(),
      );
    }
    final doc = detail.document;
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    final isInvoice = doc.kind == DocumentKind.invoice;
    final cancelled = doc.status == DocumentStatus.cancelled;
    final payments = isInvoice
        ? (ref.watch(paymentsProvider(doc.clientId)).valueOrNull ?? const [])
            .where((p) => p.payment.documentId == doc.id)
            .toList()
        : const <PaymentItem>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(doc.number),
        actions: [
          if (!cancelled)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit),
              onPressed: () => context.push(Routes.editDocument(doc.id)),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'cancel') _cancel(context, ref);
              if (v == 'client') context.push(Routes.client(doc.clientId));
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'client', child: Text('Open client')),
              if (!cancelled)
                const PopupMenuItem(value: 'cancel', child: Text('Cancel document')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          if (profile != null) ...[
            Row(
              children: [
                if (profile.logoPath != null) ...[
                  PhotoThumb(
                    key: ValueKey(profile.logoPath),
                    name: profile.logoPath!,
                    size: 40,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    profile.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              documentStatusChip(doc.status, doc.kind),
              const SizedBox(width: 8),
              Text(isInvoice ? 'Bill (non-tax)' : 'Quotation'),
              if (doc.revision > 1) Text('  · Rev ${doc.revision}'),
            ],
          ),
          const SizedBox(height: 12),
          Text(detail.client.name, style: Theme.of(context).textTheme.titleLarge),
          Text(dayFormat.format(parseIsoDate(doc.date)) +
              (doc.dueDate == null
                  ? ''
                  : ' · Due ${dayFormat.format(parseIsoDate(doc.dueDate!))}')),
          const SectionTitle('Lines'),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final l in detail.lines)
                  ListTile(
                    title: Text(l.line.name),
                    subtitle: Text(l.line.lineType == LineType.lumpSum
                        ? 'Lump-sum'
                        : '${formatMilli(l.line.qtyMilli)} ${l.unitCode ?? ''} × '
                            '${formatPaise(l.line.ratePaise)}'),
                    trailing: Text(formatPaise(l.line.amountPaise),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Panel(
            child: Column(
              children: [
                AmountRow(label: 'Subtotal', paise: doc.subtotalPaise),
                if (doc.discountPaise != 0)
                  AmountRow(
                      label: 'Discount', paise: doc.discountPaise, prefix: '− '),
                if (doc.roundOffPaise != 0)
                  AmountRow(label: 'Round off', paise: doc.roundOffPaise),
                const Divider(),
                AmountRow(label: 'Total', paise: doc.totalPaise, bold: true),
                if (isInvoice && !cancelled) ...[
                  AmountRow(
                    label: 'Received',
                    paise: detail.paidPaise,
                    color: AppColors.successText,
                  ),
                  AmountRow(
                    label: 'Balance due',
                    paise: detail.balancePaise,
                    bold: true,
                    color: detail.balancePaise > 0
                        ? AppColors.warningText
                        : AppColors.successText,
                  ),
                ],
              ],
            ),
          ),
          if (!isInvoice && detail.convertedInvoiceId != null) ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link),
              title: const Text('Converted to a bill'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  context.push(Routes.document(detail.convertedInvoiceId!)),
            ),
          ],
          if (payments.isNotEmpty) ...[
            const SectionTitle('Payments'),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [for (final p in payments) PaymentTile(item: p)],
              ),
            ),
          ],
          if (doc.notes != null) ...[
            const SectionTitle('Notes'),
            Text(doc.notes!),
          ],
          const SizedBox(height: 32),
        ],
      ),
      bottomNavigationBar: cancelled
          ? null
          : BottomActionBar(
              label: 'Share PDF',
              onPressed: () => _share(context, ref, detail),
              top: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    if (isInvoice && detail.balancePaise > 0)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(Routes.payment(
                            clientId: doc.clientId,
                            documentId: doc.id,
                          )),
                          icon: const Icon(Icons.payments),
                          label: const Text('Payment received'),
                        ),
                      ),
                    if (!isInvoice)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _convert(context, ref),
                          icon: const Icon(Icons.receipt_long),
                          label: Text(detail.convertedInvoiceId == null
                              ? 'Convert to bill'
                              : 'Make another bill'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
