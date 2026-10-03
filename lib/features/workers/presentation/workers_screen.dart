import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_drawer.dart';
import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/workers_repository.dart';

class WorkersScreen extends ConsumerStatefulWidget {
  const WorkersScreen({super.key});

  @override
  ConsumerState<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends ConsumerState<WorkersScreen> {
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final workers = ref.watch(
      _showInactive ? inactiveWorkersProvider : activeWorkersProvider,
    );

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(_showInactive ? 'Inactive workers' : 'Workers'),
        actions: [
          IconButton(
            tooltip: 'Today\'s attendance',
            icon: const Icon(Icons.fact_check),
            onPressed: () => context.go(Routes.attendance()),
          ),
          PopupMenuButton<bool>(
            onSelected: (value) => setState(() => _showInactive = value),
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: !_showInactive,
                checked: _showInactive,
                child: const Text('Show inactive'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: _showInactive
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(Routes.addWorker),
              icon: const Icon(Icons.person_add),
              label: const Text('Add Worker'),
            ),
      body: workers.when(
        loading: () => const ListSkeleton(),
        error: (error, _) => Center(child: Text('Could not load workers: $error')),
        data: (items) {
          if (items.isEmpty) {
            return _showInactive
                ? const EmptyState(
                    icon: Icons.person_off,
                    title: 'No inactive workers',
                    message: 'Workers you mark as left will show here.',
                  )
                : EmptyState(
                    icon: Icons.groups,
                    title: 'No workers yet',
                    message:
                        'Add your workers to mark attendance and keep khata.',
                    actionLabel: 'Add first worker',
                    onAction: () => context.push(Routes.addWorker),
                  );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              final phone = item.worker.phone;
              final subtitle = [
                if (item.roleName != null) item.roleName!,
                wageLabel(item.wage),
                if (phone != null) formatIndianPhone(phone),
              ].join(' · ');
              return ListTile(
                minVerticalPadding: 12,
                leading: CircleAvatar(
                  backgroundColor: AppColors.amber100,
                  foregroundColor: AppColors.slate900,
                  child: Text(initials(item.worker.name)),
                ),
                title: Text(item.worker.name),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.worker(item.worker.id)),
              );
            },
          );
        },
      ),
    );
  }
}
