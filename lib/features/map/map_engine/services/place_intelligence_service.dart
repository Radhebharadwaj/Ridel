import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/offline_service.dart';
import '../services/network_fallback_service.dart';

class PlaceIntelligenceService {
  final http.Client _client;
  final OfflineService _offlineService;
  final NetworkFallbackService _fallbackService;

  static const String _edgeBackendUrl = 'https://api.ridel.com/v1';

  final Map<String, _CacheEntry> _ramCache = {};
  static const Duration _defaultTTL = Duration(hours: 24);
  bool _diskCacheLoaded = false;

  final Map<String, Future<PlaceIntelligence?>> _pendingRequests = {};

  PlaceIntelligenceService({
    http.Client? client,
    OfflineService? offlineService,
    NetworkFallbackService? fallbackService,
  })  : _client = client ?? http.Client(),
        _offlineService = offlineService ?? OfflineService(),
        _fallbackService = fallbackService ?? NetworkFallbackService();

  // ────────── Public API ──────────

  Future<PlaceIntelligence?> fetchPlaceDetails(
    String placeName,
    LatLng location, {
    int radiusMeters = 500,
    Duration ttl = _defaultTTL,
  }) async {
    final cacheKey = _cacheKey(placeName, location, radiusMeters);

    // 1. RAM cache hit
    if (_ramCache.containsKey(cacheKey)) {
      final entry = _ramCache[cacheKey]!;
      if (!entry.isExpired(ttl)) {
        return entry.data;
      }
    }

    // 2. Disk cache hit
    if (!_diskCacheLoaded) await _loadDiskCache();
    final diskEntry = await _getDiskCache(cacheKey);
    if (diskEntry != null && !diskEntry.isExpired(ttl)) {
      _ramCache[cacheKey] = diskEntry;
      return diskEntry.data;
    }

    // 3. Offline check
    if (!_offlineService.isOnlineSync) {
      debugPrint('📵 Offline – no network & no cache for $placeName');
      return null;
    }

    // 4. Deduplicate in‑flight requests
    if (_pendingRequests.containsKey(cacheKey)) {
      return _pendingRequests[cacheKey];
    }

    final future = _performNetworkFetch(placeName, location, radiusMeters, ttl);
    _pendingRequests[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _pendingRequests.remove(cacheKey);
    }
  }

  Future<Map<String, PlaceIntelligence?>> fetchBatch(
    List<PlaceQuery> queries, {
    Duration ttl = _defaultTTL,
  }) async {
    final results = <String, PlaceIntelligence?>{};

    final List<Map<String, dynamic>> toFetch = [];
    for (final q in queries) {
      final cacheKey = _cacheKey(q.placeName, q.location, q.radiusMeters);
      final cached = await _getFromCache(cacheKey, ttl);
      if (cached != null) {
        results[cacheKey] = cached;
      } else {
        toFetch.add({
          'name': q.placeName,
          'lat': q.location.latitude,
          'lng': q.location.longitude,
          'radius': q.radiusMeters,
        });
      }
    }

    if (toFetch.isEmpty) return results;
    if (!_offlineService.isOnlineSync) return results;

    try {
      final uri = Uri.parse('$_edgeBackendUrl/places/batch');
      final response = await _fallbackService.requestWithFallback(
        endpoint: uri,
        request: () => _client
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'queries': toFetch}),
            )
            .timeout(const Duration(seconds: 8)),
        fallback: (uri) async => http.Response('{}', 200),
        cacheKey: null,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> batchData = await _runMaybeInIsolate(
          () => json.decode(response.body) as Map<String, dynamic>,
        );
        for (final entry in batchData.entries) {
          final key = entry.key;
          if (entry.value != null) {
            final intelligence =
                PlaceIntelligence.fromJson(entry.value as Map<String, dynamic>);
            await _updateCache(key, intelligence, ttl);
            results[key] = intelligence;
          } else {
            results[key] = null;
          }
        }
      }
    } catch (e) {
      debugPrint('Batch fetch failed: $e');
    }
    return results;
  }

  Future<PlaceIntelligence?> refreshPlace(
    String placeName,
    LatLng location, {
    int radiusMeters = 500,
  }) async {
    final cacheKey = _cacheKey(placeName, location, radiusMeters);
    _ramCache.remove(cacheKey);
    await _removeDiskCache(cacheKey);
    return fetchPlaceDetails(placeName, location, radiusMeters: radiusMeters);
  }

  void dispose() {
    _client.close();
    _ramCache.clear();
    _pendingRequests.clear();
  }

  static Future<T> _runMaybeInIsolate<T>(T Function() callback) async {
    if (kIsWeb) {
      return callback();
    }
    return await Isolate.run(callback);
  }

  // ────────── Private Helpers ──────────

  Future<PlaceIntelligence?> _performNetworkFetch(
    String placeName,
    LatLng location,
    int radiusMeters,
    Duration ttl,
  ) async {
    final safeQuery = Uri.encodeComponent(placeName);
    final uri = Uri.parse(
      '$_edgeBackendUrl/places/search'
      '?q=$safeQuery'
      '&lat=${location.latitude}'
      '&lng=${location.longitude}'
      '&radius=$radiusMeters',
    );

    try {
      final response = await _fallbackService.requestWithFallback(
        endpoint: uri,
        request: () => _client.get(uri).timeout(const Duration(seconds: 3)),
        fallback: (uri) => Future.value(http.Response('{}', 200)),
        cacheKey: null,
      );

      if (response.statusCode == 200) {
        final data = await _runMaybeInIsolate(
          () => json.decode(response.body) as Map<String, dynamic>,
        );
        if (data.isEmpty) return null;
        final intelligence = PlaceIntelligence.fromJson(data);
        await _updateCache(
            _cacheKey(placeName, location, radiusMeters), intelligence, ttl);
        return intelligence;
      }
    } catch (e) {
      debugPrint('Network fetch failed for $placeName: $e');
    }
    return null;
  }

  Future<void> _updateCache(
      String key, PlaceIntelligence data, Duration ttl) async {
    final entry = _CacheEntry(data: data, storedAt: DateTime.now());
    _ramCache[key] = entry;
    _persistToDisk(key, entry);
  }

  Future<void> _persistToDisk(String key, _CacheEntry entry) async {
    try {
      final jsonStr = await _runMaybeInIsolate(() => json.encode(entry.toJson()));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('place_cache_$key', jsonStr);
    } catch (e) {
      debugPrint('Failed to persist place cache: $e');
    }
  }

  Future<PlaceIntelligence?> _getFromCache(String key, Duration ttl) async {
    if (_ramCache.containsKey(key)) {
      final entry = _ramCache[key]!;
      if (!entry.isExpired(ttl)) return entry.data;
    }
    if (!_diskCacheLoaded) await _loadDiskCache();
    final diskEntry = await _getDiskCache(key);
    if (diskEntry != null && !diskEntry.isExpired(ttl)) {
      _ramCache[key] = diskEntry;
      return diskEntry.data;
    }
    return null;
  }

  Future<void> _loadDiskCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('place_cache_'));
    for (final key in keys) {
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) continue;
      try {
        final data = await _runMaybeInIsolate(
            () => json.decode(jsonStr) as Map<String, dynamic>);
        final entry = _CacheEntry.fromJson(data);
        final cacheKey = key.substring('place_cache_'.length);
        _ramCache[cacheKey] = entry;
      } catch (_) {
        await prefs.remove(key);
      }
    }
    _diskCacheLoaded = true;
  }

  Future<_CacheEntry?> _getDiskCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('place_cache_$key');
    if (jsonStr == null) return null;
    try {
      final data = await _runMaybeInIsolate(
          () => json.decode(jsonStr) as Map<String, dynamic>);
      return _CacheEntry.fromJson(data);
    } catch (_) {
      await prefs.remove('place_cache_$key');
      return null;
    }
  }

  Future<void> _removeDiskCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('place_cache_$key');
  }

  String _cacheKey(String placeName, LatLng loc, int radius) =>
      '${placeName}_${loc.latitude.toStringAsFixed(5)}_${loc.longitude.toStringAsFixed(5)}_$radius';
}

// ───── Helper query struct for batch ─────
class PlaceQuery {
  final String placeName;
  final LatLng location;
  final int radiusMeters;
  PlaceQuery(this.placeName, this.location, {this.radiusMeters = 500});
}

// ───── Cache entry wrapper (FIXED TIMESTAMP LOGIC) ─────
class _CacheEntry {
  final PlaceIntelligence data;
  final DateTime storedAt;
  _CacheEntry({required this.data, required this.storedAt});

  bool isExpired(Duration ttl) => DateTime.now().difference(storedAt) > ttl;

  Map<String, dynamic> toJson() => {
        'data': data.toJson(),
        'storedAt': storedAt.millisecondsSinceEpoch,
      };

  factory _CacheEntry.fromJson(Map<String, dynamic> json) => _CacheEntry(
        data: PlaceIntelligence.fromJson(json['data'] as Map<String, dynamic>),
        storedAt: DateTime.fromMillisecondsSinceEpoch(json['storedAt'] as int),
      );
}

// ───── Flexible Data Model ─────
class PlaceIntelligence {
  final String title;
  final String summary;
  final List<String> imageUrls;
  final String? openingHours;
  final double? rating;
  final String? address;
  final String? phone;
  final String? website;
  final String? priceLevel;
  final Map<String, dynamic>? extra;

  PlaceIntelligence({
    required this.title,
    required this.summary,
    required this.imageUrls,
    this.openingHours,
    this.rating,
    this.address,
    this.phone,
    this.website,
    this.priceLevel,
    this.extra,
  });

  factory PlaceIntelligence.fromJson(Map<String, dynamic> json) {
    return PlaceIntelligence(
      title: json['title'] ?? 'Unknown Place',
      summary: json['summary'] ?? '',
      imageUrls: List<String>.from(json['imageUrls'] ?? []),
      openingHours: json['openingHours'],
      rating: (json['rating'] as num?)?.toDouble(),
      address: json['address'],
      phone: json['phone'],
      website: json['website'],
      priceLevel: json['priceLevel'],
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'summary': summary,
        'imageUrls': imageUrls,
        'openingHours': openingHours,
        'rating': rating,
        'address': address,
        'phone': phone,
        'website': website,
        'priceLevel': priceLevel,
        'extra': extra,
      };
}
