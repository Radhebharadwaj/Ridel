import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridel/core/services/saved_places_service.dart';
import '../services/local_places_cache.dart';
import '../services/supabase_places_service.dart';

class PlacesRepository {
  final LocalPlacesCache _localCache;
  final SupabasePlacesService _supabaseService;

  PlacesRepository({
    required LocalPlacesCache localCache,
    required SupabasePlacesService supabaseService,
  })  : _localCache = localCache,
        _supabaseService = supabaseService;

  Stream<List<SavedPlace>> getPlaces() async* {
    // 1. Instantly return data from local cache
    final localPlaces = await _localCache.getPlaces();
    yield localPlaces;

    // 2. If authenticated, fetch data from Supabase in the background
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final remotePlaces = await _supabaseService.getPlaces();

      // 3. If Supabase data differs from the cache, update local cache & yield
      final localJson = jsonEncode(localPlaces.map((p) => p.toJson()).toList());
      final remoteJson =
          jsonEncode(remotePlaces.map((p) => p.toJson()).toList());

      if (localJson != remoteJson) {
        await _localCache.savePlaces(remotePlaces);
        yield remotePlaces;
      }
    }
  }

  Future<void> addPlace(SavedPlace place) async {
    // 1. Save to LocalPlacesCache first for instant UI update
    await _localCache.addPlace(place);

    // 2. If authenticated, push to Supabase
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await _supabaseService.savePlace(place);
    }
  }

  Future<void> removePlace(String type) async {
    await _localCache.removePlace(type);

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await _supabaseService.removePlace(type);
    }
  }
}
