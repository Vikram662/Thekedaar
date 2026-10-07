import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/db/database.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/common.dart';
import '../../jobs/data/jobs_repository.dart';
import '../data/tasks_repository.dart';

class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, this.taskId});

  final String? taskId;

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _personNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  TaskType _taskType = TaskType.siteVisit;
  String? _selectedJobId;
  DateTime _dueDate = DateTime.now();
  TimeOfDay _dueTime = const TimeOfDay(hour: 10, minute: 0);
  bool _isAlertActive = true;
  int? _intervalMinutes;
  bool _saving = false;
  bool _initialized = false;

  final List<int?> _intervalOptions = [null, 15, 30, 60, 120, 1440];

  String _intervalLabel(int? mins) {
    if (mins == null) return tr('At task time');
    if (mins < 60) return tr('{mins} min repeat', {'mins': mins});
    if (mins == 60) return tr('Every 1 hour');
    if (mins == 120) return tr('Every 2 hours');
    if (mins == 1440) return tr('Daily');
    return tr('{mins} min repeat', {'mins': mins});
  }

  @override
  void dispose() {
    _titleController.dispose();
    _personNameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _loadExisting(TaskReminder t) {
    _titleController.text = t.title;
    _taskType = t.taskType;
    _selectedJobId = t.jobId;
    _personNameController.text = t.personName ?? '';
    _phoneController.text = t.phone ?? '';
    _notesController.text = t.notes ?? '';
    final dt = DateTime.fromMillisecondsSinceEpoch(t.scheduledAt);
    _dueDate = dt;
    _dueTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
    _isAlertActive = t.isAlertActive;
    _intervalMinutes = t.intervalMinutes;
    _initialized = true;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dueTime,
    );
    if (picked != null) {
      setState(() => _dueTime = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final repo = ref.read(tasksRepositoryProvider);
    final scheduledAt = DateTime(
      _dueDate.year,
      _dueDate.month,
      _dueDate.day,
      _dueTime.hour,
      _dueTime.minute,
    );

    try {
      await repo.saveTask(
        id: widget.taskId,
        title: _titleController.text.trim(),
        taskType: _taskType,
        jobId: _selectedJobId,
        personName: _personNameController.text.trim().isEmpty
            ? null
            : _personNameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        scheduledAt: scheduledAt,
        intervalMinutes: _intervalMinutes,
        isAlertActive: _isAlertActive,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Failed to save task: {e}', {'e': errorText(e)}))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.taskId != null;
    final jobsAsync = ref.watch(jobsProvider);

    if (isEdit && !_initialized) {
      final taskAsync = ref.watch(taskByIdProvider(widget.taskId!));
      return taskAsync.when(
        data: (t) {
          if (t == null) {
            return Scaffold(
              appBar: AppBar(title: Text(tr('Task not found'))),
              body: Center(child: Text(tr('This task does not exist.'))),
            );
          }
          _loadExisting(t);
          return _buildForm(jobsAsync, isEdit);
        },
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: Text(tr('Error'))),
          body: Center(child: Text(tr('Error loading task: {e}', {'e': errorText(e)}))),
        ),
      );
    }

    return _buildForm(jobsAsync, isEdit);
  }

  Widget _buildForm(AsyncValue<List<JobListItem>> jobsAsync, bool isEdit) {
    final jobItems = jobsAsync.valueOrNull ?? [];
    final df = DateFormat('EEE, dd MMM yyyy', uiDateLocale);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? tr('Edit Task / Reminder') : tr('Add Task / Reminder')),
        actions: [
          if (isEdit)
            IconButton(
              tooltip: tr('Delete task'),
              icon: const Icon(Icons.delete_outline, color: AppColors.dangerFill),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(tr('Delete Task?')),
                    content: Text(
                        tr('Are you sure you want to delete this task reminder?')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(tr('Cancel')),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.dangerFill),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(tr('Delete')),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await ref
                      .read(tasksRepositoryProvider)
                      .deleteTask(widget.taskId!);
                  if (mounted) context.pop();
                }
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Task Type selector
            Text(
              tr('Task Category'),
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TaskType.values.map((type) {
                final selected = _taskType == type;
                return ChoiceChip(
                  label: Text(type.label),
                  selected: selected,
                  selectedColor: AppColors.amber100,
                  onSelected: (val) {
                    if (val) setState(() => _taskType = type);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Title
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: tr('Task Title *'),
                hintText: tr('e.g. Inspect plaster work, Call client for cheque'),
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? tr('Enter a title') : null,
            ),
            const SizedBox(height: 16),

            // Linked Site / Job
            DropdownButtonFormField<String?>(
              initialValue: _selectedJobId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr('Linked Site / Job (Optional)'),
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(tr('No site linked')),
                ),
                ...jobItems.map((item) => DropdownMenuItem<String?>(
                      value: item.job.id,
                      child: Text(item.job.title),
                    )),
              ],
              onChanged: (val) => setState(() => _selectedJobId = val),
            ),
            const SizedBox(height: 16),

            // Date & Time pickers
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: tr('Date'),
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      child: Text(
                        df.format(_dueDate),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _pickTime,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: tr('Time'),
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.access_time_outlined),
                      ),
                      child: Text(
                        _dueTime.format(context),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Alert recurrence toggle
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        tr('Push Notification Reminder'),
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        tr('Ring / notify at scheduled time'),
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _isAlertActive,
                      activeThumbColor: AppColors.amber500,
                      onChanged: (v) => setState(() => _isAlertActive = v),
                    ),
                    if (_isAlertActive) ...[
                      const Divider(),
                      Row(
                        children: [
                          const Icon(Icons.alarm, size: 20, color: AppColors.slate600),
                          const SizedBox(width: 8),
                          Text(tr('Repeat:')),
                          const Spacer(),
                          DropdownButton<int?>(
                            value: _intervalMinutes,
                            underline: const SizedBox.shrink(),
                            items: _intervalOptions.map((mins) {
                              return DropdownMenuItem<int?>(
                                value: mins,
                                child: Text(_intervalLabel(mins)),
                              );
                            }).toList(),
                            onChanged: (v) {
                              setState(() => _intervalMinutes = v);
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Contact person details
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _personNameController,
                    decoration: InputDecoration(
                      labelText: tr('Contact Person'),
                      hintText: tr('e.g. Ramesh Bhai'),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: tr('Phone Number'),
                      hintText: '9876543210',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: tr('Notes / Remarks'),
                hintText: tr('Enter any additional details or instructions...'),
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 28),

            // Submit Button
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.amber500,
                foregroundColor: AppColors.slate900,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                _saving ? tr('Saving...') : (isEdit ? tr('Update Task') : tr('Save Task')),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
