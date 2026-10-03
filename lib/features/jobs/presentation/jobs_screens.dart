import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/photos.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../billing/presentation/billing_widgets.dart';
import '../data/jobs_repository.dart';

StatusChip jobStatusChip(JobStatus status) => switch (status) {
      JobStatus.planned => StatusChip(
          label: jobStatusLabel(status),
          color: AppColors.slate600,
          icon: Icons.schedule,
        ),
      JobStatus.inProgress => StatusChip(
          label: jobStatusLabel(status),
          color: AppColors.blue700,
          icon: Icons.construction,
        ),
      JobStatus.completed => StatusChip(
          label: jobStatusLabel(status),
          color: AppColors.successText,
          icon: Icons.check_circle,
        ),
    };

/// PRD JB-01: all jobs / sites, open ones first.
class JobsScreen extends ConsumerWidget {
  const JobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Jobs / Sites')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.addJob()),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('New job'),
      ),
      body: jobs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.location_city,
                title: 'No jobs yet',
                message: 'Add a site to track its bills and expenses together.',
                actionLabel: 'New job',
                onAction: () => context.push(Routes.addJob()),
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final item = list[i];
                  return ListTile(
                    minVerticalPadding: 12,
                    title: Text(item.job.title),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          jobStatusChip(item.job.status),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              item.clientName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.job(item.job.id)),
                  );
                },
              ),
      ),
    );
  }
}

class JobFormScreen extends ConsumerStatefulWidget {
  const JobFormScreen({super.key, this.jobId, this.clientId});

  final String? jobId;
  final String? clientId;

  @override
  ConsumerState<JobFormScreen> createState() => _JobFormScreenState();
}

class _JobFormScreenState extends ConsumerState<JobFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _site = TextEditingController();
  final _contract = TextEditingController();
  late String? _clientId = widget.clientId;
  JobStatus _status = JobStatus.inProgress;
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_title, _site, _contract]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_clientId == null) {
      showMessage(context, 'Choose a client');
      return;
    }
    setState(() => _saving = true);
    final site = _site.text.trim();
    final id = await ref.read(jobsRepositoryProvider).saveJob(
          id: widget.jobId,
          clientId: _clientId!,
          title: _title.text.trim(),
          siteAddress: site.isEmpty ? null : site,
          status: _status,
          contractValuePaise: parseRupeesToPaise(_contract.text),
        );
    if (!mounted) return;
    if (widget.jobId == null) {
      context.pushReplacement(Routes.job(id));
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.jobId != null && !_loaded) {
      final detail = ref.watch(jobDetailProvider(widget.jobId!)).valueOrNull;
      if (detail == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      _loaded = true;
      final job = detail.job;
      _title.text = job.title;
      _site.text = job.siteAddress ?? '';
      _contract.text = job.contractValuePaise == null
          ? ''
          : paiseToInputText(job.contractValuePaise!);
      _clientId = job.clientId;
      _status = job.status;
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.jobId == null ? 'New job' : 'Edit job')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.gutter),
          children: [
            ClientPickerField(
              clientId: _clientId,
              onChanged: (id) => setState(() => _clientId = id),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Job name',
                hintText: 'e.g. Sharma ji 2BHK wiring',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter job name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _site,
              maxLines: 2,
              decoration:
                  const InputDecoration(labelText: 'Site address (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contract,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Contract value (optional)',
                prefixText: '₹ ',
              ),
              validator: (v) => v == null ||
                      v.trim().isEmpty ||
                      parseRupeesToPaise(v) != null
                  ? null
                  : 'Enter a valid amount',
            ),
            const SectionTitle('Status'),
            SegmentedButton<JobStatus>(
              segments: [
                for (final s in JobStatus.values)
                  ButtonSegment(value: s, label: Text(jobStatusLabel(s))),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          BottomActionBar(label: 'Save', busy: _saving, onPressed: _save),
    );
  }
}

/// PRD JB-01 / EX-03: one site with its bills, expenses and rough profit.
class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(jobDetailProvider(jobId));
    final d = async.valueOrNull;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const NotFoundBody(),
      );
    }
    final job = d.job;

    return Scaffold(
      appBar: AppBar(
        title: Text(job.title),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit),
            onPressed: () => context.push(Routes.editJob(jobId)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          Row(
            children: [
              jobStatusChip(job.status),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => context.push(Routes.client(d.client.id)),
                  child: Text(d.client.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
            ],
          ),
          if (job.siteAddress != null) ...[
            const SizedBox(height: 4),
            Text(job.siteAddress!),
          ],
          const SizedBox(height: 12),
          Panel(
            child: Column(
              children: [
                if (job.contractValuePaise != null)
                  AmountRow(label: 'Contract value', paise: job.contractValuePaise!),
                AmountRow(label: 'Billed', paise: d.billedPaise),
                AmountRow(
                  label: 'Received',
                  paise: d.receivedPaise,
                  color: AppColors.successText,
                ),
                const Divider(),
                AmountRow(label: 'Expenses', paise: d.expensesPaise, prefix: '− '),
                if (d.piecePaise > 0)
                  AmountRow(label: 'Piece work', paise: d.piecePaise, prefix: '− '),
                const Divider(),
                AmountRow(
                  label: d.profitPaise >= 0 ? 'Profit' : 'Loss',
                  paise: d.profitPaise.abs(),
                  bold: true,
                  color: d.profitPaise >= 0
                      ? AppColors.successText
                      : AppColors.dangerText,
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Daily-wage labour is not counted here yet.',
                    style: TextStyle(fontSize: 12, color: AppColors.slate600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push(Routes.newDocument(
                    DocumentKind.invoice,
                    clientId: d.client.id,
                    jobId: jobId,
                  )),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('New bill'),
                ),
              ),
              const SizedBox(width: AppSizes.gap),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push(Routes.expenseForJob(jobId)),
                  icon: const Icon(Icons.receipt),
                  label: const Text('Expense'),
                ),
              ),
            ],
          ),
          const SectionTitle('Bills'),
          if (d.bills.isEmpty)
            const Text('No bills linked to this job.',
                style: TextStyle(color: AppColors.slate600))
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final b in d.bills)
                    ListTile(
                      title: Text(b.number),
                      subtitle: Row(
                        children: [
                          documentStatusChip(b.status, b.kind),
                          const SizedBox(width: 8),
                          Text(dayFormat.format(parseIsoDate(b.date))),
                        ],
                      ),
                      trailing: Text(formatPaise(b.totalPaise),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => context.push(Routes.document(b.id)),
                    ),
                ],
              ),
            ),
          const SectionTitle('Expenses'),
          if (d.expenses.isEmpty)
            const Text('No expenses linked to this job.',
                style: TextStyle(color: AppColors.slate600))
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final e in d.expenses)
                    ListTile(
                      leading: e.photoPath == null
                          ? null
                          : InkWell(
                              onTap: () => showPhoto(context, e.photoPath!),
                              child: PhotoThumb(name: e.photoPath!, size: 44),
                            ),
                      title: Text(e.remarks?.isNotEmpty == true
                          ? e.remarks!
                          : 'Expense'),
                      subtitle: Text(dayFormat.format(parseIsoDate(e.date))),
                      trailing: Text(formatPaise(e.amountPaise),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
