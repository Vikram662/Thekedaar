import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/audit.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/db/tables.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/notify/notifications.dart';
import '../../../core/utils/ids.dart';
import '../../../core/widgets/common.dart';

final tasksRepositoryProvider = Provider<TasksRepository>(
  (ref) => TasksRepository(ref.watch(databaseProvider)),
);

final tasksProvider = StreamProvider<List<TaskReminderItem>>(
  (ref) => ref.watch(tasksRepositoryProvider).watchTasks(),
);

final pendingTasksProvider = StreamProvider<List<TaskReminderItem>>(
  (ref) => ref.watch(tasksRepositoryProvider).watchPendingTasks(),
);

final taskByIdProvider = StreamProvider.family<TaskReminder?, String>(
  (ref, id) => ref.watch(tasksRepositoryProvider).watchTask(id),
);

class TaskReminderItem {
  const TaskReminderItem({
    required this.task,
    this.jobTitle,
  });

  final TaskReminder task;
  final String? jobTitle;

  String get title => task.title;
  TaskType get taskType => task.taskType;
  DateTime get dueAt => DateTime.fromMillisecondsSinceEpoch(task.scheduledAt);
}

class TasksRepository {
  TasksRepository(this._db);

  final AppDatabase _db;

  Stream<List<TaskReminderItem>> watchTasks() {
    final query = _db.select(_db.taskReminders).join([
      leftOuterJoin(
        _db.jobs,
        _db.jobs.id.equalsExp(_db.taskReminders.jobId),
      ),
    ])
      ..orderBy([
        OrderingTerm(
          expression: _db.taskReminders.scheduledAt,
          mode: OrderingMode.asc,
        ),
      ]);

    return query.watch().map(
          (rows) => rows.map((r) {
            final task = r.readTable(_db.taskReminders);
            final job = r.readTableOrNull(_db.jobs);
            return TaskReminderItem(
              task: task,
              jobTitle: job?.title,
            );
          }).toList(),
        );
  }

  Stream<List<TaskReminderItem>> watchPendingTasks() {
    final query = _db.select(_db.taskReminders).join([
      leftOuterJoin(
        _db.jobs,
        _db.jobs.id.equalsExp(_db.taskReminders.jobId),
      ),
    ])
      ..where(_db.taskReminders.isCompleted.equals(false))
      ..orderBy([
        OrderingTerm(
          expression: _db.taskReminders.scheduledAt,
          mode: OrderingMode.asc,
        ),
      ]);

    return query.watch().map(
          (rows) => rows.map((r) {
            final task = r.readTable(_db.taskReminders);
            final job = r.readTableOrNull(_db.jobs);
            return TaskReminderItem(
              task: task,
              jobTitle: job?.title,
            );
          }).toList(),
        );
  }

  Stream<TaskReminder?> watchTask(String id) {
    return (_db.select(_db.taskReminders)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<TaskReminder?> getTask(String id) =>
      (_db.select(_db.taskReminders)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> saveTask({
    String? id,
    required String title,
    required TaskType taskType,
    String? jobId,
    String? personName,
    String? phone,
    required DateTime scheduledAt,
    int? intervalMinutes,
    bool isAlertActive = true,
    String? notes,
  }) async {
    final now = nowMs();
    if (id == null) {
      final taskId = newId();
      final entry = TaskRemindersCompanion(
        id: Value(taskId),
        title: Value(title.trim()),
        taskType: Value(taskType),
        jobId: Value(jobId),
        personName: Value(personName?.trim()),
        phone: Value(phone?.trim()),
        scheduledAt: Value(scheduledAt.millisecondsSinceEpoch),
        intervalMinutes: Value(intervalMinutes),
        isAlertActive: Value(isAlertActive),
        isCompleted: const Value(false),
        notes: Value(notes?.trim()),
        createdAt: Value(now),
        updatedAt: Value(now),
      );

      await _db.into(_db.taskReminders).insert(entry);
      await writeAudit(
        _db,
        entity: 'TaskReminder',
        entityId: taskId,
        action: AuditAction.create,
        after: {
          'title': title,
          'type': taskType.name,
          'scheduledAt': scheduledAt.toIso8601String()
        },
      );

      if (isAlertActive && scheduledAt.isAfter(DateTime.now())) {
        await _scheduleNotification(
          id: taskId,
          title: title,
          taskType: taskType,
          scheduledAt: scheduledAt,
          intervalMinutes: intervalMinutes,
        );
      }
    } else {
      final existing = await getTask(id);
      if (existing == null) return;

      await (_db.update(_db.taskReminders)..where((t) => t.id.equals(id)))
          .write(
        TaskRemindersCompanion(
          title: Value(title.trim()),
          taskType: Value(taskType),
          jobId: Value(jobId),
          personName: Value(personName?.trim()),
          phone: Value(phone?.trim()),
          scheduledAt: Value(scheduledAt.millisecondsSinceEpoch),
          intervalMinutes: Value(intervalMinutes),
          isAlertActive: Value(isAlertActive),
          notes: Value(notes?.trim()),
          updatedAt: Value(now),
        ),
      );

      await writeAudit(
        _db,
        entity: 'TaskReminder',
        entityId: id,
        action: AuditAction.update,
        before: {'title': existing.title, 'scheduledAt': existing.scheduledAt},
        after: {
          'title': title,
          'scheduledAt': scheduledAt.millisecondsSinceEpoch
        },
      );

      await AppNotifications.instance.cancelTaskNotifications(id);
      if (isAlertActive && scheduledAt.isAfter(DateTime.now())) {
        await _scheduleNotification(
          id: id,
          title: title,
          taskType: taskType,
          scheduledAt: scheduledAt,
          intervalMinutes: intervalMinutes,
        );
      }
    }
  }

  Future<void> toggleAlert(String id, bool active) async {
    final task = await getTask(id);
    if (task == null) return;

    await (_db.update(_db.taskReminders)..where((t) => t.id.equals(id))).write(
      TaskRemindersCompanion(
        isAlertActive: Value(active),
        updatedAt: Value(nowMs()),
      ),
    );

    if (!active) {
      await AppNotifications.instance.cancelTaskNotifications(id);
    } else {
      final scheduledAt = DateTime.fromMillisecondsSinceEpoch(task.scheduledAt);
      if (scheduledAt.isAfter(DateTime.now())) {
        await _scheduleNotification(
          id: id,
          title: task.title,
          taskType: task.taskType,
          scheduledAt: scheduledAt,
          intervalMinutes: task.intervalMinutes,
        );
      }
    }
  }

  Future<void> toggleCompleted(String id, bool completed) async {
    final task = await getTask(id);
    if (task == null) return;

    await (_db.update(_db.taskReminders)..where((t) => t.id.equals(id))).write(
      TaskRemindersCompanion(
        isCompleted: Value(completed),
        isAlertActive: Value(!completed),
        updatedAt: Value(nowMs()),
      ),
    );

    if (completed) {
      await AppNotifications.instance.cancelTaskNotifications(id);
    } else {
      final scheduledAt = DateTime.fromMillisecondsSinceEpoch(task.scheduledAt);
      if (scheduledAt.isAfter(DateTime.now())) {
        await _scheduleNotification(
          id: id,
          title: task.title,
          taskType: task.taskType,
          scheduledAt: scheduledAt,
          intervalMinutes: task.intervalMinutes,
        );
      }
    }
  }

  Future<void> _scheduleNotification({
    required String id,
    required String title,
    required TaskType taskType,
    required DateTime scheduledAt,
    required int? intervalMinutes,
  }) =>
      AppNotifications.instance.scheduleTaskNotifications(
        taskId: id,
        title: '${taskType.label}: $title',
        body: tr('Scheduled for {date}. Tap to open.',
            {'date': dayTimeFormat.format(scheduledAt)}),
        scheduledAt: scheduledAt,
        intervalMinutes: intervalMinutes,
      );
  Future<void> deleteTask(String id) async {
    final existing = await getTask(id);
    if (existing == null) return;

    await (_db.delete(_db.taskReminders)..where((t) => t.id.equals(id))).go();
    await writeAudit(
      _db,
      entity: 'TaskReminder',
      entityId: id,
      action: AuditAction.delete,
      before: {'title': existing.title},
    );

    await AppNotifications.instance.cancelTaskNotifications(id);
  }
}
