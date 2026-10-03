import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/db/providers.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/widgets/common.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../../onboarding/presentation/onboarding_screen.dart';

/// PRD TR-05: add a trade later. Only that trade's defaults are added;
/// existing data is never changed or removed.
class TradesScreen extends ConsumerStatefulWidget {
  const TradesScreen({super.key});

  @override
  ConsumerState<TradesScreen> createState() => _TradesScreenState();
}

class _TradesScreenState extends ConsumerState<TradesScreen> {
  Set<Trade>? _selected;
  bool _saving = false;

  Future<void> _save() async {
    final selected = _selected!;
    if (selected.isEmpty) {
      showMessage(context, 'Choose at least one trade');
      return;
    }
    setState(() => _saving = true);
    await ref.read(seedServiceProvider).applyTrades(selected);
    await ref
        .read(settingsRepositoryProvider)
        .saveTrades(Trade.encode(selected));
    if (!mounted) return;
    showMessage(context, 'Trades saved');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    if (profile == null) {
      return const SkeletonPage();
    }
    final selected = _selected ??= Trade.decode(profile.trades);

    return Scaffold(
      appBar: AppBar(title: const Text('Trades')),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.gutter),
        children: [
          const Text(
            'Adding a trade adds its roles, items and templates. '
            'Removing one keeps all your data.',
            style: TextStyle(color: AppColors.slate600),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSizes.gap,
            crossAxisSpacing: AppSizes.gap,
            childAspectRatio: 2.4,
            children: [
              for (final trade in Trade.values)
                TradeTile(
                  trade: trade,
                  selected: selected.contains(trade),
                  onTap: () => setState(() {
                    if (!selected.remove(trade)) selected.add(trade);
                  }),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar:
          BottomActionBar(label: 'Save', busy: _saving, onPressed: _save),
    );
  }
}
