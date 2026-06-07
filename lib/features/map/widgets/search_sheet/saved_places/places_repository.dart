import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_places_cache.dart';
import 'supabase_places_service.dart';
import 'saved_place.dart';

class PlacesRepository {
  final LocalPlacesCache _localCache = LocalPlacesCache();
  final SupabasePlacesService _cloudService = SupabasePlacesService();
  
  /// Exposes the list of saved places to the UI.
  final ValueNotifier<List<SavedPlace>> savedPlacesNotifier = ValueNotifier([]);

  PlacesRepository() {
    _initialize();
  }

  /// Initializes the repository by loading from the ultra-fast local cache first.
  Future<void> _initialize() async {
    final cachedPlaces = await _localCache.getPlaces();
    savedPlacesNotifier.value = cachedPlaces;
  }

  /// Adds or updates a saved place.
  Future<void> addOrUpdatePlace(SavedPlace place) async {
    // 1. Update the local ValueNotifier instantly (0ms latency for UI)
    final currentPlaces = List<SavedPlace>.from(savedPlacesNotifier.value);
    final index = currentPlaces.indexWhere((p) => p.id == place.id);
    
    if (index >= 0) {
      currentPlaces[index] = place;
    } else {
      currentPlaces.add(place);
    }
    
    savedPlacesNotifier.value = currentPlaces;

    // 2. Persist to local cache first
    await _localCache.savePlaces(currentPlaces);

    // 3. Background sync to Cloud if user is logged in
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      // Fire and forget (background task)
      _cloudService.upsertPlace(place, user.id);
    }
  }

  /// Deletes a saved place.
  Future<void> deletePlace(String placeId) async {
    // 1. Update local ValueNotifier instantly
    final currentPlaces = List<SavedPlace>.from(savedPlacesNotifier.value);
    currentPlaces.removeWhere((p) => p.id == placeId);
    savedPlacesNotifier.value = currentPlaces;

    // 2. Persist to local cache
    await _localCache.savePlaces(currentPlaces);

    // 3. Background sync to Cloud if user is logged in
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      // Fire and forget
      _cloudService.deletePlace(placeId);
    }
  }

  /// Silently replaces local state (called during sync).
  void silentUpdateLocalState(List<SavedPlace> places) {
    savedPlacesNotifier.value = places;
    _localCache.savePlaces(places);
  }

  /// Clears the local repository state.
  Future<void> clearLocalState() async {
    savedPlacesNotifier.value = [];
    await _localCache.clearCache();
  }
}
