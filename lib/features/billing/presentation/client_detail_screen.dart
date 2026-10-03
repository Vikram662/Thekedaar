import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../jobs/data/jobs_repository.dart';
import '../data/billing_repository.dart';
import 'billing_screen.dart';
import 'billing_widgets.dart';

/// Client ledger: billed, received, outstanding (PRD BL-01).
class ClientDetailScreen extends ConsumerWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clientProvider(clientId));
    final balance = async.valueOrNull;
    if (balance == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const NotFoundBody(),
      );
    }
    final client = balance.client;
    final bills = ref.watch(clientDocumentsProvider(clientId)).valueOrNull ?? const [];
    final payments = ref.watch(paymentsProvider(clientId)).valueOrNull ?? const [];
    final jobs = (ref.watch(jobsProvider).valueOrNull ?? const <JobListItem>[])
        .where((j) => j.job.clientId == clientId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(client.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit),
            onPressed: () => context.push(Routes.editClient(clientId)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          if (client.phone != null) Text(formatIndianPhone(client.phone!)),
          if (client.address != null) Text(client.address!),
          const SizedBox(height: 12),
          Panel(
            child: Column(
              children: [
                AmountRow(label: 'Billed', paise: balance.billedPaise),
                AmountRow(
                  label: 'Received',
                  paise: balance.receivedPaise,
                  color: AppColors.successText,
                ),
                const Divider(),
                AmountRow(
                  label: balance.outstandingPaise >= 0 ? 'Pending' : 'Advance with you',
                  paise: balance.outstandingPaise.abs(),
                  bold: true,
                  color: balance.outstandingPaise > 0
                      ? AppColors.warningText
                      : AppColors.successText,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push(
                      Routes.newDocument(DocumentKind.invoice, clientId: clientId)),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('New bill'),
                ),
              ),
              const SizedBox(width: AppSizes.gap),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.push(Routes.payment(clientId: clientId)),
                  icon: const Icon(Icons.payments),
                  label: const Text('Payment'),
                ),
              ),
            ],
          ),
          SectionTitle(
            'Jobs / sites',
            trailing: TextButton.icon(
              onPressed: () => context.push(Routes.addJob(clientId: clientId)),
              icon: const Icon(Icons.add),
              label: const Text('New job'),
            ),
          ),
          if (jobs.isEmpty)
            const Text('No jobs yet.', style: TextStyle(color: AppColors.slate600))
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final j in jobs)
                    ListTile(
                      title: Text(j.job.title),
                      subtitle: Text(jobStatusLabel(j.job.status)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.job(j.job.id)),
                    ),
                ],
              ),
            ),
          const SectionTitle('Bills'),
          if (bills.isEmpty)
            const Text('No bills yet.', style: TextStyle(color: AppColors.slate600))
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [for (final b in bills) DocumentTile(item: b)],
              ),
            ),
          const SectionTitle('Payments'),
          if (payments.isEmpty)
            const Text('No payments yet.',
                style: TextStyle(color: AppColors.slate600))
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [for (final p in payments) PaymentTile(item: p)],
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
