import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_drawer.dart';
import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/tasks_repository.dart';

IconData taskTypeIcon(TaskType type) => switch (type) {
      TaskType.siteVisit => Icons.location_on_outlined,
      TaskType.clientMeeting => Icons.handshake_outlined,
      TaskType.materialProcurement => Icons.local_shipping_outlined,
      TaskType.workerPayment => Icons.payments_outlined,
      TaskType.engineerReview => Icons.engineering_outlined,
      TaskType.other => Icons.task_alt_outlined,
    };

Color taskTypeColor(TaskType type) => switch (type) {
      TaskType.siteVisit => AppColors.blue700,
      TaskType.clientMeeting => AppColors.amber500,
      TaskType.materialProcurement => Colors.teal,
      TaskType.workerPayment => AppColors.successText,
      TaskType.engineerReview => AppColors.blue700,
      TaskType.other => AppColors.slate600,
    };

/// PRD C8: Site Tasks, Visits & Reminders Screen
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  int _filterIndex = 0; // 0 = Upcoming, 1 = All, 2 = Completed

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Tasks & Reminders')),
      ),
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.addTask),
        icon: const Icon(Icons.add_alarm),
        label: Text(tr('New task')),
      ),
      body: Column(
        children: [
          // Filter segmented tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                _filterChip(tr('Upcoming'), 0),
                const SizedBox(width: 8),
                _filterChip(tr('All'), 1),
                const SizedBox(width: 8),
                _filterChip(tr('Completed'), 2),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: tasksAsync.when(
              loading: () => const ListSkeleton(),
              error: (e, _) => Center(child: Text(tr('Error loading tasks: {e}', {'e': e}))),
              data: (list) {
                final filtered = list.where((item) {
                  if (_filterIndex == 0) return !item.task.isCompleted;
                  if (_filterIndex == 2) return item.task.isCompleted;
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.notifications_none_outlined,
                    title: _filterIndex == 2
                        ? tr('No completed tasks')
                        : tr('No tasks scheduled'),
                    message:
                        tr('Schedule client meetings, site visits, or material follow-ups.'),
                    actionLabel: tr('New task'),
                    onAction: () => context.push(Routes.addTask),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    return _TaskCard(
                      item: item,
                      onToggleAlert: (active) => ref
                          .read(tasksRepositoryProvider)
                          .toggleAlert(item.task.id, active),
                      onToggleCompleted: (completed) => ref
                          .read(tasksRepositoryProvider)
                          .toggleCompleted(item.task.id, completed),
                      onDelete: () => _confirmDelete(context, item.task.id),
                      onEdit: () => context.push(Routes.editTask(item.task.id)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, int index) {
    final selected = _filterIndex == index;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filterIndex = index),
      selectedColor: AppColors.amber500,
      labelStyle: TextStyle(
        color: selected ? AppColors.slate900 : AppColors.slate600,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Delete task?')),
        content: Text(tr('This will cancel all scheduled reminder alarms.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.dangerFill),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(tasksRepositoryProvider).deleteTask(id);
    }
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.item,
    required this.onToggleAlert,
    required this.onToggleCompleted,
    required this.onDelete,
    required this.onEdit,
  });

  final TaskReminderItem item;
  final ValueChanged<bool> onToggleAlert;
  final ValueChanged<bool> onToggleCompleted;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final task = item.task;
    final scheduledDate = DateTime.fromMillisecondsSinceEpoch(task.scheduledAt);
    final isOverdue =
        !task.isCompleted && scheduledDate.isBefore(DateTime.now());

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: task.isCompleted
              ? AppColors.border
              : isOverdue
                  ? AppColors.dangerFill.withOpacity(0.5)
                  : AppColors.border,
          width: isOverdue ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Type chip, Date & Alert toggle
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: taskTypeColor(task.taskType).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        taskTypeIcon(task.taskType),
                        size: 14,
                        color: taskTypeColor(task.taskType),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        task.taskType.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: taskTypeColor(task.taskType),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Bell alert toggle
                IconButton(
                  icon: Icon(
                    task.isAlertActive
                        ? Icons.notifications_active
                        : Icons.notifications_off_outlined,
                    color: task.isAlertActive
                        ? AppColors.amber500
                        : AppColors.slate600.withOpacity(0.5),
                    size: 22,
                  ),
                  tooltip:
                      task.isAlertActive ? tr('Turn off alert') : tr('Turn on alert'),
                  onPressed: () => onToggleAlert(!task.isAlertActive),
                ),
                // Edit & Delete menu
                PopupMenuButton<String>(
                  onSelected: (val) {
                    if (val == 'edit') onEdit();
                    if (val == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(tr('Delete'),
                          style: TextStyle(color: AppColors.dangerText)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Title & Completed Checkbox
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: task.isCompleted,
                  onChanged: (v) => onToggleCompleted(v ?? false),
                  activeColor: AppColors.successFill,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.isCompleted
                              ? AppColors.slate600
                              : AppColors.slate900,
                        ),
                      ),
                      if (item.jobTitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            tr('Site: {jobTitle}', {'jobTitle': item.jobTitle}),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.blue700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // Time & Date row
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color:
                        isOverdue ? AppColors.dangerText : AppColors.slate600,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    DateFormat('d MMM yyyy, h:mm a', uiDateLocale).format(scheduledDate),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isOverdue ? FontWeight.w700 : FontWeight.w500,
                      color:
                          isOverdue ? AppColors.dangerText : AppColors.slate600,
                    ),
                  ),
                  if (task.intervalMinutes != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        tr('• Repeat every {intervalMinutes}m', {'intervalMinutes': task.intervalMinutes}),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.slate600,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Person & Phone action if available
            if (task.personName != null || task.phone != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 48),
                child: Row(
                  children: [
                    if (task.personName != null)
                      Text(
                        task.personName!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (task.phone != null) ...[
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: () => launchUrl(Uri.parse('tel:${task.phone}')),
                        child: Row(
                          children: [
                            const Icon(Icons.phone,
                                size: 13, color: AppColors.blue700),
                            const SizedBox(width: 4),
                            Text(
                              formatIndianPhone(task.phone!),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.blue700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.chat_bubble_outline,
                            size: 16, color: Colors.green),
                        tooltip: tr('WhatsApp'),
                        onPressed: () => launchUrl(
                          Uri.parse('https://wa.me/${task.phone}?text=Hello'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // Notes
            if (task.notes != null && task.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 48),
                child: Text(
                  task.notes!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.slate600.withValues(alpha: 0.8),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
