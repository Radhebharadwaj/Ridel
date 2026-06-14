import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'saved_place.dart';

class SupabasePlacesService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _tableName = 'saved_places';

  /// Fetches saved places from the cloud for the given user ID.
  Future<List<SavedPlace>> fetchFromCloud(String userId) async {
    try {
      final response =
          await _supabase.from(_tableName).select().eq('user_id', userId);

      final List<dynamic> data = response;
      return data.map((e) => SavedPlace.fromMap(e)).toList();
    } catch (e) {
      debugPrint('Failed to fetch from cloud: $e');
      // Handle network or offline gracefully by returning an empty list
      return [];
    }
  }

  /// Upserts a place to Supabase for the given user ID.
  Future<void> upsertPlace(SavedPlace place, String userId) async {
    try {
      final map = place.toMap();
      map['user_id'] = userId;
      map['updated_at'] = DateTime.now().toIso8601String();

      await _supabase.from(_tableName).upsert(
            map,
            onConflict: 'id', // Assuming 'id' is unique or primary key
          );
    } catch (e) {
      debugPrint('Failed to upsert place to cloud: $e');
      // Graciously ignore or queue for later
    }
  }

  /// Deletes a place from Supabase.
  Future<void> deletePlace(String placeId) async {
    try {
      await _supabase.from(_tableName).delete().eq('id', placeId);
    } catch (e) {
      debugPrint('Failed to delete place from cloud: $e');
    }
  }
}
