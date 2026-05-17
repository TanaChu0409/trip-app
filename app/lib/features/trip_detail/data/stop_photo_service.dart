import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:trip_planner_app/core/utils/image_format.dart';
import 'package:trip_planner_app/core/utils/photo_compress.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

class StopPhotoService {
  StopPhotoService._();

  static final StopPhotoService instance = StopPhotoService._();

  static const _bucket = 'stop-photos';
  static const _signedUrlExpirySeconds = 60 * 60;
  static const signedUrlRefreshTolerance = Duration(minutes: 1);
  static const int maxPhotos = 4;

  SupabaseClient get _client => Supabase.instance.client;

  /// Compress [bytes] to JPEG, upload to Supabase Storage, insert a row in
  /// `stop_photos`, and return the resulting [StopPhoto].
  ///
  /// Uploaded path: `{userId}/{tripId}/{stopId}/{uuid}.{ext}`
  Future<StopPhoto> compressAndUpload({
    required String stopId,
    required String tripId,
    required int sortOrder,
    required Uint8List bytes,
  }) async {
    final userId = _requireUserId();
    final upload = await _prepareUpload(bytes);

    final filename = '${const Uuid().v4()}.${upload.fileExtension}';
    final storagePath = '$userId/$tripId/$stopId/$filename';

    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          upload.bytes,
          fileOptions: FileOptions(
            contentType: upload.contentType,
            upsert: false,
          ),
        );

    try {
      final row = await _client
          .from('stop_photos')
          .insert({
            'stop_id': stopId,
            'storage_path': storagePath,
            'sort_order': sortOrder,
          })
          .select()
          .single();

      return buildPhotoFromRow(Map<String, dynamic>.from(row));
    } catch (_) {
      try {
        // Ignore cleanup failures because the original insert error is the
        // actionable failure for the caller.
        await _client.storage.from(_bucket).remove([storagePath]);
      } catch (_) {}
      rethrow;
    }
  }

  /// Delete [photo] from both storage and the database.
  Future<void> deletePhoto(StopPhoto photo) async {
    final photoId = photo.id;
    if (photoId == null) return;

    // Best-effort storage delete — continue even if the object is already gone.
    try {
      await _client.storage.from(_bucket).remove([photo.storagePath]);
    } catch (_) {}

    await _client.from('stop_photos').delete().eq('id', photoId);
  }

  /// Fetch all photos for the given [stopIds], ordered by `sort_order`.
  Future<List<Map<String, dynamic>>> fetchPhotosForStops(
      List<String> stopIds) async {
    if (stopIds.isEmpty) return const [];

    final rows = await _client
        .from('stop_photos')
        .select('id, stop_id, storage_path, sort_order')
        .inFilter('stop_id', stopIds)
        .order('sort_order');

    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, List<StopPhoto>>> fetchPhotoMapForStops(
      List<String> stopIds) async {
    final rows = await fetchPhotosForStops(stopIds);
    if (rows.isEmpty) {
      return const {};
    }

    final photos = await Future.wait(rows.map(buildPhotoFromRow));
    final photosByStopId = <String, List<StopPhoto>>{};
    for (var index = 0; index < rows.length; index += 1) {
      final stopId = rows[index]['stop_id'] as String;
      photosByStopId.putIfAbsent(stopId, () => []).add(photos[index]);
    }
    return photosByStopId;
  }

  Future<List<StopPhoto>> fetchPhotosForStop(String stopId) async {
    final rows = await fetchPhotosForStops([stopId]);
    if (rows.isEmpty) {
      return const [];
    }

    return Future.wait(rows.map(buildPhotoFromRow));
  }

  Future<StopPhoto> buildPhotoFromRow(Map<String, dynamic> row) async {
    final storagePath = row['storage_path'] as String? ?? '';
    final signedUrl = await _createSignedUrl(storagePath);
    return StopPhoto.fromJson(
      row,
      publicUrl: signedUrl,
      signedUrlExpiresAt: _nextSignedUrlExpiry(),
    );
  }

  Future<StopPhoto> ensureActiveUrl(StopPhoto photo) async {
    if (photo.storagePath.isEmpty ||
        !photo.needsUrlRefresh(tolerance: signedUrlRefreshTolerance)) {
      return photo;
    }

    final signedUrl = await _createSignedUrl(photo.storagePath);
    return photo.copyWith(
      url: signedUrl,
      signedUrlExpiresAt: _nextSignedUrlExpiry(),
    );
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw const AuthException('登入狀態已失效，請重新登入後再試。');
    }
    return userId;
  }

  Future<String> _createSignedUrl(String storagePath) {
    return _client.storage
        .from(_bucket)
        .createSignedUrl(storagePath, _signedUrlExpirySeconds);
  }

  DateTime _nextSignedUrlExpiry() {
    return DateTime.now().add(
      const Duration(seconds: _signedUrlExpirySeconds),
    );
  }

  Future<_PreparedStopPhotoUpload> _prepareUpload(Uint8List bytes) async {
    final sourceFormat = detectImageFormat(bytes);

    try {
      final compressed = await compressImageToJpeg(bytes);
      if (compressed.isEmpty) {
        throw const FormatException('Image compression returned no bytes.');
      }

      return _PreparedStopPhotoUpload(
        bytes: compressed,
        contentType: 'image/jpeg',
        fileExtension: 'jpg',
      );
    } catch (_) {
      if (sourceFormat.canUploadWithoutConversion) {
        return _PreparedStopPhotoUpload(
          bytes: bytes,
          contentType: sourceFormat.contentType,
          fileExtension: sourceFormat.fileExtension,
        );
      }

      if (sourceFormat == DetectedImageFormat.heic ||
          sourceFormat == DetectedImageFormat.heif) {
        throw ArgumentError('目前無法處理這張 iPhone 圖片，請先轉成 JPEG 或 PNG 後再試。');
      }

      throw ArgumentError('不支援的圖片格式，請改用 JPEG、PNG 或 WebP。');
    }
  }
}

class _PreparedStopPhotoUpload {
  const _PreparedStopPhotoUpload({
    required this.bytes,
    required this.contentType,
    required this.fileExtension,
  });

  final Uint8List bytes;
  final String contentType;
  final String fileExtension;
}
