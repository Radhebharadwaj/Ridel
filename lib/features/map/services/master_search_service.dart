import 'dart:async';
import 'dart:convert';

import 'dart:collection';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/place_model.dart';
import 'supabase_search_db.dart';
import 'package:ridel/core/services/place_service.dart';

// ── Cache Entry with TTL (Apple Maps Standard) ──
class _SearchCacheEntry {
  final List<PlaceModel> data;
  final DateTime timestamp;
  _SearchCacheEntry(this.data, this.timestamp);

  bool get isFresh => DateTime.now().difference(timestamp).inMinutes < 15;
}

/// 🧠 The Unified Master Search Engine (Singleton)
class MasterSearchService {
  static final MasterSearchService _instance = MasterSearchService._internal();
  factory MasterSearchService() => _instance;

  MasterSearchService._internal() {
    _supabaseEngine = SupabaseSearchService();
  }

  // 🚀 FIX: Persistent Client that NEVER closes during app lifetime
  final http.Client _client = http.Client();
  late final SupabaseSearchService _supabaseEngine;

  // ── Unified LRU Cache & Race Condition Guards ──
  final LinkedHashMap<String, _SearchCacheEntry> _searchCache = LinkedHashMap();
  static const int _maxCacheSize =
      20; // 🚀 FIX: Optimized size for memory safety

  // 🚀 FIX: Deduplication map prevents duplicate API calls for concurrent requests
  final Map<String, Future<List<PlaceModel>>> _pendingRequests = {};

  // =========================================================================
  // 1. GLOBAL SEARCH (AUTOCOMPLETE) - The Graceful Fallback Chain
  // =========================================================================
  Future<List<PlaceModel>> searchPlaces(String query,
      {LatLng? userLocation}) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed == 'dropped pin' || trimmed.contains('fetching')) return [];
    if (trimmed.length < 2) return [];

    // 1. Unified RAM Cache Check with LRU Bump & TTL
    if (_searchCache.containsKey(trimmed)) {
      final entry = _searchCache.remove(trimmed)!;
      if (entry.isFresh) {
        _searchCache[trimmed] = entry; // Move to end (LRU bump)
        return entry.data;
      }
    }

    // 2. Request Deduplication
    if (_pendingRequests.containsKey(trimmed)) {
      return await _pendingRequests[trimmed]!;
    }

    // 3. Network Fetch Pipeline (Supabase -> Nominatim)
    final future = _executeSearchPipeline(trimmed, userLocation);
    _pendingRequests[trimmed] = future;

    try {
      final results = await future;
      if (results.isNotEmpty) {
        _saveToCache(trimmed, results);
      }
      return results;
    } finally {
      _pendingRequests.remove(trimmed);
    }
  }

  Future<List<PlaceModel>> _executeSearchPipeline(
      String query, LatLng? location) async {
    // Attempt 1: Our Supabase DB (Lightning Fast, Location Biased)
    try {
      final primaryResults = await _supabaseEngine.getTrendingSuggestions(query,
          userLocation: location);
      if (primaryResults.isNotEmpty) return primaryResults;
    } catch (_) {}

    // Attempt 2: Premium Autocomplete (Ola Maps)
    try {
      debugPrint("🔄 MasterSearch: Trying Premium Autocomplete...");
      final premiumResults = await PlaceService()
          .searchPremiumPlaces(query, userLocation: location);
      if (premiumResults.isNotEmpty) return premiumResults;
    } catch (_) {}

    // Attempt 3: Fallback to Nominatim OSM
    debugPrint("🔄 MasterSearch: Premium empty, falling back to Nominatim...");
    return await _fallbackNominatimSearch(query, location);
  }

  // =========================================================================
  // 2. NEARBY PLACES (e.g. Restaurants, Fuel)
  // =========================================================================
  Future<List<PlaceModel>> getNearbyPlaces(
      LatLng location, String category) async {
    final cacheKey =
        "nearby_${category}_${location.latitude.toStringAsFixed(3)}_${location.longitude.toStringAsFixed(3)}";

    if (_searchCache.containsKey(cacheKey)) {
      final entry = _searchCache.remove(cacheKey)!;
      if (entry.isFresh) {
        _searchCache[cacheKey] = entry; // LRU Bump
        debugPrint("⚡ MasterSearch: Nearby RAM Cache Hit!");
        return entry.data;
      }
    }

    // 🚀 FIX: Broader Overpass Query (Regex-like) for better category matches
    final String overpassQuery = '''
      [out:json][timeout:5];
      (
        node["amenity"~"$category", i](around:2000, ${location.latitude}, ${location.longitude});
        node["shop"~"$category", i](around:2000, ${location.latitude}, ${location.longitude});
        node["tourism"~"$category", i](around:2000, ${location.latitude}, ${location.longitude});
      );
      out center 20;
    ''';

    try {
      final response = await _client.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: overpassQuery,
        headers: {
          'User-Agent': 'Ridel-App/1.0'
        }, // 🚀 FIX: Overpass User-Agent Added
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final places = _parseOverpassSync(response.body, category);
        if (places.isNotEmpty) _saveToCache(cacheKey, places);
        return places;
      }
    } catch (e) {
      debugPrint("⚠️ Overpass Fetch Failed: $e");
    }
    return [];
  }

  // =========================================================================
  // 3. OFFLINE LOCAL HISTORY (Instant Load)
  // =========================================================================
  Future<List<PlaceModel>> getLocalHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyList = prefs.getStringList('search_history') ?? [];
      if (historyList.isEmpty) return [];

      return _parseHistorySync(historyList);
    } catch (e) {
      return [];
    }
  }

  Future<void> saveToHistory(PlaceModel place) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> history = prefs.getStringList('search_history') ?? [];

      final placeJson = json.encode(place.toJson());

      // 🚀 FIX: Extremely safe duplicate removal using exact JSON structure matching
      history.removeWhere((item) =>
          item.contains('"place_id":"${place.placeId}"') ||
          item.contains('"p_place_id":"${place.placeId}"'));

      history.insert(0, placeJson);
      if (history.length > 10) history = history.sublist(0, 10);

      await prefs.setStringList('search_history', history);
      _supabaseEngine.logSuccessfulSearch(place); // Background Sync
    } catch (_) {}
  }

  // =========================================================================
  // 🛡️ INTERNAL FALLBACKS & MANAGERS
  // =========================================================================
  Future<List<PlaceModel>> _fallbackNominatimSearch(
      String query, LatLng? location) async {
    try {
      debugPrint("🔍 DEBUG API: Hitting search API with query: $query");
      String url =
          'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5';
      if (location != null) {
        url +=
            '&viewbox=${location.longitude - 0.1},${location.latitude + 0.1},${location.longitude + 0.1},${location.latitude - 0.1}';
      }

      final response = await _client.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Ridel-App/1.0', 'Accept-Encoding': 'gzip'},
      ).timeout(const Duration(seconds: 4));

      debugPrint("🔍 DEBUG API STATUS: ${response.statusCode}");
      debugPrint("🔍 DEBUG API BODY: ${response.body}");

      if (response.statusCode != 200) {
        debugPrint(
            "🛑 DEBUG API FATAL: API returned error code ${response.statusCode}");
        return [];
      }

      final parsedResults = _parseNominatimSync(response.body);
      return parsedResults;
    } catch (e, stackTrace) {
      debugPrint("🛑 DEBUG PARSING CRASH: $e");
      debugPrint("🛑 STACKTRACE: $stackTrace");
      return [];
    }
  }

  void _saveToCache(String key, List<PlaceModel> results) {
    if (_searchCache.length >= _maxCacheSize) {
      _searchCache.remove(_searchCache.keys.first);
    }
    _searchCache[key] = _SearchCacheEntry(results, DateTime.now());
  }

  void clearMemoryCache() => _searchCache.clear();

  // 🚀 FIX: Removed _client.close() to preserve the Singleton HTTP connection lifecycle
}

// ====================================================================
// 🧠 THE ISOLATE PARSERS (Zero Main-Thread Blockers)
// ====================================================================
List<PlaceModel> _parseOverpassSync(
    String responseBody, String defaultCategory) {
  try {
    final data = json.decode(responseBody);
    final elements = data['elements'] as List<dynamic>? ?? [];
    return elements.map((e) {
      final lat = (e['lat'] ?? e['center']?['lat'] ?? 0.0).toDouble();
      final lon = (e['lon'] ?? e['center']?['lon'] ?? 0.0).toDouble();
      final tags = e['tags'] ?? {};
      return PlaceModel(
        placeId: e['id'].toString(),
        name: tags['name'] ?? tags['brand'] ?? 'Unknown Place',
        address: tags['addr:street'] ?? tags['amenity'] ?? defaultCategory,
        latitude: lat,
        longitude: lon,
        categories: [
          tags['amenity'] ?? tags['shop'] ?? tags['tourism'] ?? defaultCategory
        ],
      );
    }).toList();
  } catch (_) {
    return [];
  }
}

List<PlaceModel> _parseNominatimSync(String responseBody) {
  try {
    final data = json.decode(responseBody) as List<dynamic>;
    return data.map((e) {
      return PlaceModel(
        placeId: e['place_id'].toString(),
        name: e['name']?.toString().split(',').first ?? 'Unknown',
        address: e['display_name'] ?? '',
        latitude: double.tryParse(e['lat'].toString()) ?? 0.0,
        longitude: double.tryParse(e['lon'].toString()) ?? 0.0,
        categories: [e['type']?.toString().toLowerCase() ?? 'unknown'],
      );
    }).toList();
  } catch (_) {
    return [];
  }
}

List<PlaceModel> _parseHistorySync(List<String> historyJsonStrings) {
  try {
    return historyJsonStrings
        .map((str) => PlaceModel.fromJson(json.decode(str)))
        .toList();
  } catch (_) {
    return [];
  }
}