import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../security/random_bytes.dart';

/// Thrown when a backup password or recovery key does not open the keyring.
class WrongSecretException implements Exception {
  const WrongSecretException();

  @override
  String toString() => 'Wrong password or recovery key';
}

/// Argon2id cost. Stored in the keyring so it can be raised later without
/// breaking old backups.
class KdfParams {
  const KdfParams({
    this.memoryKib = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });

  factory KdfParams.fromJson(Map<String, dynamic> json) => KdfParams(
        memoryKib: json['m'] as int,
        iterations: json['t'] as int,
        parallelism: json['p'] as int,
      );

  /// Fast settings for unit tests only.
  static const testing = KdfParams(memoryKib: 64, iterations: 1);

  final int memoryKib;
  final int iterations;
  final int parallelism;

  Map<String, dynamic> toJson() =>
      {'m': memoryKib, 't': iterations, 'p': parallelism};
}

const _recoveryAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// 24 random characters shown as `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX` (PRD D1 step 4).
String generateRecoveryKey() {
  final bytes = randomBytes(24);
  final chars = [for (final b in bytes) _recoveryAlphabet[b % 32]].join();
  return [
    for (var i = 0; i < chars.length; i += 4) chars.substring(i, i + 4),
  ].join('-');
}

String normalizeRecoveryKey(String input) =>
    input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

final _aes = AesGcm.with256bits();

/// The backup master key (random, 32 bytes) wrapped twice: once with a key
/// derived from the Backup Password (Argon2id), once with the Recovery Key.
/// Changing the password re-wraps the same master key, so every old backup
/// still opens (PRD D4).
class Keyring {
  const Keyring({
    required this.kdf,
    required this.passwordSalt,
    required this.passwordWrapped,
    required this.recoverySalt,
    required this.recoveryWrapped,
  });

  factory Keyring.fromJson(Map<String, dynamic> json) => Keyring(
        kdf: KdfParams.fromJson((json['kdf'] as Map).cast<String, dynamic>()),
        passwordSalt: base64Decode(json['ps'] as String),
        passwordWrapped: base64Decode(json['pw'] as String),
        recoverySalt: base64Decode(json['rs'] as String),
        recoveryWrapped: base64Decode(json['rw'] as String),
      );

  factory Keyring.fromJsonString(String json) =>
      Keyring.fromJson(jsonDecode(json) as Map<String, dynamic>);

  final KdfParams kdf;
  final List<int> passwordSalt;
  final List<int> passwordWrapped;
  final List<int> recoverySalt;
  final List<int> recoveryWrapped;

  static Future<({Keyring keyring, List<int> masterKey})> create({
    required String password,
    required String recoveryKey,
    KdfParams kdf = const KdfParams(),
  }) async {
    final masterKey = randomBytes(32);
    final keyring = await wrap(
      masterKey: masterKey,
      password: password,
      recoveryKey: recoveryKey,
      kdf: kdf,
    );
    return (keyring: keyring, masterKey: masterKey);
  }

  static Future<Keyring> wrap({
    required List<int> masterKey,
    required String password,
    required String recoveryKey,
    KdfParams kdf = const KdfParams(),
  }) async {
    final passwordSalt = randomBytes(16);
    final recoverySalt = randomBytes(16);
    return Keyring(
      kdf: kdf,
      passwordSalt: passwordSalt,
      passwordWrapped: await _wrap(
        masterKey,
        await _passwordKey(password, passwordSalt, kdf),
      ),
      recoverySalt: recoverySalt,
      recoveryWrapped: await _wrap(
        masterKey,
        await _recoveryKek(recoveryKey, recoverySalt),
      ),
    );
  }

  /// New password, same master key and recovery wrapping.
  Future<Keyring> withNewPassword(List<int> masterKey, String password) async {
    final salt = randomBytes(16);
    return Keyring(
      kdf: kdf,
      passwordSalt: salt,
      passwordWrapped:
          await _wrap(masterKey, await _passwordKey(password, salt, kdf)),
      recoverySalt: recoverySalt,
      recoveryWrapped: recoveryWrapped,
    );
  }

  Future<List<int>> unlockWithPassword(String password) async =>
      _unwrap(passwordWrapped, await _passwordKey(password, passwordSalt, kdf));

  Future<List<int>> unlockWithRecoveryKey(String recoveryKey) async =>
      _unwrap(recoveryWrapped, await _recoveryKek(recoveryKey, recoverySalt));

  Map<String, dynamic> toJson() => {
        'v': 1,
        'kdf': kdf.toJson(),
        'ps': base64Encode(passwordSalt),
        'pw': base64Encode(passwordWrapped),
        'rs': base64Encode(recoverySalt),
        'rw': base64Encode(recoveryWrapped),
      };

  String toJsonString() => jsonEncode(toJson());

  static Future<SecretKey> _passwordKey(
    String password,
    List<int> salt,
    KdfParams kdf,
  ) {
    final argon = Argon2id(
      parallelism: kdf.parallelism,
      memory: kdf.memoryKib,
      iterations: kdf.iterations,
      hashLength: 32,
    );
    return argon.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  static Future<SecretKey> _recoveryKek(String recoveryKey, List<int> salt) {
    // The recovery key already has ~120 bits of entropy, so HKDF is enough.
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(normalizeRecoveryKey(recoveryKey))),
      nonce: salt,
    );
  }

  static Future<List<int>> _wrap(List<int> masterKey, SecretKey kek) async {
    final box = await _aes.encrypt(masterKey, secretKey: kek);
    return box.concatenation();
  }

  static Future<List<int>> _unwrap(List<int> wrapped, SecretKey kek) async {
    try {
      final box = SecretBox.fromConcatenation(
        wrapped,
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      return await _aes.decrypt(box, secretKey: kek);
    } on SecretBoxAuthenticationError {
      throw const WrongSecretException();
    }
  }
}
