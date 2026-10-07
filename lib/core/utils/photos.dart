import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../i18n/i18n.dart';
import 'ids.dart';
import 'photo_store.dart';

export 'photo_store.dart';

/// Takes or picks a photo, shrinks it (1280px, ~70% JPEG) and saves a copy
/// in app storage. Returns the stored file name, or null if cancelled.
Future<String?> captureBillPhoto({required bool fromCamera}) =>
    _pickAndStore(fromCamera: fromCamera, maxSize: 1280, quality: 70);

/// Business logo from the gallery: smaller and sharper than bill photos.
/// Stored with the photos, so it is backed up to Drive the same way.
Future<String?> pickLogo() =>
    _pickAndStore(fromCamera: false, maxSize: 600, quality: 90);

Future<String?> _pickAndStore({
  required bool fromCamera,
  required double maxSize,
  required int quality,
}) async {
  final picked = await ImagePicker().pickImage(
    source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: maxSize,
    maxHeight: maxSize,
    imageQuality: quality,
  );
  if (picked == null) return null;
  final name = '${newId()}.jpg';
  await File(picked.path).copy((await photoFile(name)).path);
  return name;
}

/// Full-screen zoomable view of a stored photo.
Future<void> showPhoto(BuildContext context, String name) async {
  final file = await photoFile(name);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              child: file.existsSync()
                  ? Image.file(file, fit: BoxFit.contain)
                  : Center(
                      child: Text(
                        tr('Photo not found on this phone'),
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
            ),
          ),
          SafeArea(
            child: IconButton(
              tooltip: tr('Close'),
              color: Colors.white,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Small thumbnail for lists and forms.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({
    super.key,
    required this.name,
    this.size = 56,
    this.fit = BoxFit.cover,
  });

  final String name;
  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: photoFile(name),
      builder: (context, snapshot) {
        final file = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.square(
            dimension: size,
            child: file != null && file.existsSync()
                ? Image.file(file, fit: fit, cacheWidth: 300)
                : const ColoredBox(
                    color: Color(0xFFE2E8F0),
                    child: Icon(Icons.image_not_supported),
                  ),
          ),
        );
      },
    );
  }
}
