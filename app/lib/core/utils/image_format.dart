import 'dart:typed_data';

enum DetectedImageFormat {
  jpeg,
  png,
  webp,
  heic,
  heif,
  unknown,
}

extension DetectedImageFormatX on DetectedImageFormat {
  String get contentType {
    switch (this) {
      case DetectedImageFormat.jpeg:
        return 'image/jpeg';
      case DetectedImageFormat.png:
        return 'image/png';
      case DetectedImageFormat.webp:
        return 'image/webp';
      case DetectedImageFormat.heic:
        return 'image/heic';
      case DetectedImageFormat.heif:
        return 'image/heif';
      case DetectedImageFormat.unknown:
        return 'application/octet-stream';
    }
  }

  String get fileExtension {
    switch (this) {
      case DetectedImageFormat.jpeg:
        return 'jpg';
      case DetectedImageFormat.png:
        return 'png';
      case DetectedImageFormat.webp:
        return 'webp';
      case DetectedImageFormat.heic:
        return 'heic';
      case DetectedImageFormat.heif:
        return 'heif';
      case DetectedImageFormat.unknown:
        return 'bin';
    }
  }

  bool get canUploadWithoutConversion {
    switch (this) {
      case DetectedImageFormat.jpeg:
      case DetectedImageFormat.png:
      case DetectedImageFormat.webp:
        return true;
      case DetectedImageFormat.heic:
      case DetectedImageFormat.heif:
      case DetectedImageFormat.unknown:
        return false;
    }
  }
}

DetectedImageFormat detectImageFormat(Uint8List bytes) {
  if (_hasPrefix(bytes, const [0xFF, 0xD8, 0xFF])) {
    return DetectedImageFormat.jpeg;
  }

  if (_hasPrefix(bytes, const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ])) {
    return DetectedImageFormat.png;
  }

  if (_hasPrefix(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
      _hasAsciiAt(bytes, 8, 'WEBP')) {
    return DetectedImageFormat.webp;
  }

  if (_hasAsciiAt(bytes, 4, 'ftyp')) {
    final brand = _readAscii(bytes, 8, 4).toLowerCase();
    if (_heicBrands.contains(brand)) {
      return DetectedImageFormat.heic;
    }
    if (_heifBrands.contains(brand)) {
      return DetectedImageFormat.heif;
    }
  }

  return DetectedImageFormat.unknown;
}

bool _hasPrefix(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }

  for (var index = 0; index < prefix.length; index += 1) {
    if (bytes[index] != prefix[index]) {
      return false;
    }
  }
  return true;
}

bool _hasAsciiAt(Uint8List bytes, int offset, String value) {
  if (bytes.length < offset + value.length) {
    return false;
  }
  return _readAscii(bytes, offset, value.length) == value;
}

String _readAscii(Uint8List bytes, int offset, int length) {
  final codes = bytes.sublist(offset, offset + length);
  return String.fromCharCodes(codes);
}

const Set<String> _heicBrands = {
  'heic',
  'heix',
  'hevc',
  'hevx',
  'heim',
  'heis',
  'hevm',
  'hevs',
};

const Set<String> _heifBrands = {
  'heif',
  'mif1',
  'msf1',
};
