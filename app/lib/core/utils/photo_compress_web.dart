import 'dart:typed_data';

/// Compress [bytes] to JPEG with max dimension [maxDimension] and [quality].
/// This is the **web** implementation using the pure-Dart `image` package.
/// HEIC is not encountered on web, so only common formats (JPEG/PNG/WebP)
/// are handled.
// ignore: depend_on_referenced_packages
import 'package:image/image.dart' as img;

Future<List<int>> compressToJpeg(
  Uint8List bytes, {
  required int maxDimension,
  required int quality,
}) async {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('不支援的圖片格式，請改用 JPEG、PNG 或 WebP。');
  }

  img.Image resized;
  if (decoded.width > maxDimension || decoded.height > maxDimension) {
    if (decoded.width >= decoded.height) {
      resized = img.copyResize(decoded, width: maxDimension);
    } else {
      resized = img.copyResize(decoded, height: maxDimension);
    }
  } else {
    resized = decoded;
  }

  return img.encodeJpg(resized, quality: quality);
}
