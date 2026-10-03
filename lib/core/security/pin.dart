import 'dart:convert';

import 'package:cryptography/cryptography.dart';

const pinLength = 4;
const freeAttempts = 5;

/// PRD AU-02: reject PINs like 0000, 1111, 1234, 9876.
bool isWeakPin(String pin) {
  if (pin.length != pinLength || int.tryParse(pin) == null) return true;
  final digits = pin.codeUnits.map((c) => c - 48).toList();
  final allSame = digits.every((d) => d == digits.first);
  var ascending = true;
  var descending = true;
  for (var i = 1; i < digits.length; i++) {
    if (digits[i] != digits[i - 1] + 1) ascending = false;
    if (digits[i] != digits[i - 1] - 1) descending = false;
  }
  return allSame || ascending || descending;
}

/// PRD AU-03: 5 free attempts, then 30 s, doubling with each further miss
/// (capped at one hour).
Duration? lockoutAfterFailures(int failures) {
  if (failures < freeAttempts) return null;
  final seconds = 30 * (1 << (failures - freeAttempts).clamp(0, 7));
  return Duration(seconds: seconds.clamp(30, 3600));
}

final _pinKdf = Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: 60000,
  bits: 256,
);

/// PBKDF2-SHA256 hash of the PIN, base64. The hash lives in Android Keystore
/// backed secure storage, never in the database (PRD Part F).
Future<String> hashPin(String pin, List<int> salt) async {
  final key = await _pinKdf.deriveKeyFromPassword(password: pin, nonce: salt);
  return base64Encode(await key.extractBytes());
}

/// Constant-time comparison of two base64 hashes.
bool hashesEqual(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
