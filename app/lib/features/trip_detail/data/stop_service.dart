import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

class StopService {
  StopService._();

  static final StopService instance = StopService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<StopItem> createStop({
    required String dayId,
    required StopItem stop,
  }) async {
    final data = await _client
        .from('stops')
        .insert({...stop.toJson(), 'day_id': dayId})
        .select()
        .single();

    return StopItem.fromJson(Map<String, dynamic>.from(data));
  }

  Future<StopItem> updateStop(StopItem stop) async {
    final stopId = stop.id;
    if (stopId == null || stopId.isEmpty) {
      throw ArgumentError('Stop id is required for update.');
    }

    final data = await _client
        .from('stops')
        .update(stop.toJson())
        .eq('id', stopId)
        .select()
        .single();

    return StopItem.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> reorderStops({
    required String dayId,
    required List<StopItem> stops,
  }) async {
    await Future.wait([
      for (final stop in stops)
        if (stop.id != null)
          _client
              .from('stops')
              .update({'sort_order': stop.sortOrder})
              .eq('day_id', dayId)
              .eq('id', stop.id!),
    ]);
  }

  Future<void> deleteStop(String stopId) {
    return _client.from('stops').delete().eq('id', stopId);
  }
}