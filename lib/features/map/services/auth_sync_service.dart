import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_places_cache.dart';
import 'supabase_places_service.dart';

class AuthSyncService {
  final LocalPlacesCache _localCache;
  final SupabasePlacesService _supabaseService;
  StreamSubscription<AuthState>? _authStateSubscription;
  bool _wasAuthenticated = false;

  AuthSyncService({
    required LocalPlacesCache localCache,
    required SupabasePlacesService supabaseService,
  })  : _localCache = localCache,
        _supabaseService = supabaseService;

  void startListening() {
    _wasAuthenticated = Supabase.instance.client.auth.currentUser != null;

    _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;
      final bool isAuthenticated = session != null;

      // When a user logs in (transitioning from guest to authenticated)
      if (!_wasAuthenticated && isAuthenticated && event == AuthChangeEvent.signedIn) {
        await _performBackgroundSync();
      }

      _wasAuthenticated = isAuthenticated;
    });
  }

  Future<void> _performBackgroundSync() async {
    try {
      // 1. Read all places from LocalPlacesCache
      final localPlaces = await _localCache.getPlaces();
      
      // 2. Ensure duplicate limits (max 5) are respected during this sync.
      final placesToSync = localPlaces.take(5).toList();

      // 3. Upload them to the Supabase user_saved_places table concurrently
      // 🚀 CRITICAL FIX: Execute network calls in parallel to prevent background blocking
      await Future.wait(placesToSync.map((place) => _supabaseService.savePlace(place)));
    } catch (e) {
      // Sync failed, skip
    }
  }

  void dispose() {
    _authStateSubscription?.cancel();
  }
}
