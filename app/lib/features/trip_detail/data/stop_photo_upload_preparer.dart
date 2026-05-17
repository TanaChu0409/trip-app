import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:trip_planner_app/core/utils/image_format.dart';
import 'package:trip_planner_app/core/utils/photo_compress.dart';

enum StopPhotoUploadErrorCode {
  unsupportedImageFormat,
  invalidImageData,
  iphoneImageConversionFailed,
}

class StopPhotoUploadException implements Exception {
  const StopPhotoUploadException({
    required this.code,
    required this.userMessage,
    required this.diagnosticMessage,
    this.sourceFormat = DetectedImageFormat.unknown,
    this.cause,
  });

  final StopPhotoUploadErrorCode code;
  final String userMessage;
  final String diagnosticMessage;
  final DetectedImageFormat sourceFormat;
  final Object? cause;

  @override
  String toString() => diagnosticMessage;
}

class PreparedStopPhotoUpload {
  const PreparedStopPhotoUpload({
    required this.bytes,
    required this.contentType,
    required this.fileExtension,
    required this.sourceFormat,
  });

  final Uint8List bytes;
  final String contentType;
  final String fileExtension;
  final DetectedImageFormat sourceFormat;
}

typedef StopPhotoImageCompressor = Future<Uint8List> Function(Uint8List bytes);
typedef StopPhotoRasterValidator = bool Function(Uint8List bytes);

class StopPhotoUploadPreparer {
  StopPhotoUploadPreparer({
    StopPhotoImageCompressor? compressor,
    StopPhotoRasterValidator? rasterValidator,
  })  : _compressor = compressor ?? compressImageToJpeg,
        _rasterValidator = rasterValidator ?? _defaultRasterValidator;

  final StopPhotoImageCompressor _compressor;
  final StopPhotoRasterValidator _rasterValidator;

  Future<PreparedStopPhotoUpload> prepare(Uint8List bytes) async {
    final sourceFormat = detectImageFormat(bytes);

    switch (sourceFormat) {
      case DetectedImageFormat.jpeg:
      case DetectedImageFormat.png:
      case DetectedImageFormat.webp:
        return _prepareKnownRaster(bytes, sourceFormat);
      case DetectedImageFormat.heic:
      case DetectedImageFormat.heif:
        return _prepareIphoneFormat(bytes, sourceFormat);
      case DetectedImageFormat.unknown:
        throw const StopPhotoUploadException(
          code: StopPhotoUploadErrorCode.unsupportedImageFormat,
          userMessage: '不支援的圖片格式，請改用 JPEG、PNG 或 WebP。',
          diagnosticMessage: 'Unsupported image format signature.',
        );
    }
  }

  Future<PreparedStopPhotoUpload> _prepareKnownRaster(
    Uint8List bytes,
    DetectedImageFormat sourceFormat,
  ) async {
    if (!_rasterValidator(bytes)) {
      throw StopPhotoUploadException(
        code: StopPhotoUploadErrorCode.invalidImageData,
        sourceFormat: sourceFormat,
        userMessage: '這張圖片檔案已損毀或無法讀取，請改選其他照片。',
        diagnosticMessage: 'Raster decode failed for $sourceFormat bytes.',
      );
    }

    try {
      final compressed = await _compressor(bytes);
      if (compressed.isEmpty) {
        throw const FormatException('Image compression returned no bytes.');
      }

      return PreparedStopPhotoUpload(
        bytes: compressed,
        contentType: 'image/jpeg',
        fileExtension: 'jpg',
        sourceFormat: sourceFormat,
      );
    } catch (_) {
      return PreparedStopPhotoUpload(
        bytes: bytes,
        contentType: sourceFormat.contentType,
        fileExtension: sourceFormat.fileExtension,
        sourceFormat: sourceFormat,
      );
    }
  }

  Future<PreparedStopPhotoUpload> _prepareIphoneFormat(
    Uint8List bytes,
    DetectedImageFormat sourceFormat,
  ) async {
    try {
      final compressed = await _compressor(bytes);
      if (compressed.isEmpty) {
        throw const FormatException('Image compression returned no bytes.');
      }

      return PreparedStopPhotoUpload(
        bytes: compressed,
        contentType: 'image/jpeg',
        fileExtension: 'jpg',
        sourceFormat: sourceFormat,
      );
    } catch (error) {
      throw StopPhotoUploadException(
        code: StopPhotoUploadErrorCode.iphoneImageConversionFailed,
        sourceFormat: sourceFormat,
        cause: error,
        userMessage: '目前無法處理這張 iPhone 圖片，請先轉成 JPEG 或 PNG 後再試。',
        diagnosticMessage:
            'Failed to convert iPhone image format $sourceFormat: $error',
      );
    }
  }
}

bool _defaultRasterValidator(Uint8List bytes) {
  return img.decodeImage(bytes) != null;
}
