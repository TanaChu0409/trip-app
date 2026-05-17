import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trip_detail/data/stop_photo_upload_preparer.dart';

void main() {
  group('StopPhotoUploadPreparer', () {
    test('compresses valid jpeg bytes when conversion succeeds', () async {
      final preparer = StopPhotoUploadPreparer(
        compressor: (_) async => Uint8List.fromList(const [0xAA, 0xBB]),
        rasterValidator: (_) => true,
      );

      final prepared = await preparer.prepare(
        Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xE0]),
      );

      expect(prepared.bytes, [0xAA, 0xBB]);
      expect(prepared.contentType, 'image/jpeg');
      expect(prepared.fileExtension, 'jpg');
    });

    test('falls back to original png bytes only after decode validation', () async {
      final source = Uint8List.fromList(const [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]);
      final preparer = StopPhotoUploadPreparer(
        compressor: (_) async => throw const FormatException('compress failed'),
        rasterValidator: (_) => true,
      );

      final prepared = await preparer.prepare(source);

      expect(prepared.bytes, source);
      expect(prepared.contentType, 'image/png');
      expect(prepared.fileExtension, 'png');
    });

    test('rejects malformed png bytes when decode validation fails', () async {
      final preparer = StopPhotoUploadPreparer(
        compressor: (_) async => throw const FormatException('compress failed'),
        rasterValidator: (_) => false,
      );

      expect(
        () => preparer.prepare(
          Uint8List.fromList(const [
            0x89,
            0x50,
            0x4E,
            0x47,
            0x0D,
            0x0A,
            0x1A,
            0x0A,
          ]),
        ),
        throwsA(
          isA<StopPhotoUploadException>().having(
            (error) => error.code,
            'code',
            StopPhotoUploadErrorCode.invalidImageData,
          ),
        ),
      );
    });

    test('converts heic bytes to jpeg when native conversion succeeds', () async {
      final preparer = StopPhotoUploadPreparer(
        compressor: (_) async => Uint8List.fromList(const [0x11, 0x22]),
        rasterValidator: (_) => false,
      );

      final prepared = await preparer.prepare(
        Uint8List.fromList(const [
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
        ]),
      );

      expect(prepared.bytes, [0x11, 0x22]);
      expect(prepared.contentType, 'image/jpeg');
      expect(prepared.fileExtension, 'jpg');
    });

    test('returns explicit iPhone conversion error for heif failures', () async {
      final preparer = StopPhotoUploadPreparer(
        compressor: (_) async => throw const FormatException('compress failed'),
        rasterValidator: (_) => false,
      );

      expect(
        () => preparer.prepare(
          Uint8List.fromList(const [
            0x00,
            0x00,
            0x00,
            0x18,
            0x66,
            0x74,
            0x79,
            0x70,
            0x6D,
            0x69,
            0x66,
            0x31,
          ]),
        ),
        throwsA(
          isA<StopPhotoUploadException>().having(
            (error) => error.code,
            'code',
            StopPhotoUploadErrorCode.iphoneImageConversionFailed,
          ),
        ),
      );
    });

    test('rejects unsupported image signatures', () async {
      final preparer = StopPhotoUploadPreparer(
        compressor: (_) async => Uint8List.fromList(const [0xAA]),
        rasterValidator: (_) => true,
      );

      expect(
        () => preparer.prepare(Uint8List.fromList(const [0x01, 0x02, 0x03])),
        throwsA(
          isA<StopPhotoUploadException>().having(
            (error) => error.code,
            'code',
            StopPhotoUploadErrorCode.unsupportedImageFormat,
          ),
        ),
      );
    });
  });
}
