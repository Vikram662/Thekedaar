import 'dart:convert';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class RemoteFile {
  const RemoteFile({
    required this.id,
    required this.name,
    required this.size,
    required this.createdTime,
    this.appProperties = const {},
  });

  final String id;
  final String name;
  final int size;
  final DateTime createdTime;
  final Map<String, String> appProperties;
}

class DriveQuota {
  const DriveQuota({this.limitBytes, required this.usageBytes});

  /// Null for unlimited accounts.
  final int? limitBytes;
  final int usageBytes;

  int? get freeBytes => limitBytes == null ? null : limitBytes! - usageBytes;

  double? get usedFraction =>
      limitBytes == null || limitBytes == 0 ? null : usageBytes / limitBytes!;
}

/// Drive folder layout (PRD D2):
///   Thekedaar Backups/
///     device.json, keys.json
///     db/`yyyy-MM-dd_HHmmss_vN`.tkbak
class DriveStore {
  DriveStore(http.Client client) : _api = drive.DriveApi(client);

  static const rootFolderName = 'Thekedaar Backups';
  static const dbFolderName = 'db';
  static const deviceFileName = 'device.json';
  static const keysFileName = 'keys.json';
  static const _folderMime = 'application/vnd.google-apps.folder';
  static const _fields =
      'files(id,name,size,createdTime,appProperties),nextPageToken';

  final drive.DriveApi _api;

  String _escape(String value) => value.replaceAll("'", r"\'");

  Future<String?> findFolder(String name, {String? parentId}) async {
    final parent = parentId == null ? '' : " and '$parentId' in parents";
    final result = await _api.files.list(
      q: "name = '${_escape(name)}' and mimeType = '$_folderMime' "
          'and trashed = false$parent',
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final files = result.files ?? const [];
    return files.isEmpty ? null : files.first.id;
  }

  Future<String> ensureFolder(String name, {String? parentId}) async {
    final existing = await findFolder(name, parentId: parentId);
    if (existing != null) return existing;
    final folder = drive.File()
      ..name = name
      ..mimeType = _folderMime
      ..parents = parentId == null ? null : [parentId];
    final created = await _api.files.create(folder, $fields: 'id');
    return created.id!;
  }

  Future<List<RemoteFile>> listFiles(String folderId) async {
    final files = <RemoteFile>[];
    String? pageToken;
    do {
      final result = await _api.files.list(
        q: "'$folderId' in parents and trashed = false",
        spaces: 'drive',
        orderBy: 'createdTime desc',
        pageSize: 200,
        pageToken: pageToken,
        $fields: _fields,
      );
      for (final file in result.files ?? const <drive.File>[]) {
        files.add(_toRemote(file));
      }
      pageToken = result.nextPageToken;
    } while (pageToken != null);
    return files;
  }

  Future<RemoteFile?> findFile(String folderId, String name) async {
    final result = await _api.files.list(
      q: "'$folderId' in parents and name = '${_escape(name)}' and trashed = false",
      spaces: 'drive',
      $fields: _fields,
    );
    final files = result.files ?? const [];
    return files.isEmpty ? null : _toRemote(files.first, fallbackName: name);
  }

  RemoteFile _toRemote(drive.File file, {String fallbackName = ''}) =>
      RemoteFile(
        id: file.id!,
        name: file.name ?? fallbackName,
        size: int.tryParse(file.size ?? '') ?? 0,
        createdTime:
            file.createdTime ?? DateTime.fromMillisecondsSinceEpoch(0),
        // Drive types the values as nullable; keep only real ones.
        appProperties: {
          for (final e in (file.appProperties ?? const {}).entries)
            if (e.value != null) e.key: e.value!,
        },
      );

  /// Creates a file, or replaces the content of [existingId].
  Future<String> upload({
    required String folderId,
    required String name,
    required List<int> bytes,
    Map<String, String>? appProperties,
    String? existingId,
  }) async {
    final media = drive.Media(Stream.value(bytes), bytes.length);
    if (existingId != null) {
      final updated = await _api.files.update(
        drive.File()..appProperties = appProperties,
        existingId,
        uploadMedia: media,
        $fields: 'id',
      );
      return updated.id!;
    }
    final meta = drive.File()
      ..name = name
      ..parents = [folderId]
      ..appProperties = appProperties;
    final created =
        await _api.files.create(meta, uploadMedia: media, $fields: 'id');
    return created.id!;
  }

  Future<Uint8List> download(String fileId) async {
    final media = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<Map<String, dynamic>?> readJson(String folderId, String name) async {
    final file = await findFile(folderId, name);
    if (file == null) return null;
    final bytes = await download(file.id);
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<void> writeJson(
    String folderId,
    String name,
    Map<String, dynamic> json,
  ) async {
    final existing = await findFile(folderId, name);
    await upload(
      folderId: folderId,
      name: name,
      bytes: utf8.encode(jsonEncode(json)),
      existingId: existing?.id,
    );
  }

  Future<void> delete(String fileId) => _api.files.delete(fileId);

  Future<DriveQuota?> quota() async {
    final about = await _api.about.get($fields: 'storageQuota');
    final quota = about.storageQuota;
    if (quota == null) return null;
    return DriveQuota(
      limitBytes: int.tryParse(quota.limit ?? ''),
      usageBytes: int.tryParse(quota.usage ?? '') ?? 0,
    );
  }
}
