import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/db/enums.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/language_picker.dart';
import '../../subscription/subscription_controller.dart';
import '../data/onboarding_repository.dart';
import 'trade_icons.dart';

/// First launch: business name, phone and trades (PRD C0, TR-01).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _trades = <Trade>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_refresh);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  bool get _canContinue =>
      !_saving && _name.text.trim().isNotEmpty && _trades.isNotEmpty;

  void _toggle(Trade trade) {
    setState(() {
      if (!_trades.remove(trade)) _trades.add(trade);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(onboardingRepositoryProvider).complete(
            businessName: _name.text.trim(),
            phone: normalizeIndianPhone(_phone.text),
            trades: _trades,
          );
      unawaited(ref.read(subscriptionControllerProvider.notifier).refresh());
      if (!mounted) return;
      context.go(Routes.dashboard);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Could not save. Please try again. ({error})', {'error': errorText(error)}))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Set up your business'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.gutter),
          children: [
            const Align(
              alignment: Alignment.centerRight,
              child: LanguageToggle(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Business name')),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? tr('Enter business name')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: tr('Mobile number (optional)'),
                prefixText: '+91 ',
              ),
              validator: (value) => (value == null ||
                      value.trim().isEmpty ||
                      normalizeIndianPhone(value) != null)
                  ? null
                  : tr('Enter a valid 10-digit mobile number'),
            ),
            const SizedBox(height: 24),
            Text(tr('What work do you do?'), style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              tr('Choose one or more. You can change this later.'),
              style: textTheme.bodyMedium?.copyWith(color: AppColors.slate600),
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
                    selected: _trades.contains(trade),
                    onTap: () => _toggle(trade),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restore),
              title: Text(tr('Already using Thekedaar?')),
              subtitle: Text(
                  tr('Restore your data from Google Drive or a backup file')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.restore),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.gutter),
          child: FilledButton(
            onPressed: _canContinue ? _submit : null,
            child: _saving
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : Text(tr('Continue')),
          ),
        ),
      ),
    );
  }
}

/// Selectable trade tile, also used in Settings → Trades.
class TradeTile extends StatelessWidget {
  const TradeTile({
    super.key,
    required this.trade,
    required this.selected,
    required this.onTap,
  });

  final Trade trade;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSizes.radius),
      side: BorderSide(
        color: selected ? AppColors.amber500 : AppColors.border,
        width: selected ? 2 : 1,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.amber100 : AppColors.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(tradeIcon(trade), color: AppColors.slate900),
                const SizedBox(width: AppSizes.gap),
                Expanded(
                  child: Text(
                    trade.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: AppColors.successText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
