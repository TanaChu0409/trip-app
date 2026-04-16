import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

class ParkingSpotService {
  ParkingSpotService._();

  static final ParkingSpotService instance = ParkingSpotService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<ParkingSpot> createParkingSpot({
    required String stopId,
    required ParkingSpot parkingSpot,
  }) async {
    final data = await _client
        .from('parking_spots')
        .insert({...parkingSpot.toJson(), 'stop_id': stopId})
        .select()
        .single();

    return ParkingSpot.fromJson(Map<String, dynamic>.from(data));
  }

  Future<ParkingSpot> updateParkingSpot(ParkingSpot parkingSpot) async {
    final parkingSpotId = parkingSpot.id;
    if (parkingSpotId == null || parkingSpotId.isEmpty) {
      throw ArgumentError('Parking spot id is required for update.');
    }

    final data = await _client
        .from('parking_spots')
        .update(parkingSpot.toJson())
        .eq('id', parkingSpotId)
        .select()
        .single();

    return ParkingSpot.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> reorderParkingSpots({
    required String stopId,
    required List<ParkingSpot> parkingSpots,
  }) async {
    await Future.wait([
      for (final parkingSpot in parkingSpots)
        if (parkingSpot.id != null)
          _client
              .from('parking_spots')
              .update({'sort_order': parkingSpot.sortOrder})
              .eq('stop_id', stopId)
              .eq('id', parkingSpot.id!),
    ]);
  }

  Future<void> deleteParkingSpot(String parkingSpotId) {
    return _client.from('parking_spots').delete().eq('id', parkingSpotId);
  }
}