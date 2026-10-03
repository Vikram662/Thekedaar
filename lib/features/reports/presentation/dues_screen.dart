import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/pdf/pdf_common.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../billing/data/billing_repository.dart';
import '../../expenses/data/expenses_repository.dart';
import '../../khata/data/khata_repository.dart';
import '../../lock/app_lock_controller.dart';
import '../domain/dues_pdf.dart';
import '../domain/dues_report.dart';

/// Combined Lena / Dena report from clients, bills and worker balances.
final duesReportProvider = Provider<AsyncValue<DuesReport>>((ref) {
  final clients = ref.watch(clientsProvider);
  final invoices = ref.watch(documentsProvider(DocumentKind.invoice));
  final workers = ref.watch(allWorkerBalancesProvider);
  final suppliers = ref.watch(suppliersProvider);
  for (final value in [clients, invoices, workers, suppliers]) {
    if (value.hasError) {
      return AsyncValue.error(
          value.error!, value.stackTrace ?? StackTrace.current);
    }
  }
  if (!clients.hasValue ||
      !invoices.hasValue ||
      !workers.hasValue ||
      !suppliers.hasValue) {
    return const AsyncValue.loading();
  }
  return AsyncValue.data(buildDuesReport(
    clients: clients.requireValue,
    invoices: invoices.requireValue,
    workers: workers.requireValue,
    suppliers: suppliers.requireValue,
  ));
});

class DuesScreen extends ConsumerWidget {
  const DuesScreen({super.key, this.initialTab = 0});

  /// 0 = Lena, 1 = Dena.
  final int initialTab;

  Future<void> _sharePdf(
    BuildContext context,
    WidgetRef ref,
    DuesReport report,
  ) async {
    final profile = await ref.read(businessProfileProvider.future);
    if (profile == null) return;
    final bytes = await buildDuesPdf(report, profile);
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    try {
      await sharePdf(bytes, fileName: 'Lena-Dena-report.pdf');
    } finally {
      lock.suspendRelock = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(duesReportProvider);
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lena / Dena'),
          actions: [
            if (report.hasValue)
              IconButton(
                tooltip: 'Share PDF',
                icon: const Icon(Icons.picture_as_pdf),
                onPressed: () => _sharePdf(context, ref, report.requireValue),
              ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(
                text: report.hasValue
                    ? 'Lena ${formatPaise(report.requireValue.lenaTotal)}'
                    : 'Lena',
              ),
              Tab(
                text: report.hasValue
                    ? 'Dena ${formatPaise(report.requireValue.denaTotal)}'
                    : 'Dena',
              ),
            ],
          ),
        ),
        body: report.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (r) => TabBarView(
            children: [
              _DueList(
                items: r.lena,
                receive: true,
                header: r.overdueTotal > 0
                    ? 'Overdue (due date passed): ${formatPaise(r.overdueTotal)}'
                    : null,
              ),
              _DueList(items: r.dena, receive: false),
            ],
          ),
        ),
      ),
    );
  }
}

class _DueList extends ConsumerWidget {
  const _DueList({required this.items, required this.receive, this.header});

  final List<DueItem> items;
  final bool receive;
  final String? header;

  Future<void> _remind(BuildContext context, WidgetRef ref, DueItem item) async {
    final profile = await ref.read(businessProfileProvider.future);
    final business = profile?.name ?? '';
    final upi = profile?.upiId;
    final text = 'Hello ${item.name}, payment of ${formatPaise(item.amountPaise)} '
        'is pending with $business.'
        '${upi == null || upi.isEmpty ? '' : ' UPI: $upi.'}'
        ' Please pay at the earliest. Thank you.';
    final lock = ref.read(appLockProvider);
    lock.suspendRelock = true;
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } finally {
      lock.suspendRelock = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return EmptyState(
        icon: receive ? Icons.call_received : Icons.call_made,
        title: receive ? 'Nothing to receive' : 'Nothing to pay',
        message: receive
            ? 'No client or worker owes you money right now.'
            : 'All workers and suppliers are paid up.',
      );
    }
    final color = receive ? AppColors.warningText : AppColors.successText;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (header != null)
          Container(
            width: double.infinity,
            color: AppColors.dangerSurface,
            padding: const EdgeInsets.all(12),
            child: Text(
              header!,
              style: const TextStyle(
                color: AppColors.dangerText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        for (final item in items) ...[
          ListTile(
            minVerticalPadding: 12,
            leading: CircleAvatar(
              backgroundColor: AppColors.amber100,
              foregroundColor: AppColors.slate900,
              child: Icon(dueParty(item.party).icon),
            ),
            title: Text(item.name),
            subtitle: Text([
              dueParty(item.party).label,
              if (item.overduePaise > 0)
                'Overdue ${formatPaise(item.overduePaise)}',
              if (!receive && item.party == DueParty.client)
                'Advance received',
            ].join(' · ')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatPaise(item.amountPaise),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                if (receive && item.party == DueParty.client)
                  IconButton(
                    tooltip: 'Send reminder',
                    icon: const Icon(Icons.send),
                    onPressed: () => _remind(context, ref, item),
                  ),
              ],
            ),
            onTap: () => context.push(switch (item.party) {
              DueParty.client => Routes.client(item.id),
              DueParty.worker => Routes.worker(item.id),
              DueParty.supplier => Routes.supplier(item.id),
            }),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

({String label, IconData icon}) dueParty(DueParty party) => switch (party) {
      DueParty.client => (label: 'Client', icon: Icons.person_outline),
      DueParty.worker => (label: 'Worker', icon: Icons.engineering),
      DueParty.supplier => (label: 'Supplier', icon: Icons.store),
    };

/// Lena / Dena summary card for the dashboard.
class DuesSummaryCard extends ConsumerWidget {
  const DuesSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(duesReportProvider).valueOrNull;
    Widget half({
      required String label,
      required int paise,
      required Color color,
      required IconData icon,
      required int tab,
      String? note,
    }) =>
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSizes.radius),
            onTap: () => context.push(Routes.dues(tab)),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: color),
                      const SizedBox(width: 6),
                      Text(label),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    report == null ? '…' : formatPaise(paise),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  Text(
                    note ?? ' ',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.dangerText),
                  ),
                ],
              ),
            ),
          ),
        );

    return Row(
      children: [
        half(
          label: 'Lena (to receive)',
          paise: report?.lenaTotal ?? 0,
          color: AppColors.warningText,
          icon: Icons.call_received,
          tab: 0,
          note: (report?.overdueTotal ?? 0) > 0
              ? 'Overdue ${formatPaise(report!.overdueTotal)}'
              : null,
        ),
        const SizedBox(width: AppSizes.gap),
        half(
          label: 'Dena (to pay)',
          paise: report?.denaTotal ?? 0,
          color: AppColors.successText,
          icon: Icons.call_made,
          tab: 1,
        ),
      ],
    );
  }
}
