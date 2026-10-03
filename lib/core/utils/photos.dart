import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'ids.dart';
import 'photo_store.dart';

export 'photo_store.dart';

/// Takes or picks a photo, shrinks it (1280px, ~70% JPEG) and saves a copy
/// in app storage. Returns the stored file name, or null if cancelled.
Future<String?> captureBillPhoto({required bool fromCamera}) async {
  final picked = await ImagePicker().pickImage(
    source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1280,
    maxHeight: 1280,
    imageQuality: 70,
  );
  if (picked == null) return null;
  final name = '${newId()}.jpg';
  await File(picked.path).copy((await photoFile(name)).path);
  return name;
}

Future<void> deletePhoto(String? name) async {
  if (name == null) return;
  final file = await photoFile(name);
  if (file.existsSync()) await file.delete();
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
                  : const Center(
                      child: Text(
                        'Photo not found on this phone',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
            ),
          ),
          SafeArea(
            child: IconButton(
              tooltip: 'Close',
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
  const PhotoThumb({super.key, required this.name, this.size = 56});

  final String name;
  final double size;

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
                ? Image.file(file, fit: BoxFit.cover, cacheWidth: 200)
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
