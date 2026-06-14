import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_places_cache.dart';
import 'supabase_places_service.dart';
import 'places_repository.dart';
import 'saved_place.dart';

class AuthSyncService {
  final LocalPlacesCache _localCache = LocalPlacesCache();
  final SupabasePlacesService _cloudService = SupabasePlacesService();
  final PlacesRepository _repository;
  StreamSubscription<AuthState>? _authSubscription;

  AuthSyncService(this._repository) {
    _initAuthListener();
  }

  void _initAuthListener() {
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      if (event == AuthChangeEvent.signedIn && session != null) {
        _handleLoginSync(session.user.id);
      } else if (event == AuthChangeEvent.signedOut) {
        _handleLogout();
      }
    });
  }

  /// Handles merging local offline places with cloud storage on login.
  Future<void> _handleLoginSync(String userId) async {
    // 1. Fetch current local places
    final localPlaces = await _localCache.getPlaces();

    // 2. Push any local places to Cloud to back them up silently
    for (final place in localPlaces) {
      await _cloudService.upsertPlace(place, userId);
    }

    // 3. Fetch all places from Cloud
    final cloudPlaces = await _cloudService.fetchFromCloud(userId);

    // 4. Merge them (Cloud data overwrites local if there are duplicates,
    // but in this setup, since we just pushed local to cloud, cloud has everything).
    // We can use a map keyed by place ID to deduplicate.
    final Map<String, SavedPlace> mergedMap = {};

    // First add local places
    for (final place in localPlaces) {
      mergedMap[place.id] = place;
    }

    // Then overwrite/add with cloud places
    for (final place in cloudPlaces) {
      mergedMap[place.id] = place;
    }

    final mergedPlaces = mergedMap.values.toList();

    // 5. Update local state silently
    _repository.silentUpdateLocalState(mergedPlaces);
  }

  /// Handles clearing sensitive local data on logout.
  Future<void> _handleLogout() async {
    await _repository.clearLocalState();
  }

  void dispose() {
    _authSubscription?.cancel();
  }
}
