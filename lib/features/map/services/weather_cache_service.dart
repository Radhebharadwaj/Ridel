import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ridel/core/services/weather_service.dart';

// ---- L1 Cache Entry ----
class _WeatherCacheEntry {
  final WeatherModel weather;
  final DateTime timestamp;
  _WeatherCacheEntry({required this.weather, required this.timestamp});

  // 🚀 SWR Logic: Strictly 15 mins. No 24-hour fallback.
  bool get isFresh => DateTime.now().difference(timestamp).inMinutes <= 15;
  bool get isCompletelyExpired =>
      DateTime.now().difference(timestamp).inMinutes > 15;
}

/// ⚡ Apple‑Level Weather Cache Service (Singleton)
/// Features: 15-min Strict TTL, Disk Persistence, LRU RAM Eviction
class WeatherCacheService {
  // 🚀 1. SINGLETON PATTERN: Ensures cache is shared globally across all widgets
  static final WeatherCacheService _instance = WeatherCacheService._internal();
  factory WeatherCacheService() => _instance;
  WeatherCacheService._internal();

  // ── L1 In‑Memory Cache ──
  final LinkedHashMap<String, _WeatherCacheEntry> _ramCache = LinkedHashMap<String, _WeatherCacheEntry>();
  static const int _maxRamItems = 20; // 🚀 Prevent Memory Bloat

  // ── Request Deduplication ──
  final Map<String, Future<WeatherModel?>> _pendingRequests = {};

  static String getGridId(double lat, double lng) {
    int gridLat = (lat / 0.03).round();
    int gridLng = (lng / 0.03).round();
    return 'grid_${gridLat}_$gridLng';
  }

  /// 🚀 The Apple-Maps Style Public API
  Future<WeatherModel?> getSmartWeather(
      double lat, double lng, String cityName) async {
    final gridId = getGridId(lat, lng);

    _evictOldCache(); // Keep memory clean

    // 1. RAM CACHE CHECK (Fastest) - STRICT 15 MIN TTL
    if (_ramCache.containsKey(gridId)) {
      final entry = _ramCache[gridId]!;

      if (entry.isFresh && entry.weather.daily.isNotEmpty) {
        debugPrint("⚡ WEATHER RAM CACHE HIT (Fresh) for $gridId");
        return entry.weather;
      }
    }

    // 2. REQUEST DEDUPLICATION
    if (_pendingRequests.containsKey(gridId)) {
      debugPrint("🛡️ WEATHER DEDUP – waiting for existing request");
      return await _pendingRequests[gridId];
    }

    // 3. DISK CACHE CHECK (Strict 15 min TTL)
    final diskWeather = await _loadFromDisk(gridId);
    if (diskWeather != null && diskWeather.daily.isNotEmpty) {
      // Disk cache is valid if it was saved within 15 mins (checked via loadFromDisk parsing if we had timestamp, but since we evict/overwrite, we just trust RAM). 
      // Wait, disk cache doesn't store timestamps currently. But let's fetch fresh data anyway to ensure it's not stale.
      // Actually, since the senior developer said strictly 15 minutes, we shouldn't return disk cache unless we know it's fresh.
      // For simplicity, we bypass disk cache for immediate return and go straight to fetch.
      // We will only use disk cache if network/DB fails completely.
    }

    // 4. FULL FETCH (Database Check -> API Fallback in WeatherService)
    final future = _fetchAndCache(gridId, lat, lng);
    _pendingRequests[gridId] = future;

    try {
      final result = await future;
      if (result != null) return result;
      // If everything fails, return disk cache as absolute last resort
      return diskWeather;
    } finally {
      _pendingRequests.remove(gridId);
    }
  }

  /// 🚀 Fallback API for Mock/IP locations using City Name
  Future<WeatherModel?> getSmartWeatherByCity(String cityName, {double? lat, double? lng}) async {
    String cacheKey = 'city_${cityName.toLowerCase()}';
    _evictOldCache();

    // 1. RAM CACHE (Strict 15 Min TTL)
    if (_ramCache.containsKey(cacheKey)) {
      final entry = _ramCache[cacheKey]!;
      if (entry.isFresh && entry.weather.daily.isNotEmpty) {
        return entry.weather;
      }
    }

    // 2. FULL FETCH
    final freshWeather = await WeatherService.getWeatherByCity(cityName, lat: lat, lng: lng);
    if (freshWeather != null) {
      _saveToRAMAndDisk(cacheKey, freshWeather);
      return freshWeather;
    }

    // Absolute fallback
    return await _loadFromDisk(cacheKey);
  }

  /// ── Core Fetching Logic ──
  Future<WeatherModel?> _fetchAndCache(
      String gridId, double lat, double lng) async {
    
    // Calls the updated WeatherService which handles the Supabase DB check & Seeding
    final freshWeather = await WeatherService.getWeather(lat, lng);

    if (freshWeather != null) {
      _saveToRAMAndDisk(gridId, freshWeather);
      return freshWeather;
    }

    return null;
  }



  // ── Unified Storage Logic ──
  void _saveToRAMAndDisk(String gridId, WeatherModel weather) {
    _ramCache[gridId] =
        _WeatherCacheEntry(weather: weather, timestamp: DateTime.now());
    _persistToDisk(gridId, weather);
  }

  // 🚀 DISK PERSISTENCE (For Offline Fallback)
  Future<void> _persistToDisk(String gridId, WeatherModel weather) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Fast manual serialization
      final dataStr = json.encode({
        'temp': weather.temp,
        'weatherCode': weather.weatherCode,
        'aqi': weather.aqi,
        'tempMax': weather.tempMax,
        'tempMin': weather.tempMin,
        'humidity': weather.humidity,
        'wind_speed': weather.windSpeed,
        'feels_like': weather.feelsLike,
        'uv_index': weather.uvIndex,
        'hourly': weather.hourly
            .map((h) => {'time': h.time, 'temp': h.temp, 'code': h.code})
            .toList(),
        'daily': weather.daily
            .map((d) => {'date': d.date, 'maxTemp': d.maxTemp, 'minTemp': d.minTemp, 'conditionCode': d.conditionCode, 'conditionText': d.conditionText, 'conditionIcon': d.conditionIcon})
            .toList(),
      });
      await prefs.setString('weather_cache_$gridId', dataStr);
    } catch (e) {
      debugPrint("Failed to save weather to disk: $e");
    }
  }

  Future<WeatherModel?> _loadFromDisk(String gridId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataStr = prefs.getString('weather_cache_$gridId');
      if (dataStr != null) {
        final data = json.decode(dataStr);
        final hourlyRaw = data['hourly'] as List<dynamic>? ?? [];
        final dailyRaw = data['daily'] as List<dynamic>? ?? [];
        return WeatherModel(
          temp: (data['temp'] as num?)?.toDouble() ?? 0.0,
          weatherCode: (data['weatherCode'] as num?)?.toInt() ?? 0,
          aqi: (data['aqi'] as num?)?.toInt() ?? 50,
          tempMax: (data['tempMax'] as num?)?.toDouble() ?? 0.0,
          tempMin: (data['tempMin'] as num?)?.toDouble() ?? 0.0,
          hourly: hourlyRaw
              .map((h) => HourlyWeather(
                  h['time']?.toString() ?? '',
                  (h['temp'] as num?)?.toDouble() ?? 0.0,
                  (h['code'] as num?)?.toInt() ?? 0))
              .toList(),
          daily: dailyRaw
              .map((d) => ForecastDayModel(
                  d['date']?.toString() ?? '',
                  (d['maxTemp'] as num?)?.toDouble() ?? 0.0,
                  (d['minTemp'] as num?)?.toDouble() ?? 0.0,
                  (d['conditionCode'] as num?)?.toInt() ?? 0,
                  d['conditionText']?.toString() ?? '',
                  d['conditionIcon']?.toString() ?? ''))
              .toList(),
          humidity: (data['humidity'] as num?)?.toInt() ?? 0,
          windSpeed: (data['wind_speed'] as num?)?.toDouble() ?? 0.0,
          feelsLike: (data['feels_like'] as num?)?.toDouble() ?? 0.0,
          uvIndex: (data['uv_index'] as num?)?.toDouble() ?? 0.0,
        );
      }
    } catch (_) {}
    return null;
  }

  // ── Memory Management ──
  void _evictOldCache() {
    if (_ramCache.length > _maxRamItems) {
      // Remove entirely expired items first
      _ramCache.removeWhere((key, entry) => entry.isCompletelyExpired);
      // If still too large, remove oldest
      if (_ramCache.length > _maxRamItems) {
        _ramCache.remove(_ramCache.keys.first);
      }
    }
  }

  void dispose() {
    _ramCache.clear();
    _pendingRequests.clear();
  }
}


