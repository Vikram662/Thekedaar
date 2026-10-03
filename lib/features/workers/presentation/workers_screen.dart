import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/workers_repository.dart';

class WorkersScreen extends ConsumerWidget {
  const WorkersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workers = ref.watch(activeWorkersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Workers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.addWorker),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Worker'),
      ),
      body: workers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load workers: $error')),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.groups,
              title: 'No workers yet',
              message: 'Add your workers to mark attendance and keep khata.',
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
                if (phone != null) formatIndianPhone(phone),
              ].join(' · ');
              return ListTile(
                minVerticalPadding: 12,
                leading: CircleAvatar(
                  backgroundColor: AppColors.amber100,
                  foregroundColor: AppColors.slate900,
                  child: Text(item.worker.name.characters.first.toUpperCase()),
                ),
                title: Text(item.worker.name),
                subtitle: subtitle.isEmpty ? null : Text(subtitle),
              );
            },
          );
        },
      ),
    );
  }
}
