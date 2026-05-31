import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart'; // Added for LatLng
import '../models/place_model.dart';

class SupabaseSearchService {
  // 🚀 SINGLETON PATTERN: Global state maintain karne ke liye
  static final SupabaseSearchService _instance =
      SupabaseSearchService._internal();
  factory SupabaseSearchService() => _instance;
  SupabaseSearchService._internal();

  final _supabase = Supabase.instance.client;

  // ── 🚀 FIX: LRU In‑Memory Cache (Max 50 items, TTL = 5 min) ──
  // LinkedHashMap insertion order maintain karta hai, LRU ke liye perfect hai
  final LinkedHashMap<String, _CacheEntry<List<PlaceModel>>> _cache =
      LinkedHashMap();
  static const _cacheTTL = Duration(minutes: 5);
  static const int _maxCacheSize = 50;

  // ── Request Deduplication ──
  final Map<String, Future<List<PlaceModel>>> _pendingRequests = {};

  // ── Race Condition Guard ──
  int _requestId = 0;

  /// 🔥 BACKGROUND MAGIC: Saves successful searches
  Future<void> logSuccessfulSearch(PlaceModel place) async {
    try {
      final params = <String, dynamic>{
        'p_address': place.address,
        'p_categories': place.categories.isNotEmpty
            ? place.categories.join(', ')
            : 'unknown',
        'p_lat': place.latitude,
        'p_lng': place.longitude,
        'p_name': place.name,
        'p_place_id': place.placeId,
      };

      await _supabase.rpc('log_smart_place_search', params: params);
      if (kDebugMode) print("✅ SILENT SYNC: Place '${place.name}' logged!");
    } catch (e) {
      if (kDebugMode) print("❌ SILENT SYNC FAILED: $e");
    }
  }

  /// ⚡ FUZZY AUTOCOMPLETE: With Location Bias, LRU Cache, and Isolate Parsing
  Future<List<PlaceModel>> getTrendingSuggestions(String query,
      {LatLng? userLocation}) async {
    final trimmed =
        query.trim().toLowerCase(); // 🚀 FIX: Case-insensitive cache key
    if (trimmed.length < 2) return [];

    final currentRequestId = ++_requestId;

    // 1. LRU Cache Check
    if (_cache.containsKey(trimmed)) {
      final entry =
          _cache.remove(trimmed)!; // Remove to re-insert at end (LRU bump)

      if (DateTime.now().difference(entry.timestamp) < _cacheTTL) {
        _cache[trimmed] = entry; // Make it most recently used
        return entry.data;
      }
      // If expired, let it remain removed
    }

    // 2. Deduplication
    if (_pendingRequests.containsKey(trimmed)) {
      return await _pendingRequests[trimmed]!;
    }

    // 3. Network Fetch
    final future = _fetchSuggestions(trimmed, currentRequestId, userLocation);
    _pendingRequests[trimmed] = future;

    try {
      final results = await future;

      // Cache the fresh result (only if still latest)
      if (currentRequestId == _requestId) {
        _saveToCache(trimmed, results);
      }
      return results;
    } finally {
      _pendingRequests.remove(trimmed);
    }
  }

  Future<List<PlaceModel>> _fetchSuggestions(
      String query, int requestId, LatLng? location) async {
    try {
      // 🚀 FIX: Location Bias Added.
      // Supabase RPC can now sort results based on distance if lat/lng are provided.
      final Map<String, dynamic> params = {'search_query': query};
      if (location != null) {
        params['user_lat'] = location.latitude;
        params['user_lng'] = location.longitude;
      }

      final response = await _supabase
          .rpc('fuzzy_search_places', params: params)
          .timeout(const Duration(seconds: 3));

      // 🚨 Race condition check
      if (requestId != _requestId) return [];

      final rawList = response as List<dynamic>;
      if (rawList.isEmpty) return [];

      // 🚀 FIX: Isolate Parsing for Smooth UI
      // Offloads JSON parsing of 20+ items to background thread.
      final parsedPlaces = await Isolate.run(() => _parsePlacesSync(rawList));
      return parsedPlaces;
    } catch (e) {
      if (requestId != _requestId) return [];
      if (e is PostgrestException && e.code == 'PGRST202') return [];
      if (kDebugMode) print("❌ FETCH TRENDING FAILED: $e");
      return []; // Fallback empty, let UI handle or fallback to NetworkFallbackService
    }
  }

  // ── 🚀 Isolate Helper Method ──
  static List<PlaceModel> _parsePlacesSync(List<dynamic> rawData) {
    try {
      return rawData
          .map((json) => PlaceModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint("Isolate parse error: $e");
      return [];
    }
  }

  // ── 🚀 LRU Cache Manager ──
  void _saveToCache(String query, List<PlaceModel> results) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(
          _cache.keys.first); // Removes the oldest (least recently used)
    }
    _cache[query] = _CacheEntry(data: results, timestamp: DateTime.now());
  }

  void clearCache() => _cache.clear();

  void cancelPendingRequests() {
    _pendingRequests.clear();
    _requestId++;
  }
}

class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  _CacheEntry({required this.data, required this.timestamp});
}
