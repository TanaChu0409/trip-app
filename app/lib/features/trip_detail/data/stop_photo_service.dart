import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:trip_planner_app/core/utils/photo_compress.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

class StopPhotoService {
  StopPhotoService._();

  static final StopPhotoService instance = StopPhotoService._();

  static const _bucket = 'stop-photos';
  static const _signedUrlExpirySeconds = 60 * 60;
  static const int maxPhotos = 4;

  SupabaseClient get _client => Supabase.instance.client;

  /// Compress [bytes] to JPEG, upload to Supabase Storage, insert a row in
  /// `stop_photos`, and return the resulting [StopPhoto].
  ///
  /// Uploaded path: `{userId}/{tripId}/{stopId}/{uuid}.jpg`
  Future<StopPhoto> compressAndUpload({
    required String stopId,
    required String tripId,
    required int sortOrder,
    required Uint8List bytes,
  }) async {
    final userId = _requireUserId();
    final compressed = await compressImageToJpeg(bytes);

    final filename = '${const Uuid().v4()}.jpg';
    final storagePath = '$userId/$tripId/$stopId/$filename';

    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          compressed,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
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

  Future<StopPhoto> buildPhotoFromRow(Map<String, dynamic> row) async {
    final storagePath = row['storage_path'] as String? ?? '';
    final signedUrl = await _client.storage
        .from(_bucket)
        .createSignedUrl(storagePath, _signedUrlExpirySeconds);
    return StopPhoto.fromJson(row, publicUrl: signedUrl);
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw AuthException('登入狀態已失效，請重新登入後再試。');
    }
    return userId;
  }
}
