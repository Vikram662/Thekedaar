import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// Overridden in `main()` with the opened database.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

/// Closes the live database, lets [write] replace the file at the given
/// path, reopens it, runs [afterOpen], and restarts the app (PRD D6).
typedef DatabaseReplacer = Future<void> Function(
  Future<void> Function(String dbPath) write,
  Future<void> Function(AppDatabase db) afterOpen,
);

final databaseReplacerProvider = Provider<DatabaseReplacer>(
  (ref) => throw UnimplementedError('databaseReplacerProvider must be overridden'),
);

final businessProfileProvider = StreamProvider<BusinessProfile?>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.businessProfiles).watchSingleOrNull();
});
