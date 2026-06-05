import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ridel/core/services/weather_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---- L1 Cache Entry ----
class _WeatherCacheEntry {
  final WeatherModel weather;
  final DateTime timestamp;
  _WeatherCacheEntry({required this.weather, required this.timestamp});

  // 🚀 SWR Logic: Fresh for 15 mins. Stale (but usable) up to 24 hours.
  bool get isFresh => DateTime.now().difference(timestamp).inMinutes < 15;
  bool get isCompletelyExpired =>
      DateTime.now().difference(timestamp).inHours > 24;
}

/// ⚡ Apple‑Level Weather Cache Service (Singleton)
/// Features: Stale-While-Revalidate, Disk Persistence, LRU RAM Eviction, Isolate Parsing
class WeatherCacheService {
  // 🚀 1. SINGLETON PATTERN: Ensures cache is shared globally across all widgets
  static final WeatherCacheService _instance = WeatherCacheService._internal();
  factory WeatherCacheService() => _instance;
  WeatherCacheService._internal();

  // ── L1 In‑Memory Cache ──
  final Map<String, _WeatherCacheEntry> _ramCache = {};
  static const int _maxRamItems = 20; // 🚀 Prevent Memory Bloat

  // ── Request Deduplication ──
  final Map<String, Future<WeatherModel?>> _pendingRequests = {};

  static String getGridId(double lat, double lng) {
    int gridLat = (lat / 0.03).round();
    int gridLng = (lng / 0.03).round();
    return 'grid_${gridLat}_$gridLng';
  }

  /// 🚀 The Apple-Maps Style Public API (Optimistic UI & SWR)
  Future<WeatherModel?> getSmartWeather(
      double lat, double lng, String cityName) async {
    final gridId = getGridId(lat, lng);

    _evictOldCache(); // Keep memory clean

    // 1. RAM CACHE CHECK (Fastest)
    if (_ramCache.containsKey(gridId)) {
      final entry = _ramCache[gridId]!;

      if (entry.isFresh && entry.weather.daily.isNotEmpty) {
        debugPrint("⚡ WEATHER RAM CACHE HIT (Fresh) for $gridId");
        return entry.weather;
      } else if (!entry.isCompletelyExpired && entry.weather.daily.isNotEmpty) {
        // 🚀 STALE-WHILE-REVALIDATE: Return old data instantly, fetch new in background
        debugPrint(
            "🔄 WEATHER SWR: Returning stale data, updating in background...");
        _fetchAndCache(gridId, cityName, lat, lng); // Fire & Forget
        return entry.weather;
      }
    }

    // 2. REQUEST DEDUPLICATION
    if (_pendingRequests.containsKey(gridId)) {
      debugPrint("🛡️ WEATHER DEDUP – waiting for existing request");
      return await _pendingRequests[gridId];
    }

    // 3. DISK CACHE CHECK (Offline Fallback)
    final diskWeather = await _loadFromDisk(gridId);
    if (diskWeather != null && diskWeather.daily.isNotEmpty) {
      // Load disk data into RAM
      _ramCache[gridId] = _WeatherCacheEntry(
          weather: diskWeather,
          timestamp: DateTime.now().subtract(const Duration(minutes: 20)));

      // Since disk data is likely stale, trigger background update (SWR)
      debugPrint(
          "💾 WEATHER DISK HIT: Returning offline data, updating in background...");
      _fetchAndCache(gridId, cityName, lat, lng); // Fire & Forget
      return diskWeather;
    }

    // 4. FULL FETCH (If completely empty)
    final future = _fetchAndCache(gridId, cityName, lat, lng);
    _pendingRequests[gridId] = future;

    try {
      return await future;
    } finally {
      _pendingRequests.remove(gridId);
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295; // Math.PI / 180
    final double a = 0.5 - math.cos((lat2 - lat1) * p) / 2 + 
        math.cos(lat1 * p) * math.cos(lat2 * p) * 
        (1 - math.cos((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a)); // distance in km
  }

  /// ── Core Fetching Logic ──
  Future<WeatherModel?> _fetchAndCache(
      String gridId, String cityName, double lat, double lng) async {
    try {
      // 1. DATABASE GEO-QUERY (Cache Check) & TTL Validation
      final threeHoursAgo = DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String();
      
      // Calculate a bounding box for ~4km radius to aggressively filter the DB query
      const double radiusKm = 4.0;
      const double latDelta = radiusKm / 111.0;
      final double lngDelta = radiusKm / (111.0 * math.cos(lat * math.pi / 180.0));

      final double minLat = lat - latDelta;
      final double maxLat = lat + latDelta;
      final double minLng = lng - lngDelta;
      final double maxLng = lng + lngDelta;

      final recentRecords = await Supabase.instance.client
          .from('weather_cache')
          .select()
          .gte('updated_at', threeHoursAgo)
          .gte('lat', minLat)
          .lte('lat', maxLat)
          .gte('lng', minLng)
          .lte('lng', maxLng);

      Map<String, dynamic>? closestRecord;
      double minDistance = 3.0; // 3km radius

      for (var record in recentRecords) {
        double rLat = record['lat'] is num ? (record['lat'] as num).toDouble() : double.tryParse(record['lat'].toString()) ?? 0.0;
        double rLng = record['lng'] is num ? (record['lng'] as num).toDouble() : double.tryParse(record['lng'].toString()) ?? 0.0;
        
        double dist = _calculateDistance(lat, lng, rLat, rLng);
        if (dist <= 3.0 && dist < minDistance) {
          minDistance = dist;
          closestRecord = record;
        }
      }

      if (closestRecord != null) {
        debugPrint("⚡ WEATHER DB CACHE HIT (Distance: ${minDistance.toStringAsFixed(2)}km)");
        final weatherDataStr = closestRecord['weather_data'];
        final Map<String, dynamic> weatherData = weatherDataStr is String ? json.decode(weatherDataStr) : weatherDataStr;
        
        final hourlyRaw = weatherData['hourly'] as List<dynamic>? ?? [];
        final dailyRaw = weatherData['daily'] as List<dynamic>? ?? [];
        
        final cachedWeather = WeatherModel(
          temp: (weatherData['temp'] as num?)?.toDouble() ?? 0.0,
          weatherCode: (weatherData['weatherCode'] as num?)?.toInt() ?? 0,
          aqi: (weatherData['aqi'] as num?)?.toInt() ?? 50,
          tempMax: (weatherData['tempMax'] as num?)?.toDouble() ?? 0.0,
          tempMin: (weatherData['tempMin'] as num?)?.toDouble() ?? 0.0,
          hourly: hourlyRaw.map((h) => HourlyWeather(h['time']?.toString() ?? '', (h['temp'] as num?)?.toDouble() ?? 0.0, (h['code'] as num?)?.toInt() ?? 0)).toList(),
          daily: dailyRaw.map((d) => DailyWeather(d['time']?.toString() ?? '', (d['maxTemp'] as num?)?.toDouble() ?? 0.0, (d['minTemp'] as num?)?.toDouble() ?? 0.0, (d['code'] as num?)?.toInt() ?? 0)).toList(),
          humidity: (weatherData['humidity'] as num?)?.toInt() ?? 0,
          windSpeed: (weatherData['wind_speed'] as num?)?.toDouble() ?? 0.0,
          feelsLike: (weatherData['feels_like'] as num?)?.toDouble() ?? 0.0,
          uvIndex: (weatherData['uv_index'] as num?)?.toDouble() ?? 0.0,
        );

        if (cachedWeather.windSpeed == 0.0 && cachedWeather.feelsLike == 0.0 && cachedWeather.uvIndex == 0.0) {
          debugPrint("⚠️ DB CACHE HAS ZERO-DATA. Bypassing and fetching fresh data.");
        } else {
          _saveToRAMAndDisk(gridId, cachedWeather);
          return cachedWeather;
        }
      }
    } catch (e) {
      debugPrint("⚠️ Supabase DB Error (Handled): $e");
    }

    // 2. CLIENT-SIDE API FETCH
    debugPrint("❌ DB CACHE MISS / EXPIRED. Fetching Fresh Weather from Live API...");
    final freshWeather = await WeatherService.getWeather(lat, lng);

    if (freshWeather != null) {
      _saveToRAMAndDisk(gridId, freshWeather);
      
      // 3. DATABASE SYNC (Cache Update) Background execution
      _pushToDatabase(lat, lng, freshWeather);
      
      return freshWeather;
    }

    // Fallback Live API on Exception
    final fallbackWeather = await WeatherService.getWeather(lat, lng);
    if (fallbackWeather != null) _saveToRAMAndDisk(gridId, fallbackWeather);
    return fallbackWeather;
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
            .map((d) => {'time': d.time, 'maxTemp': d.maxTemp, 'minTemp': d.minTemp, 'code': d.code})
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
          temp: data['temp'] ?? 0.0,
          weatherCode: data['weatherCode'] ?? 0,
          aqi: data['aqi'] ?? 50,
          tempMax: data['tempMax'] ?? 0.0,
          tempMin: data['tempMin'] ?? 0.0,
          hourly: hourlyRaw
              .map((h) => HourlyWeather(h['time'], h['temp'], h['code']))
              .toList(),
          daily: dailyRaw
              .map((d) => DailyWeather(d['time'], d['maxTemp'], d['minTemp'], d['code']))
              .toList(),
          humidity: data['humidity'] ?? 0,
          windSpeed: data['wind_speed'] ?? 0.0,
          feelsLike: data['feels_like'] ?? 0.0,
          uvIndex: data['uv_index'] ?? 0.0,
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

  // ── Background save to Database ──
  Future<void> _pushToDatabase(double lat, double lng, WeatherModel weather) async {
    try {
      final weatherJson = {
        'temp': weather.temp,
        'weatherCode': weather.weatherCode,
        'aqi': weather.aqi,
        'tempMax': weather.tempMax,
        'tempMin': weather.tempMin,
        'humidity': weather.humidity,
        'wind_speed': weather.windSpeed,
        'feels_like': weather.feelsLike,
        'uv_index': weather.uvIndex,
        'hourly': weather.hourly.map((h) => {'time': h.time, 'temp': h.temp, 'code': h.code}).toList(),
        'daily': weather.daily.map((d) => {'time': d.time, 'maxTemp': d.maxTemp, 'minTemp': d.minTemp, 'code': d.code}).toList(),
      };

      await Supabase.instance.client.from('weather_cache').insert({
        'lat': lat,
        'lng': lng,
        'weather_data': weatherJson,
        'humidity': weather.humidity,
        'wind_speed': weather.windSpeed,
        'feels_like': weather.feelsLike,
        'uv_index': weather.uvIndex,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      debugPrint("✅ Saved new weather to Supabase weather_cache.");
    } catch (e) {
      debugPrint("⚠️ Failed to sync weather to Supabase: $e");
    }
  }

  void dispose() {
    _ramCache.clear();
    _pendingRequests.clear();
  }
}


