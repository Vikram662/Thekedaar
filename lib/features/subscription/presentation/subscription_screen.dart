import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../app/theme.dart';
import '../../../core/config.dart';
import '../../../core/db/providers.dart';
import '../subscription_controller.dart';

Future<bool> requirePro(BuildContext context, WidgetRef ref) async {
  final access = ref.read(subscriptionControllerProvider).valueOrNull;
  if (access?.canWrite == true) return true;
  if (!context.mounted) return false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _PaywallSheet(),
  );
  return ref.read(subscriptionControllerProvider).valueOrNull?.canWrite == true;
}

class _PaywallSheet extends StatelessWidget {
  const _PaywallSheet();
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.workspace_premium,
                size: 52, color: AppColors.amber500),
            const SizedBox(height: 12),
            Text('Thekedaar Pro',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Subscribe at ₹99/month to record sites, attendance, expenses and bills. You can explore everything free.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/settings/subscription');
                },
                child: const Text('Subscribe for ₹99/month'),
              ),
            ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Not now')),
          ]),
        ),
      );
}

class ProRouteGate extends ConsumerWidget {
  const ProRouteGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(subscriptionControllerProvider);
    final access = value.valueOrNull;
    if (access?.canWrite == true) return child;
    if (value.isLoading || access?.kind == AccessKind.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Thekedaar Pro required')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.workspace_premium,
                size: 64, color: AppColors.amber500),
            const SizedBox(height: 16),
            Text('Record data with Pro',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Subscribe at ₹99/month to add or change records. All view screens remain free.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.push('/settings/subscription'),
              child: const Text('View subscription'),
            ),
            TextButton(
                onPressed: () => context.pop(), child: const Text('Back')),
          ]),
        ),
      ),
    );
  }
}

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  late final Razorpay _razorpay;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _success)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _failure);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(subscriptionControllerProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _subscribe() async {
    if (!AppConfig.subscriptionConfigured) {
      _say('This build is missing SUBSCRIPTION_API_URL.');
      return;
    }
    setState(() => _opening = true);
    try {
      final profile = await ref.read(businessProfileProvider.future);
      if (profile == null) throw Exception('Complete business setup first.');
      final controller = ref.read(subscriptionControllerProvider.notifier);
      try {
        await controller.refresh();
        final session = await controller.createCheckout();
        _razorpay.open({
          'key': session.keyId,
          'subscription_id': session.subscriptionId,
          'name': 'Thekedaar Pro',
          'description': '₹99 monthly subscription',
          'prefill': {'name': profile.name, 'contact': profile.phone ?? ''},
          'theme': {'color': '#B45309'},
          'retry': {'enabled': true, 'max_count': 3},
        });
      } catch (error) {
        await controller.registerProfile(profile);
        final session = await controller.createCheckout();
        _razorpay.open({
          'key': session.keyId,
          'subscription_id': session.subscriptionId,
          'name': 'Thekedaar Pro',
          'description': '₹99 monthly subscription',
          'prefill': {'name': profile.name, 'contact': profile.phone ?? ''},
          'theme': {'color': '#B45309'},
        });
      }
    } catch (error) {
      _say('$error');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _success(PaymentSuccessResponse response) async {
    _say('Payment received. Verifying subscription…');
    await Future<void>.delayed(const Duration(seconds: 2));
    await ref.read(subscriptionControllerProvider.notifier).refresh();
  }

  void _failure(PaymentFailureResponse response) =>
      _say(response.message ?? 'Payment was not completed.');

  Future<void> _restore() async {
    final field = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore subscription'),
        content: TextField(
          controller: field,
          decoration: const InputDecoration(
              labelText: 'Subscription ID', hintText: 'sub_xxxxxxxxxx'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, field.text),
              child: const Text('Verify')),
        ],
      ),
    );
    field.dispose();
    if (id == null || id.trim().isEmpty) return;
    try {
      await ref.read(subscriptionControllerProvider.notifier).link(id);
      _say('Subscription restored.');
    } catch (error) {
      _say('$error');
    }
  }

  Future<void> _cancel() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel subscription?'),
        content: const Text(
            'Your recurring mandate will be cancelled. Eligible payments from the first 7 days are sent for refund.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Pro')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel subscription')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final result =
          await ref.read(subscriptionControllerProvider.notifier).cancel();
      _say(result['refundStatus'] == null
          ? 'Subscription cancelled.'
          : 'Subscription cancelled. Refund: ${result['refundStatus']}');
    } catch (error) {
      _say('$error');
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(subscriptionControllerProvider);
    final access = value.valueOrNull;
    final active = access?.canWrite == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Thekedaar Pro')),
      body: RefreshIndicator(
        onRefresh: ref.read(subscriptionControllerProvider.notifier).refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(active ? Icons.verified : Icons.workspace_premium,
                size: 72,
                color: active ? AppColors.successText : AppColors.amber500),
            const SizedBox(height: 12),
            Text(active ? 'Pro is active' : 'Explore free',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              active
                  ? 'You can record all business data.${access?.kind == AccessKind.offlineGrace ? '\n${access?.message}' : ''}'
                  : 'Browse the complete app free. Subscribe when you want to add or change records.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (value.isLoading)
              const Center(child: CircularProgressIndicator()),
            if (!active)
              FilledButton.icon(
                onPressed: _opening ? null : _subscribe,
                icon: const Icon(Icons.payment),
                label: const Text('Subscribe · ₹99/month'),
              ),
            if (active)
              OutlinedButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel subscription'),
              ),
            TextButton.icon(
              onPressed: _restore,
              icon: const Icon(Icons.restore),
              label: const Text('Restore with Subscription ID'),
            ),
            const Divider(height: 36),
            const ListTile(
              leading: Icon(Icons.visibility_outlined),
              title: Text('Free mode'),
              subtitle: Text('View menus, screens and existing/demo records.'),
            ),
            const ListTile(
              leading: Icon(Icons.edit_note),
              title: Text('Pro mode'),
              subtitle: Text(
                  'Add sites, attendance, bills, expenses and daily records.'),
            ),
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline grace'),
              subtitle:
                  Text('Active members can work offline for up to 7 days.'),
            ),
            if (access?.status != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Status: ${access!.status}',
                    textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }
}
