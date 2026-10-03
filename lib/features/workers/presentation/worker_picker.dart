import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/pickers.dart';
import '../data/workers_repository.dart';

/// Field showing the chosen worker; tap to pick from active workers.
class WorkerPickerField extends ConsumerWidget {
  const WorkerPickerField({
    super.key,
    required this.workerId,
    required this.onChanged,
  });

  final String? workerId;
  final ValueChanged<WorkerListItem> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workers = ref.watch(activeWorkersProvider).valueOrNull ?? const [];
    final selected =
        workers.where((w) => w.worker.id == workerId).firstOrNull;
    return PickerField(
      label: 'Worker',
      icon: Icons.person,
      value: selected?.worker.name,
      onTap: () async {
        final picked = await showPickerSheet<WorkerListItem>(
          context,
          title: 'Choose worker',
          options: workers,
          label: (w) => w.worker.name,
          subtitle: (w) => [
            if (w.roleName != null) w.roleName!,
            wageLabel(w.wage),
          ].join(' · '),
          selected: selected,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}
