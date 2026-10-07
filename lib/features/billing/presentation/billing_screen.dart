import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pickers.dart';
import '../data/billing_repository.dart';
import 'billing_widgets.dart';

/// Billing tab (PRD E1): Invoices | Quotations | Clients | Payments.
class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key, this.tab});

  /// Sub-tab requested by the drawer (0 bills … 3 payments).
  final int? tab;

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: (widget.tab ?? 0).clamp(0, 3),
  )..addListener(() => setState(() {}));

  @override
  void didUpdateWidget(BillingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tab = widget.tab;
    if (tab != null && tab != oldWidget.tab) _tabs.animateTo(tab.clamp(0, 3));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Widget? _fab() => switch (_tabs.index) {
        0 => FloatingActionButton.extended(
            onPressed: () => context.push(Routes.newDocument(DocumentKind.invoice)),
            icon: const Icon(Icons.add),
            label: Text(tr('New Bill')),
          ),
        1 => FloatingActionButton.extended(
            onPressed: () =>
                context.push(Routes.newDocument(DocumentKind.quotation)),
            icon: const Icon(Icons.add),
            label: Text(tr('New Quotation')),
          ),
        2 => FloatingActionButton.extended(
            onPressed: () => context.push(Routes.addClient),
            icon: const Icon(Icons.person_add),
            label: Text(tr('New Client')),
          ),
        _ => FloatingActionButton.extended(
            onPressed: () => context.push(Routes.payment()),
            icon: const Icon(Icons.payments),
            label: Text(tr('Payment received')),
          ),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(tr('Billing')),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: tr('Bills')),
            Tab(text: tr('Quotations')),
            Tab(text: tr('Clients')),
            Tab(text: tr('Payments')),
          ],
        ),
      ),
      floatingActionButton: _fab(),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _DocumentsTab(kind: DocumentKind.invoice),
          _DocumentsTab(kind: DocumentKind.quotation),
          _ClientsTab(),
          _PaymentsTab(),
        ],
      ),
    );
  }
}

class _DocumentsTab extends ConsumerWidget {
  const _DocumentsTab({required this.kind});

  final DocumentKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider(kind));
    final isInvoice = kind == DocumentKind.invoice;
    return docs.when(
      loading: () => const ListSkeleton(),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: isInvoice ? Icons.receipt_long : Icons.request_quote,
              title: isInvoice ? tr('No bills yet') : tr('No quotations yet'),
              message: isInvoice
                  ? tr('Make a bill and share the PDF on WhatsApp.')
                  : tr('Make a quotation; convert it to a bill in one tap.'),
              actionLabel: isInvoice ? tr('New Bill') : tr('New Quotation'),
              onAction: () => context.push(Routes.newDocument(kind)),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => DocumentTile(item: list[i]),
            ),
    );
  }
}

class _ClientsTab extends ConsumerWidget {
  const _ClientsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider);
    return clients.when(
      loading: () => const ListSkeleton(),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.people_outline,
              title: tr('No clients yet'),
              message: tr('Add the people you work for.'),
              actionLabel: tr('New Client'),
              onAction: () => context.push(Routes.addClient),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = list[i];
                return ListTile(
                  minVerticalPadding: 12,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.amber100,
                    foregroundColor: AppColors.slate900,
                    child: Text(initials(c.client.name)),
                  ),
                  title: Text(c.client.name),
                  subtitle: c.client.phone == null
                      ? null
                      : Text(formatIndianPhone(c.client.phone!)),
                  trailing: c.outstandingPaise > 0
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatPaise(c.outstandingPaise),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.warningText,
                              ),
                            ),
                            Text(tr('pending'),
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.slate600)),
                          ],
                        )
                      : null,
                  onTap: () => context.push(Routes.client(c.client.id)),
                );
              },
            ),
    );
  }
}

class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(paymentsProvider(null));
    return payments.when(
      loading: () => const ListSkeleton(),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.payments_outlined,
              title: tr('No payments yet'),
              message: tr('Money received from clients shows here.'),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => PaymentTile(item: list[i]),
            ),
    );
  }
}

class PaymentTile extends StatelessWidget {
  const PaymentTile({super.key, required this.item});

  final PaymentItem item;

  @override
  Widget build(BuildContext context) {
    final p = item.payment;
    return ListTile(
      title: Text(item.clientName),
      subtitle: Text([
        dayFormat.format(parseIsoDate(p.date)),
        paymentModeLabel(p.mode),
        if (item.documentNumber != null) item.documentNumber!,
        if (p.remarks != null && p.remarks!.isNotEmpty) p.remarks!,
      ].join(' · ')),
      trailing: Text(
        '+${formatPaise(p.amountPaise)}',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.successText,
        ),
      ),
    );
  }
}
