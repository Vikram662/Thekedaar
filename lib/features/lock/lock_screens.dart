import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/backup/google_drive_auth.dart';
import '../../core/db/meta_store.dart';
import '../../core/db/providers.dart';
import '../../core/security/pin.dart';
import 'app_lock_controller.dart';
import 'pin_pad.dart';

/// Shown over the whole app while locked or before a PIN exists. Lives in
/// `MaterialApp.builder`, above the router.
class LockGate extends ConsumerWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider);
    const splash = Scaffold(body: Center(child: CircularProgressIndicator()));
    if (profile.isLoading && !profile.hasValue) return splash;
    // No business yet → onboarding is showing; nothing to protect.
    if (profile.valueOrNull == null) return child;

    final lock = ref.watch(appLockProvider);
    return switch (lock.status) {
      LockStatus.unlocked => child,
      LockStatus.checking => splash,
      LockStatus.needsSetup => _OwnNavigator(
          key: const ValueKey('pin-setup'),
          child: const PinSetupScreen(),
        ),
      LockStatus.locked => _OwnNavigator(
          key: const ValueKey('locked'),
          child: const LockScreen(),
        ),
    };
  }
}

/// The gate sits above the app's router, so lock screens get their own
/// Navigator (for dialogs and overlays).
class _OwnNavigator extends StatelessWidget {
  const _OwnNavigator({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child),
      );
}

class LockScreen extends ConsumerStatefulWidget {
  /// With [confirmOnly] the screen verifies identity (PRD AU-06) and pops
  /// `true`, without changing the lock state.
  const LockScreen({super.key, this.confirmOnly = false, this.reason});

  final bool confirmOnly;
  final String? reason;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(appLockProvider).lockedUntil != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _done() {
    if (widget.confirmOnly) Navigator.of(context).pop(true);
  }

  Future<void> _tryBiometric() async {
    final lock = ref.read(appLockProvider);
    if (!lock.biometricEnabled) return;
    final ok = await lock.authenticateBiometric(
      reason: widget.reason ?? 'Unlock Thekedaar',
      unlock: !widget.confirmOnly,
    );
    if (ok && mounted) _done();
  }

  Future<void> _onPin(String pin) async {
    final result = await ref
        .read(appLockProvider)
        .checkPin(pin, unlock: !widget.confirmOnly);
    if (!mounted) return;
    switch (result) {
      case PinOk():
        setState(() => _error = null);
        _done();
      case PinWrong(:final attemptsLeft):
        setState(() => _error = attemptsLeft > 0
            ? 'Wrong PIN. $attemptsLeft tries left.'
            : 'Wrong PIN.');
      case PinLockedOut():
        setState(() => _error = 'Too many wrong tries.');
    }
  }

  Future<void> _forgotPin() async {
    final email = await MetaStore(ref.read(databaseProvider))
        .get(MetaKeys.driveEmail);
    if (!mounted) return;
    if (email == null) {
      setState(() => _error =
          'Google Drive backup is not connected, so the PIN cannot be reset '
          'here. Reinstall the app and restore from a backup file.');
      return;
    }
    try {
      final verified = await GoogleDriveAuth().verifyAccount();
      if (!mounted) return;
      if (verified.toLowerCase() == email.toLowerCase()) {
        ref.read(appLockProvider).startPinReset();
        if (widget.confirmOnly) Navigator.of(context).pop(false);
      } else {
        setState(() => _error = 'Please choose the account $email');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Google sign-in failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final until = lock.lockedUntil;
    final waiting = until != null && until.isAfter(DateTime.now());
    final seconds = waiting ? until.difference(DateTime.now()).inSeconds + 1 : 0;

    return PopScope(
      canPop: widget.confirmOnly,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: widget.confirmOnly
            ? AppBar(title: const Text('Confirm it is you'))
            : null,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.gutter),
              child: Column(
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    widget.reason ?? 'Enter your PIN',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: Text(
                      waiting ? 'Try again in $seconds s' : (_error ?? ''),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.dangerText),
                    ),
                  ),
                  PinPad(
                    enabled: !waiting,
                    onCompleted: _onPin,
                    onBiometric: lock.biometricEnabled && lock.biometricAvailable
                        ? _tryBiometric
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _forgotPin,
                    child: const Text('Forgot PIN?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Create a new 4-digit PIN: enter twice, weak PINs rejected (PRD AU-02).
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key, this.popOnDone = false});

  /// True when opened from Settings → Change PIN.
  final bool popOnDone;

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String? _first;
  String? _error;

  Future<void> _onPin(String pin) async {
    if (_first == null) {
      if (isWeakPin(pin)) {
        setState(() => _error = 'This PIN is too easy. Choose another.');
        return;
      }
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (pin != _first) {
      setState(() {
        _first = null;
        _error = 'PINs did not match. Start again.';
      });
      return;
    }
    final lock = ref.read(appLockProvider);
    await lock.setPin(pin);
    if (lock.biometricAvailable && !lock.biometricEnabled && mounted) {
      final enable = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Use fingerprint?'),
          content: const Text('Unlock the app with fingerprint or face.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Use fingerprint'),
            ),
          ],
        ),
      );
      if (enable ?? false) await lock.setBiometricEnabled(true);
    }
    if (widget.popOnDone && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('App lock PIN')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.gutter),
            child: Column(
              children: [
                Text(
                  _first == null ? 'Create a 4-digit PIN' : 'Enter the PIN again',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: Text(
                    _error ?? 'You will use it to open the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _error == null
                          ? AppColors.slate600
                          : AppColors.dangerText,
                    ),
                  ),
                ),
                PinPad(onCompleted: _onPin),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for biometric/PIN before sensitive actions (PRD AU-06).
Future<bool> confirmIdentity(BuildContext context, {String? reason}) async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LockScreen(confirmOnly: true, reason: reason),
    ),
  );
  return ok ?? false;
}
