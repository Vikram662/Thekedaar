import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../utils/ids.dart';
import 'database.dart';
import 'enums.dart';

/// Thrown when an entry falls inside a settled (locked) period (PRD AT-06).
class PeriodLockedException implements Exception {
  const PeriodLockedException([this.message = 'This period is settled and locked']);

  final String message;

  @override
  String toString() => message;
}

/// Records who-changed-what (PRD I-T3, I-S4, DB-09). Single admin, so "who"
/// is always the admin; before/after hold the row as JSON.
Future<void> writeAudit(
  AppDatabase db, {
  required String entity,
  required String entityId,
  required AuditAction action,
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
}) =>
    db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
          id: newId(),
          entity: entity,
          entityId: entityId,
          action: action,
          beforeJson: before == null ? const Value.absent() : Value(_encode(before)),
          afterJson: after == null ? const Value.absent() : Value(_encode(after)),
        ));

String _encode(Map<String, dynamic> json) => jsonEncode(
      json,
      toEncodable: (value) => value is Enum ? value.name : value.toString(),
    );
