import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// New UUID v4 primary key (PRD Part F: ids are UUID text, sync-ready).
String newId() => _uuid.v4();

final _nonAlphanumeric = RegExp(r'[^a-z0-9]+');
final _edgeUnderscores = RegExp(r'^_+|_+$');

/// `"CPVC pipe 1/2 inch"` → `"cpvc_pipe_1_2_inch"`. Used for seed keys.
String slug(String value) => value
    .toLowerCase()
    .replaceAll(_nonAlphanumeric, '_')
    .replaceAll(_edgeUnderscores, '');
