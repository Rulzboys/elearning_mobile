import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../../shared/models/models.dart';

class PrivateImageUpload {
  const PrivateImageUpload({
    required this.bytes,
    required this.contentType,
    required this.fileName,
  });

  final Uint8List bytes;
  final String contentType;
  final String fileName;
}

Future<PrivateImageUpload?> pickPrivateImage() async {
  final picker = ImagePicker();
  XFile? recoveredFile;
  try {
    recoveredFile = (await picker.retrieveLostData()).files?.firstOrNull;
  } catch (_) {
    // Recovery is only available on supported platforms. A normal gallery
    // selection must still work on web and desktop builds.
  }
  final XFile? file =
      recoveredFile ??
      await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1800,
        requestFullMetadata: false,
      );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
    throw const AppFailure('Ukuran foto harus lebih kecil dari 5 MB.');
  }
  final lower = file.name.toLowerCase();
  final contentType =
      file.mimeType ??
      (lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp')
          ? 'image/webp'
          : lower.endsWith('.jpg') || lower.endsWith('.jpeg')
          ? 'image/jpeg'
          : '');
  if (!const ['image/jpeg', 'image/png', 'image/webp'].contains(contentType)) {
    throw const AppFailure('Gunakan foto JPG, PNG, atau WebP.');
  }
  return PrivateImageUpload(
    bytes: bytes,
    contentType: contentType,
    fileName: file.name,
  );
}
