import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/photos.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pickers.dart';
import '../data/expenses_repository.dart';

/// PRD EX-01: business expenses by month, with category totals.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  Future<void> _delete(ExpenseItem item) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this expense?',
      message: '${item.categoryName} · ${formatPaise(item.expense.amountPaise)}',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) {
      await ref.read(expensesRepositoryProvider).deleteExpense(item.expense.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(
      monthExpensesProvider((year: _month.year, month: _month.month)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            tooltip: 'Suppliers',
            icon: const Icon(Icons.store),
            onPressed: () => context.push(Routes.suppliers),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.addExpense),
        icon: const Icon(Icons.add),
        label: const Text('Expense'),
      ),
      body: Column(
        children: [
          Material(
            color: AppColors.surface,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: Text(
                    monthFormat.format(_month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _isCurrentMonth ? null : () => _shift(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.when(
              loading: () => const ListSkeleton(),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.receipt,
                    title: 'No expenses this month',
                    message: 'Petrol, material, food, tools and rent go here.',
                    actionLabel: 'Add expense',
                    onAction: () => context.push(Routes.addExpense),
                  );
                }
                final total =
                    list.fold(0, (sum, i) => sum + i.expense.amountPaise);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    Panel(
                      child: Column(
                        children: [
                          AmountRow(label: 'Total', paise: total, bold: true),
                          const Divider(),
                          for (final t in totalsByCategory(list))
                            AmountRow(label: t.category, paise: t.totalPaise),
                        ],
                      ),
                    ),
                    const SectionTitle('Entries'),
                    Panel(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final item in list)
                            ListTile(
                              leading: item.expense.photoPath == null
                                  ? null
                                  : InkWell(
                                      onTap: () => showPhoto(
                                          context, item.expense.photoPath!),
                                      child: PhotoThumb(
                                          name: item.expense.photoPath!,
                                          size: 44),
                                    ),
                              title: Text(item.categoryName),
                              subtitle: Text([
                                dayFormat.format(parseIsoDate(item.expense.date)),
                                paymentModeLabel(item.expense.mode),
                                if (item.jobTitle != null) item.jobTitle!,
                                if (item.expense.remarks != null &&
                                    item.expense.remarks!.isNotEmpty)
                                  item.expense.remarks!,
                              ].join(' · ')),
                              trailing: Text(
                                formatPaise(item.expense.amountPaise),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onLongPress: () => _delete(item),
                            ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Long-press an entry to delete it.',
                        style: TextStyle(color: AppColors.slate600),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
