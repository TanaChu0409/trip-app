import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/core/utils/image_format.dart';

void main() {
  test('detects png signature', () {
    final bytes = Uint8List.fromList(const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
    ]);

    expect(detectImageFormat(bytes), DetectedImageFormat.png);
    expect(DetectedImageFormat.png.canUploadWithoutConversion, isTrue);
    expect(DetectedImageFormat.png.contentType, 'image/png');
  });

  test('detects jpeg signature', () {
    final bytes = Uint8List.fromList(const [
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      0x00,
      0x10,
    ]);

    expect(detectImageFormat(bytes), DetectedImageFormat.jpeg);
  });

  test('detects webp signature', () {
    final bytes = Uint8List.fromList(const [
      0x52,
      0x49,
      0x46,
      0x46,
      0x24,
      0x00,
      0x00,
      0x00,
      0x57,
      0x45,
      0x42,
      0x50,
    ]);

    expect(detectImageFormat(bytes), DetectedImageFormat.webp);
  });

  test('detects heic signature', () {
    final bytes = Uint8List.fromList(const [
      0x00,
      0x00,
      0x00,
      0x18,
      0x66,
      0x74,
      0x79,
      0x70,
      0x68,
      0x65,
      0x69,
      0x63,
    ]);

    expect(detectImageFormat(bytes), DetectedImageFormat.heic);
    expect(DetectedImageFormat.heic.canUploadWithoutConversion, isFalse);
  });

  test('returns unknown for unsupported bytes', () {
    final bytes = Uint8List.fromList(const [0x01, 0x02, 0x03, 0x04]);

    expect(detectImageFormat(bytes), DetectedImageFormat.unknown);
    expect(DetectedImageFormat.unknown.canUploadWithoutConversion, isFalse);
  });
}
