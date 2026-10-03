import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/backup/backup_scheduler.dart';
import 'core/db/database.dart';
import 'core/db/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await BackupScheduler().initialize();
  } catch (_) {
    // Background backup unavailable; foreground triggers still run.
  }
  final db = AppDatabase();
  final needsOnboarding =
      await db.select(db.businessProfiles).getSingleOrNull() == null;
  runApp(AppRoot(database: db, needsOnboarding: needsOnboarding));
}

/// Owns the open database. A restore closes it, swaps the file and rebuilds
/// the whole app on the new data (PRD D6).
class AppRoot extends StatefulWidget {
  const AppRoot({
    super.key,
    required this.database,
    required this.needsOnboarding,
  });

  final AppDatabase database;
  final bool needsOnboarding;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late AppDatabase _db = widget.database;
  late bool _needsOnboarding = widget.needsOnboarding;
  int _generation = 0;

  Future<void> _replaceDatabase(
    Future<void> Function(String dbPath) write,
    Future<void> Function(AppDatabase db) afterOpen,
  ) async {
    await _db.close();
    try {
      await write(await databaseFilePath());
    } finally {
      _db = AppDatabase();
    }
    await afterOpen(_db);
    final needsOnboarding =
        await _db.select(_db.businessProfiles).getSingleOrNull() == null;
    setState(() {
      _needsOnboarding = needsOnboarding;
      _generation++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: ValueKey(_generation),
      overrides: [
        databaseProvider.overrideWithValue(_db),
        databaseReplacerProvider.overrideWithValue(_replaceDatabase),
      ],
      child: ThekedaarApp(needsOnboarding: _needsOnboarding),
    );
  }
}
