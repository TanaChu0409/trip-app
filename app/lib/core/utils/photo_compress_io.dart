import 'dart:typed_data';

/// Compress [bytes] to JPEG with max dimension [maxDimension] and [quality].
/// This is the **native (iOS/Android)** implementation using
/// `flutter_image_compress`, which handles HEIC/HEIF → JPEG conversion
/// automatically on iOS.
// ignore: depend_on_referenced_packages
import 'package:flutter_image_compress/flutter_image_compress.dart';

Future<List<int>> compressToJpeg(
  Uint8List bytes, {
  required int maxDimension,
  required int quality,
}) async {
  final result = await FlutterImageCompress.compressWithList(
    bytes,
    minWidth: maxDimension,
    minHeight: maxDimension,
    quality: quality,
    format: CompressFormat.jpeg,
  );
  return result;
}
