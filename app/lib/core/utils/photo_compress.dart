import 'dart:typed_data';

import 'photo_compress_io.dart'
    if (dart.library.html) 'photo_compress_web.dart' as compress_impl;

/// Compress image [bytes] (any format, including HEIC on iOS) to JPEG.
/// - On **native** (iOS/Android): uses `flutter_image_compress`, which
///   handles HEIC → JPEG conversion automatically.
/// - On **web** (Safari/Chrome): uses the pure-Dart `image` package.
///
/// The result is resized so neither dimension exceeds [maxDimension] (default
/// 1200 px) and re-encoded at [quality] (default 80, 0–100).
Future<Uint8List> compressImageToJpeg(
  Uint8List bytes, {
  int maxDimension = 1200,
  int quality = 80,
}) async {
  final result = await compress_impl.compressToJpeg(
    bytes,
    maxDimension: maxDimension,
    quality: quality,
  );
  return result is Uint8List ? result : Uint8List.fromList(result);
}
