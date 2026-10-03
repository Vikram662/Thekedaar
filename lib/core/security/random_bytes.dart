import 'dart:math';

final _random = Random.secure();

List<int> randomBytes(int length) =>
    List<int>.generate(length, (_) => _random.nextInt(256));
