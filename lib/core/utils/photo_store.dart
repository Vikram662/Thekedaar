import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Photos live in `<app documents>/photos/`. The database stores only the
/// file name, so paths stay valid after a restore on another phone.
/// No Flutter UI imports here: the background backup job uses this too.
Future<Directory> photoDirectory() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'photos'));
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}

Future<File> photoFile(String name) async =>
    File(p.join((await photoDirectory()).path, name));

/// Names of all stored photos.
Future<List<String>> listPhotoNames() async {
  final dir = await photoDirectory();
  return [
    for (final f in dir.listSync().whereType<File>())
      if (f.path.endsWith('.jpg')) p.basename(f.path),
  ];
}
