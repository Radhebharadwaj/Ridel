import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ridel/features/map/models/place_model.dart';

// =========================================================================
// 🚀 1. The Unified Data Model (Apple Maps Style Rich Data)
// =========================================================================
class EnrichedPlaceDetails {
  final String? wikiSummary;
  final String? wikiImageUrl;
  final String? wikiArticleUrl;
  final String? osmPhone;
  final String? osmOpeningHours;
  final String? osmWebsite;

  EnrichedPlaceDetails({
    this.wikiSummary,
    this.wikiImageUrl,
    this.wikiArticleUrl,
    this.osmPhone,
    this.osmOpeningHours,
    this.osmWebsite,
  });

  bool get isEmpty =>
      wikiSummary == null &&
      osmPhone == null &&
      osmOpeningHours == null &&
      osmWebsite == null;
}

// =========================================================================
// 🧠 2. The Unified Enrichment Service (Singleton)
// =========================================================================
class PlaceEnrichmentService {
  static final PlaceEnrichmentService _instance =
      PlaceEnrichmentService._internal();
  factory PlaceEnrichmentService() => _instance;
  PlaceEnrichmentService._internal();

  // 🚀 FIX: Persistent Client bound to Singleton. Disposed properly when app closes.
  final http.Client _apiClient = http.Client();
  static const Duration _apiTimeout = Duration(seconds: 4);

  // 🚀 FIX: L1 RAM Caches (Max 20 items to prevent memory bloat)
  final LinkedHashMap<String, EnrichedPlaceDetails> _detailsCache =
      LinkedHashMap();
  final LinkedHashMap<String, PlaceModel> _geocodeCache = LinkedHashMap();
  static const int _maxCacheSize = 20;

  // =========================================================================
  // 🌍 1. The "Rich Card" Fetcher (Combines Wiki + OSM)
  // =========================================================================
  Future<EnrichedPlaceDetails?> getRichPlaceDetails(
      String placeName, double lat, double lon) async {
    final trimmed = placeName.trim().toLowerCase();
    if (trimmed == 'dropped pin' || trimmed.contains('fetching')) return null;

    final cacheKey = "${lat.toStringAsFixed(3)}_${lon.toStringAsFixed(3)}";

    if (_detailsCache.containsKey(cacheKey)) {
      debugPrint("⚡ Place Details: RAM Cache Hit!");
      final entry = _detailsCache.remove(cacheKey)!;
      _detailsCache[cacheKey] = entry; // LRU Bump
      return entry;
    }

    // 🚀 FIX: Fetch both Wikipedia and OSM concurrently for maximum speed
    final responses = await Future.wait([
      _fetchWikiDetails(placeName),
      _fetchOSMDetails(lat, lon),
    ]);

    final wiki = responses[0];
    final osm = responses[1];

    final result = EnrichedPlaceDetails(
      wikiSummary: wiki?['summary'],
      wikiImageUrl: wiki?['imageUrl'],
      wikiArticleUrl: wiki?['articleUrl'],
      osmPhone: osm?['phone'],
      osmOpeningHours: osm?['hours'],
      osmWebsite: osm?['website'],
    );

    if (!result.isEmpty) {
      _saveToCache(_detailsCache, cacheKey, result);
      return result;
    }
    return null;
  }

  // =========================================================================
  // 📍 2. Ola Reverse Geocoding (Safe Fallback)
  // =========================================================================
  Future<PlaceModel> reverseGeocode(double lat, double lng) async {
    final cacheKey = "${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}";

    if (_geocodeCache.containsKey(cacheKey)) {
      return _geocodeCache[cacheKey]!;
    }

    final url = Uri.parse(
        'https://ridel.ridel.workers.dev/api/maps/places/v1/reverse-geocode?latlng=$lat,$lng');

    try {
      final response = await _fetchWithRetry(url);
      if (response != null && response.statusCode == 200) {
        final PlaceModel? place = await compute(
            _parseOlaReverseSyncWrapper, {'body': response.body, 'lat': lat, 'lng': lng});
        if (place != null) {
          _saveToCache(_geocodeCache, cacheKey, place);
          return place;
        }
      }
    } catch (e) {
      debugPrint("⚠️ Reverse Geocoding Error: $e");
    }
    return _createFallbackPin(lat, lng);
  }

  // =========================================================================
  // 🛡️ INTERNAL API ENGINES
  // =========================================================================

  Future<Map<String, dynamic>?> _fetchWikiDetails(String placeName) async {
    try {
      // 🚀 FIX: Smart Wikipedia Fallback Chain
      // Attempt 1: Full Name (e.g., "Lal Qila, Delhi")
      String query = Uri.encodeComponent(placeName.trim().replaceAll(' ', '_'));
      var response = await _fetchWithRetry(Uri.parse(
          'https://en.wikipedia.org/api/rest_v1/page/summary/$query'));

      // Attempt 2: If 404, fallback to first part (e.g., "Lal Qila")
      if (response == null || response.statusCode == 404) {
        String baseName =
            placeName.split(',').first.trim().replaceAll(' ', '_');
        query = Uri.encodeComponent(baseName);
        response = await _fetchWithRetry(Uri.parse(
            'https://en.wikipedia.org/api/rest_v1/page/summary/$query'));
      }

      if (response != null && response.statusCode == 200) {
        return await compute(_parseWikiSync, response.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _fetchOSMDetails(double lat, double lon) async {
    try {
      // 🚀 FIX: OSM Query strictly excludes roads/highways to avoid grabbing street names instead of buildings
      final query =
          '''[out:json][timeout:5];(nwr(around:30, $lat, $lon)["name"][!"highway"];);out tags limit 1;''';
      final url = Uri.parse('https://overpass-api.de/api/interpreter');

      final response = await _apiClient.post(
        url,
        body: query,
        headers: {'User-Agent': 'RidelApp/1.0 (contact@ridelapp.com)'},
      ).timeout(_apiTimeout);

      if (response.statusCode == 200) {
        return await compute(_parseOSMSync, response.body);
      }
    } catch (_) {}
    return null;
  }

  // 🚀 FIX: Network Retry Interceptor (Handles temporary 5xx errors or network drops)
  Future<http.Response?> _fetchWithRetry(Uri url, {int retries = 1}) async {
    int attempt = 0;
    while (attempt <= retries) {
      try {
        final response = await _apiClient.get(url, headers: {
          'Accept': 'application/json',
          'Accept-Language': 'en,hi', // 🚀 Localization support added
          'User-Agent':
              'RidelApp/1.0 (contact@ridelapp.com)' // 🚀 Added everywhere
        }).timeout(_apiTimeout);

        if (response.statusCode == 200 || response.statusCode == 404) {
          return response;
        }
      } catch (_) {}
      attempt++;
      if (attempt <= retries) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return null;
  }

  // =========================================================================
  // 🧹 MEMORY MANAGEMENT
  // =========================================================================



  void _saveToCache<T>(LinkedHashMap<String, T> cache, String key, T item) {
    if (cache.length >= _maxCacheSize) cache.remove(cache.keys.first);
    cache[key] = item;
  }

  void dispose() {
    _apiClient.close(); // 🚀 FIX: Prevents Socket Leaks
    _detailsCache.clear();
    _geocodeCache.clear();
  }

  static PlaceModel _createFallbackPin(double lat, double lng) {
    return PlaceModel(
      placeId: 'dropped_pin_${lat.toStringAsFixed(3)}',
      name: "Dropped Pin",
      address: "Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}",
      latitude: lat,
      longitude: lng,
      categories: const ['Map Pin'], // 🚀 FIX: Aligned with updated PlaceModel
    );
  }

  // ====================================================================
  // 🧠 THE ISOLATE PARSERS (Zero UI Jank)
  // ====================================================================

  static Map<String, dynamic>? _parseWikiSync(String responseBody) {
    try {
      final data = json.decode(responseBody) as Map<String, dynamic>;
      if (data['type'] == 'disambiguation') return null;

      String? imageUrl =
          data['originalimage']?['source'] ?? data['thumbnail']?['source'];
      // 🚀 FIX: SVG Crash Prevention handled in Isolate before reaching UI
      if (imageUrl != null && imageUrl.toLowerCase().endsWith('.svg')) {
        imageUrl = null;
      }

      return {
        'summary': data['extract'],
        'imageUrl': imageUrl,
        'articleUrl': data['content_urls']?['desktop']?['page'],
      };
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _parseOSMSync(String responseBody) {
    try {
      final data = json.decode(responseBody) as Map<String, dynamic>;
      if (data['elements'] != null && data['elements'].isNotEmpty) {
        final tags = data['elements'][0]['tags'];
        if (tags != null) {
          return {
            'phone': tags['phone'] ?? tags['contact:phone'],
            'hours': tags['opening_hours'],
            'website': tags['website'] ?? tags['contact:website'],
          };
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static PlaceModel? _parseOlaReverseSyncWrapper(Map<String, dynamic> args) {
    return _parseOlaReverseSync(args['body'], args['lat'], args['lng']);
  }

  static PlaceModel? _parseOlaReverseSync(
      String responseBody, double lat, double lng) {
    try {
      final data = json.decode(responseBody) as Map<String, dynamic>;
      if (data['results'] != null && data['results'].isNotEmpty) {
        final result = data['results'][0];

        String name = result['name'] ?? '';
        if (name.isEmpty || name.contains(',')) {
          name = result['address_components']?.firstWhere(
                  (comp) => comp['types'].contains('neighborhood'),
                  orElse: () => {'short_name': ''})['short_name'] ??
              '';
          if (name.isEmpty) {
             // 🚀 CRITICAL FIX: Prevent Null Pointer Crash on empty map zones
             name = (result['formatted_address'] as String?)?.split(',').first ?? 'Dropped Pin';
          }
        }

        return PlaceModel(
          placeId:
              result['place_id'] ?? 'dropped_pin_${lat.toStringAsFixed(3)}',
          name: name,
          address: result['formatted_address'] ?? "Dropped Pin",
          latitude: lat,
          longitude: lng,
          categories: const ['Location'], // 🚀 FIX: Valid List format
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
