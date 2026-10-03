import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/security/pin.dart';
import '../../core/security/random_bytes.dart';
import '../../core/security/secure_store.dart';

enum LockStatus { checking, needsSetup, locked, unlocked }

sealed class PinCheck {
  const PinCheck();
}

class PinOk extends PinCheck {
  const PinOk();
}

class PinWrong extends PinCheck {
  const PinWrong(this.attemptsLeft);

  final int attemptsLeft;
}

class PinLockedOut extends PinCheck {
  const PinLockedOut(this.until);

  final DateTime until;
}

final appLockProvider = ChangeNotifierProvider<AppLockController>(
  (ref) => AppLockController(ref.watch(secureStoreProvider)),
);

/// App lock state (PRD C1): biometric or 4-digit PIN on open, relock after
/// 2 minutes in the background, growing wait after wrong PINs.
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController(this._secure, [LocalAuthentication? localAuth])
      : _localAuth = localAuth ?? LocalAuthentication() {
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  final SecureStore _secure;
  final LocalAuthentication _localAuth;

  static const relockAfter = Duration(minutes: 2);

  LockStatus status = LockStatus.checking;
  bool biometricEnabled = false;
  bool biometricAvailable = false;
  int failures = 0;
  DateTime? lockedUntil;
  DateTime? _pausedAt;

  /// True while a system sheet we opened (biometric, share, file picker) is
  /// in front, so coming back does not count as leaving the app.
  bool suspendRelock = false;

  Future<void> _load() async {
    final hash = await _secure.read(SecureStore.pinHash);
    biometricEnabled = await _secure.read(SecureStore.biometricEnabled) == 'true';
    failures = int.tryParse(await _secure.read(SecureStore.pinFailures) ?? '') ?? 0;
    final until = int.tryParse(await _secure.read(SecureStore.pinLockedUntil) ?? '');
    lockedUntil = until == null ? null : DateTime.fromMillisecondsSinceEpoch(until);
    try {
      biometricAvailable = await _localAuth.isDeviceSupported() &&
          await _localAuth.canCheckBiometrics;
    } catch (_) {
      biometricAvailable = false;
    }
    status = hash == null ? LockStatus.needsSetup : LockStatus.locked;
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    final salt = randomBytes(16);
    await _secure.write(SecureStore.pinSalt, base64Encode(salt));
    await _secure.write(SecureStore.pinHash, await hashPin(pin, salt));
    await _resetFailures();
    status = LockStatus.unlocked;
    notifyListeners();
  }

  Future<PinCheck> checkPin(String pin, {bool unlock = true}) async {
    final until = lockedUntil;
    if (until != null && until.isAfter(DateTime.now())) return PinLockedOut(until);

    final hash = await _secure.read(SecureStore.pinHash);
    final salt = await _secure.read(SecureStore.pinSalt);
    if (hash == null || salt == null) return const PinWrong(0);
    final candidate = await hashPin(pin, base64Decode(salt));
    if (hashesEqual(candidate, hash)) {
      await _resetFailures();
      if (unlock) {
        status = LockStatus.unlocked;
        notifyListeners();
      }
      return const PinOk();
    }

    failures++;
    await _secure.write(SecureStore.pinFailures, '$failures');
    final wait = lockoutAfterFailures(failures);
    if (wait != null) {
      lockedUntil = DateTime.now().add(wait);
      await _secure.write(
        SecureStore.pinLockedUntil,
        '${lockedUntil!.millisecondsSinceEpoch}',
      );
      notifyListeners();
      return PinLockedOut(lockedUntil!);
    }
    notifyListeners();
    return PinWrong(freeAttempts - failures);
  }

  /// Fingerprint / face (PRD AU-01). Returns true on success.
  Future<bool> authenticateBiometric({
    String reason = 'Unlock Thekedaar',
    bool unlock = true,
  }) async {
    if (!biometricEnabled || !biometricAvailable) return false;
    suspendRelock = true;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        await _resetFailures();
        if (unlock) {
          status = LockStatus.unlocked;
          notifyListeners();
        }
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      suspendRelock = false;
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    biometricEnabled = enabled;
    await _secure.write(SecureStore.biometricEnabled, '$enabled');
    notifyListeners();
  }

  /// PIN forgotten and Google account verified (PRD AU-05): set a new PIN.
  void startPinReset() {
    status = LockStatus.needsSetup;
    notifyListeners();
  }

  void lockNow() {
    if (status == LockStatus.unlocked) {
      status = LockStatus.locked;
      notifyListeners();
    }
  }

  Future<void> _resetFailures() async {
    failures = 0;
    lockedUntil = null;
    await _secure.delete(SecureStore.pinFailures);
    await _secure.delete(SecureStore.pinLockedUntil);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !suspendRelock) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt != null &&
          DateTime.now().difference(pausedAt) > relockAfter) {
        lockNow();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
