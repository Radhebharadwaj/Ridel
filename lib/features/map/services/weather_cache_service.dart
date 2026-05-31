import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:http/http.dart' as http;
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

  static const String _baseUrl = 'https://pixra.pages.dev/api';
  static const String _secretKey = 'RIDEL_SUPER_SECRET_CRON_KEY_2026';

  static final http.Client _apiClient = http.Client();
  static const Duration _timeout = Duration(seconds: 4);

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

  /// ── Core Fetching Logic ──
  Future<WeatherModel?> _fetchAndCache(
      String gridId, String cityName, double lat, double lng) async {
    try {
      final response = await _apiClient.get(
        Uri.parse('$_baseUrl/weather/get-weather?grid_id=$gridId'),
        headers: {
          'Authorization': 'Bearer $_secretKey',
          'Content-Type': 'application/json',
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        if (jsonResponse['success'] == true && jsonResponse['data'] != null) {
          final dbData = jsonResponse['data'] as Map<String, dynamic>;

          DateTime lastUpdated = DateTime.now();
          if (dbData['last_updated'] != null) {
            String timeStr = dbData['last_updated'].toString();
            if (!timeStr.endsWith('Z') && !timeStr.contains('+')) {
              timeStr += 'Z';
            }
            try {
              lastUpdated = DateTime.parse(timeStr).toLocal();
            } catch (_) {
              lastUpdated = DateTime.now().subtract(const Duration(hours: 2));
            }
          }

          if (DateTime.now().difference(lastUpdated).inMinutes < 60) {
            // 🚀 ISOLATE PARSING
            final hourlyJsonString =
                dbData['hourly_forecast']?.toString() ?? '';
            final highLowString = dbData['high_low']?.toString() ?? '';
            final dailyJsonString = dbData['daily_forecast']?.toString() ?? '';

            final parsedData = await Isolate.run(() =>
                _parseHourlyAndHighLowSync(hourlyJsonString, highLowString, dailyJsonString));

            final weather = WeatherModel(
              temp: (dbData['current_temp'] as num?)?.toDouble() ?? 0.0,
              weatherCode:
                  int.tryParse(dbData['condition']?.toString() ?? '0') ?? 0,
              aqi: int.tryParse(dbData['aqi']?.toString() ?? '50') ?? 50,
              tempMax: parsedData.tMax,
              tempMin: parsedData.tMin,
              hourly: parsedData.hourly,
              daily: parsedData.daily,
              humidity: 0,
              windSpeed: 0.0,
              feelsLike: 0.0,
            );

            if (parsedData.daily.isNotEmpty) {
              _saveToRAMAndDisk(gridId, weather);
              return weather;
            } else {
              debugPrint("❌ CLOUDFLARE HAS NO DAILY DATA. Forcing Live API...");
            }
          }
        }
      }

      // Cloudflare missed or expired -> Live API
      debugPrint(
          "❌ CACHE MISS / EXPIRED. Fetching Fresh Weather from Live API...");
      final freshWeather = await WeatherService.getWeather(lat, lng);

      if (freshWeather != null) {
        _saveToRAMAndDisk(gridId, freshWeather);
        _pushToCloudflareD1(
            gridId, cityName, freshWeather); // Async Background Save
        return freshWeather;
      }
    } catch (e) {
      debugPrint("⚠️ Cloudflare Error (Handled): $e");
      // Fallback Live API on Exception
      final fallbackWeather = await WeatherService.getWeather(lat, lng);
      if (fallbackWeather != null) _saveToRAMAndDisk(gridId, fallbackWeather);
      return fallbackWeather;
    }
    return null;
  }

  // ── Isolate helper ──
  static _ParsedWeather _parseHourlyAndHighLowSync(
      String hourlyJson, String highLowStr, String dailyJson) {
    List<HourlyWeather> hourlyList = [];
    if (hourlyJson.isNotEmpty) {
      try {
        final List<dynamic> raw = json.decode(hourlyJson);
        hourlyList = raw
            .map((item) => HourlyWeather(
                  item['time']?.toString() ?? '',
                  (item['temp'] as num?)?.toDouble() ?? 0.0,
                  (item['code'] as num?)?.toInt() ?? 0,
                ))
            .toList();
      } catch (_) {}
    }

    List<DailyWeather> dailyList = [];
    if (dailyJson.isNotEmpty) {
      try {
        final List<dynamic> rawDaily = json.decode(dailyJson);
        dailyList = rawDaily.map((item) {
          try {
            return DailyWeather(
              item['time']?.toString() ?? '',
              (item['maxTemp'] as num?)?.toDouble() ?? 0.0,
              (item['minTemp'] as num?)?.toDouble() ?? 0.0,
              (item['code'] as num?)?.toInt() ?? 0,
            );
          } catch (err) {
            debugPrint("Error parsing individual forecast day: $err");
            return null;
          }
        }).whereType<DailyWeather>().toList();
      } catch (e) {
        debugPrint("Error parsing daily JSON: $e");
      }
    }

    double tMax = 0.0, tMin = 0.0;
    if (highLowStr.isNotEmpty) {
      final parts = highLowStr.split(',');
      if (parts.length == 2) {
        tMax = double.tryParse(parts[0]) ?? 0.0;
        tMin = double.tryParse(parts[1]) ?? 0.0;
      }
    }
    return _ParsedWeather(hourly: hourlyList, daily: dailyList, tMax: tMax, tMin: tMin);
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
          humidity: 0,
          windSpeed: 0.0,
          feelsLike: 0.0,
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

  // ── Background save to Cloudflare ──
  Future<void> _pushToCloudflareD1(
      String gridId, String cityName, WeatherModel weather) async {
    final user = Supabase.instance.client.auth.currentUser;
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (user?.id == null || token == null) return;

    try {
      final hourlyJson = json.encode(weather.hourly
          .map((h) => {'time': h.time, 'temp': h.temp, 'code': h.code})
          .toList());
      final dailyJson = json.encode(weather.daily
          .map((d) => {'time': d.time, 'maxTemp': d.maxTemp, 'minTemp': d.minTemp, 'code': d.code})
          .toList());
      final body = {
        'grid_id': gridId,
        'city_name': cityName,
        'current_temp': weather.temp,
        'condition': weather.weatherCode.toString(),
        'aqi': weather.aqi.toString(),
        'high_low': '${weather.tempMax},${weather.tempMin}',
        'hourly_forecast': hourlyJson,
        'daily_forecast': dailyJson,
      };

      await _apiClient
          .post(
            Uri.parse('$_baseUrl/cron/update-weather'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token'
            },
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  void dispose() {
    _ramCache.clear();
    _pendingRequests.clear();
  }
}

class _ParsedWeather {
  final List<HourlyWeather> hourly;
  final List<DailyWeather> daily;
  final double tMax;
  final double tMin;
  _ParsedWeather(
      {required this.hourly, required this.daily, required this.tMax, required this.tMin});
}
