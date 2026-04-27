import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:trip_planner_app/core/utils/photo_compress.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

class StopPhotoService {
  StopPhotoService._();

  static final StopPhotoService instance = StopPhotoService._();

  static const _bucket = 'stop-photos';
  static const int maxPhotos = 4;

  SupabaseClient get _client => Supabase.instance.client;

  /// Compress [bytes] to JPEG, upload to Supabase Storage, insert a row in
  /// `stop_photos`, and return the resulting [StopPhoto].
  ///
  /// Uploaded path: `{userId}/{tripId}/{stopId}/{uuid}.jpg`
  Future<StopPhoto> compressAndUpload({
    required String stopId,
    required String tripId,
    required String userId,
    required Uint8List bytes,
  }) async {
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

    final publicUrl =
        _client.storage.from(_bucket).getPublicUrl(storagePath);

    final row = await _client
        .from('stop_photos')
        .insert({
          'stop_id': stopId,
          'storage_path': storagePath,
          'sort_order': 0,
        })
        .select()
        .single();

    return StopPhoto.fromJson(
      Map<String, dynamic>.from(row),
      publicUrl: publicUrl,
    );
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

  /// Build the public URL for a given [storagePath].
  String getPublicUrl(String storagePath) {
    return _client.storage.from(_bucket).getPublicUrl(storagePath);
  }
}

