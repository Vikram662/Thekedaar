import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/security/pin.dart';

void main() {
  test('weak PINs are rejected (AU-02)', () {
    for (final pin in ['0000', '1111', '1234', '6789', '9876', '3210']) {
      expect(isWeakPin(pin), isTrue, reason: pin);
    }
    for (final pin in ['1357', '2580', '4721']) {
      expect(isWeakPin(pin), isFalse, reason: pin);
    }
    expect(isWeakPin('12a4'), isTrue);
    expect(isWeakPin('123'), isTrue);
  });

  test('wait grows after 5 wrong PINs (AU-03)', () {
    expect(lockoutAfterFailures(4), isNull);
    expect(lockoutAfterFailures(5), const Duration(seconds: 30));
    expect(lockoutAfterFailures(6), const Duration(seconds: 60));
    expect(lockoutAfterFailures(7), const Duration(seconds: 120));
    expect(lockoutAfterFailures(40), const Duration(hours: 1));
  });

  test('PIN hash is stable per salt and differs across salts', () async {
    final salt = List<int>.generate(16, (i) => i);
    final a = await hashPin('4721', salt);
    expect(await hashPin('4721', salt), a);
    expect(hashesEqual(a, await hashPin('4721', salt)), isTrue);
    expect(a == await hashPin('4722', salt), isFalse);
    expect(a == await hashPin('4721', List<int>.filled(16, 9)), isFalse);
  });
}
