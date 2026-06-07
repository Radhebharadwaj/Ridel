import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ridel/core/services/saved_places_service.dart'; // For SavedPlace model

class LocalPlacesCache {
  static const String _cacheKey = 'local_saved_places_cache';

  Future<List<SavedPlace>> getPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final String? placesJson = prefs.getString(_cacheKey);
    if (placesJson != null) {
      try {
        final List<dynamic> decoded = json.decode(placesJson);
        return decoded.map((item) => SavedPlace.fromJson(item)).toList();
      } catch (e) {
        return [];
      }
    }
    return [];
  }

  Future<void> savePlaces(List<SavedPlace> places) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = json.encode(places.map((p) => p.toJson()).toList());
    await prefs.setString(_cacheKey, encoded);
  }

  Future<void> addPlace(SavedPlace place) async {
    final places = await getPlaces();
    final existingIndex = places.indexWhere((p) => p.type == place.type);
    if (existingIndex != -1) {
      places[existingIndex] = place;
    } else {
      places.add(place);
    }
    // Respect the 5 places limit
    if (places.length > 5) {
      places.removeAt(0); // Optional: keep recent or drop oldest
    }
    await savePlaces(places);
  }

  Future<void> removePlace(String type) async {
    final places = await getPlaces();
    places.removeWhere((p) => p.type == type);
    await savePlaces(places);
  }
}
