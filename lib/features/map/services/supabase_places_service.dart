import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridel/core/services/saved_places_service.dart';

class SupabasePlacesService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<SavedPlace>> getPlaces() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await _client
          .from('user_saved_places')
          .select()
          .eq('user_id', user.id);

      final List<dynamic> data = response;
      return data.map((item) => SavedPlace(
        type: item['place_type'] as String,
        latitude: (item['latitude'] as num).toDouble(),
        longitude: (item['longitude'] as num).toDouble(),
      )).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> savePlace(SavedPlace place) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await _client.from('user_saved_places').upsert({
        'user_id': user.id,
        'place_type': place.type,
        'latitude': place.latitude,
        'longitude': place.longitude,
      });
    } catch (e) {
      // Ignore or log error
    }
  }

  Future<void> removePlace(String type) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await _client
          .from('user_saved_places')
          .delete()
          .eq('user_id', user.id)
          .eq('place_type', type);
    } catch (e) {
      // Ignore or log error
    }
  }
}
