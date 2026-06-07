import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'saved_place.dart';

class LocalPlacesCache {
  static const String _kSavedPlacesKey = 'local_saved_places';

  /// Retrieves all saved places from SharedPreferences
  Future<List<SavedPlace>> getPlaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? placesJson = prefs.getString(_kSavedPlacesKey);
      if (placesJson == null || placesJson.isEmpty) {
        return [];
      }
      final List<dynamic> decoded = json.decode(placesJson);
      return decoded.map((e) => SavedPlace.fromMap(e)).toList();
    } catch (e) {
      // Return empty list on failure to prevent crashes
      return [];
    }
  }

  /// Saves the list of places to SharedPreferences
  Future<void> savePlaces(List<SavedPlace> places) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String encoded = json.encode(places.map((e) => e.toMap()).toList());
      await prefs.setString(_kSavedPlacesKey, encoded);
    } catch (e) {
      // Optionally log error
    }
  }

  /// Clears the entire places cache
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSavedPlacesKey);
    } catch (e) {
      // Optionally log error
    }
  }
}
