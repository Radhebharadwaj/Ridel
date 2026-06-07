import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

// 🚀 1. SPEED OPTIMIZATION: Global Persistent HTTP Client & Timeout
final http.Client _apiClient = http.Client();
const Duration _apiTimeout = Duration(seconds: 5);

// 🚀 2. NAYA CLASS: Real 7-Day Forecast ko store karne ke liye
class DailyWeather {
  final String time;
  final double maxTemp;
  final double minTemp;
  final int code;
  DailyWeather(this.time, this.maxTemp, this.minTemp, this.code);
}

class HourlyWeather {
  final String time;
  final double temp;
  final int code;
  HourlyWeather(this.time, this.temp, this.code);
}

class WeatherModel {
  final double temp;
  final int weatherCode;
  final int aqi;
  final double tempMax;
  final double tempMin;
  final List<HourlyWeather> hourly;
  final List<DailyWeather> daily; // 🚀 Real 7-day data support added
  final int humidity;
  final double windSpeed;
  final double feelsLike;
  final double uvIndex;

  WeatherModel({
    required this.temp,
    required this.weatherCode,
    required this.aqi,
    required this.tempMax,
    required this.tempMin,
    required this.hourly,
    this.daily =
        const [], // 🚀 Default empty rakha hai taaki Cache Service crash na kare
    required this.humidity,
    required this.windSpeed,
    required this.feelsLike,
    required this.uvIndex,
  });
}

class WeatherService {
  static final ValueNotifier<WeatherModel?> currentWeather = ValueNotifier(null);
  static Future<List<dynamic>?> _queryD1(String sql, [List<dynamic>? params]) async {
    if (kIsWeb) {
      debugPrint("🌐 Web Detected: Bypassing D1 Cache to avoid CORS.");
      return null;
    }
    
    final url = Uri.parse('https://ridel.ridel.workers.dev/api/weather');
    final response = await _apiClient.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({"sql": sql, "params": params ?? []}),
    ).timeout(_apiTimeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['success'] == true) {
        return json['results'] as List<dynamic>?;
      }
      throw Exception('D1 Query Error: ${json['error'] ?? json['errors']}');
    }
    throw Exception('D1 HTTP Error: ${response.statusCode}');
  }

  static Future<WeatherModel?> getWeather(double lat, double lon) async {
    try {
      // 🚀 1. GLOBAL DB CHECK (Community-Driven Cache)
      int gridLat = (lat / 0.03).round();
      int gridLng = (lon / 0.03).round();
      String gridId = 'grid_${gridLat}_$gridLng';

      final results = await _queryD1('SELECT * FROM weather_grid_cache WHERE grid_id = ?', [gridId]);

      if (results != null && results.isNotEmpty) {
        final closestRecord = results.first;
        debugPrint("⚡ GLOBAL DB CACHE HIT for grid: $gridId");
        
        final highLowRaw = closestRecord['high_low'];
        Map<String, dynamic> highLow = {};
        if (highLowRaw is String) {
          highLow = jsonDecode(highLowRaw);
        } else if (highLowRaw is Map) {
          highLow = Map<String, dynamic>.from(highLowRaw);
        }
        
        final hourlyRawStr = closestRecord['hourly_forecast'];
        List<dynamic> hourlyRaw = [];
        if (hourlyRawStr is String) {
          hourlyRaw = jsonDecode(hourlyRawStr);
        } else if (hourlyRawStr is List) {
          hourlyRaw = hourlyRawStr;
        }

        final dailyRawStr = closestRecord['daily_forecast'];
        List<dynamic> dailyRaw = [];
        if (dailyRawStr is String) {
          dailyRaw = jsonDecode(dailyRawStr);
        } else if (dailyRawStr is List) {
          dailyRaw = dailyRawStr;
        }

        final cachedWeather = WeatherModel(
          temp: (closestRecord['current_temp'] as num?)?.toDouble() ?? 0.0,
          weatherCode: (closestRecord['condition'] as num?)?.toInt() ?? 0,
          aqi: (closestRecord['aqi'] as num?)?.toInt() ?? 50,
          tempMax: (highLow['max'] as num?)?.toDouble() ?? 0.0,
          tempMin: (highLow['min'] as num?)?.toDouble() ?? 0.0,
          hourly: hourlyRaw.map((h) => HourlyWeather(h['time']?.toString() ?? '', (h['temp'] as num?)?.toDouble() ?? 0.0, (h['code'] as num?)?.toInt() ?? 0)).toList(),
          daily: dailyRaw.map((d) => DailyWeather(d['time']?.toString() ?? '', (d['maxTemp'] as num?)?.toDouble() ?? 0.0, (d['minTemp'] as num?)?.toDouble() ?? 0.0, (d['code'] as num?)?.toInt() ?? 0)).toList(),
          humidity: (closestRecord['humidity'] as num?)?.toInt() ?? 0,
          windSpeed: (closestRecord['wind_speed'] as num?)?.toDouble() ?? 0.0,
          feelsLike: (closestRecord['feels_like'] as num?)?.toDouble() ?? 0.0,
          uvIndex: (closestRecord['uv_index'] as num?)?.toDouble() ?? 0.0,
        );
        currentWeather.value = cachedWeather;
        return cachedWeather;
      }
    } catch (e) {
      debugPrint("⚠️ D1 Cache Error: $e");
    }

    // 🚀 2. API FALLBACK
    debugPrint("❌ DB CACHE MISS / EXPIRED. Fetching Fresh Weather from Open-Meteo...");
    try {
      final weatherUrl = Uri.parse(
          "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code,is_day,relative_humidity_2m,wind_speed_10m,apparent_temperature,uv_index&daily=weather_code,temperature_2m_max,temperature_2m_min&hourly=temperature_2m,weather_code&timezone=auto&forecast_days=7");
      final aqiUrl = Uri.parse(
          "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=$lat&longitude=$lon&current=us_aqi");

      final responses = await Future.wait([
        _apiClient.get(weatherUrl).timeout(_apiTimeout),
        _apiClient.get(aqiUrl).timeout(_apiTimeout)
      ]);

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final wData = json.decode(responses[0].body);
        final aData = json.decode(responses[1].body);

        List<HourlyWeather> hourlyList = [];
        final hours = wData['hourly']?['time'] as List?;
        final temps = wData['hourly']?['temperature_2m'] as List?;
        final codes = wData['hourly']?['weather_code'] as List?;

        if (hours != null && temps != null && codes != null) {
          String currentApiTime = wData['current']?['time'] ?? '';
          int startIndex = hours.indexOf(currentApiTime);
          if (startIndex == -1) startIndex = DateTime.now().hour;

          for (int i = startIndex; i < startIndex + 25 && i < hours.length; i++) {
            hourlyList.add(HourlyWeather(
                hours[i]?.toString().split('T')[1].substring(0, 5) ?? '',
                (temps[i] as num?)?.toDouble() ?? 0.0,
                (codes[i] as num?)?.toInt() ?? 0));
          }
        }

        List<DailyWeather> dailyList = [];
        final dailyTimes = wData['daily']?['time'] as List?;
        final dailyMax = wData['daily']?['temperature_2m_max'] as List?;
        final dailyMin = wData['daily']?['temperature_2m_min'] as List?;
        final dailyCodes = wData['daily']?['weather_code'] as List?;

        if (dailyTimes != null && dailyMax != null && dailyMin != null && dailyCodes != null) {
          for (int i = 0; i < dailyTimes.length; i++) {
            dailyList.add(DailyWeather(
                dailyTimes[i].toString(),
                (dailyMax[i] as num?)?.toDouble() ?? 0.0,
                (dailyMin[i] as num?)?.toDouble() ?? 0.0,
                (dailyCodes[i] as num?)?.toInt() ?? 0));
          }
        }

        final freshWeather = WeatherModel(
          temp: (wData['current']?['temperature_2m'] as num?)?.toDouble() ?? 0.0,
          weatherCode: (wData['current']?['weather_code'] as num?)?.toInt() ?? 0,
          aqi: (aData['current']?['us_aqi'] as num?)?.toInt() ?? 50,
          tempMax: (wData['daily']?['temperature_2m_max']?[0] as num?)?.toDouble() ?? 0.0,
          tempMin: (wData['daily']?['temperature_2m_min']?[0] as num?)?.toDouble() ?? 0.0,
          hourly: hourlyList,
          daily: dailyList,
          humidity: (wData['current']?['relative_humidity_2m'] as num?)?.toInt() ?? 0,
          windSpeed: (wData['current']?['wind_speed_10m'] as num?)?.toDouble() ?? 0.0,
          feelsLike: (wData['current']?['apparent_temperature'] as num?)?.toDouble() ?? 0.0,
          uvIndex: (wData['current']?['uv_index'] as num?)?.toDouble() ?? 0.0,
        );

        // 🚀 3. DATABASE SEEDING (Upsert back to community cache)
        _seedDatabase(lat, lon, freshWeather);

        currentWeather.value = freshWeather;
        return freshWeather;
      }
    } catch (e) {
      debugPrint("⚠️ Weather Fetch Error (Handled): $e");
    }
    return null; // Silent fail gracefully on error
  }

  static Future<void> _seedDatabase(double lat, double lon, WeatherModel weather) async {
    try {
      int gridLat = (lat / 0.03).round();
      int gridLng = (lon / 0.03).round();
      String gridId = 'grid_${gridLat}_$gridLng';

      final highLowStr = jsonEncode({'max': weather.tempMax, 'min': weather.tempMin});
      final hourlyStr = jsonEncode(weather.hourly.map((h) => {'time': h.time, 'temp': h.temp, 'code': h.code}).toList());
      final dailyStr = jsonEncode(weather.daily.map((d) => {'time': d.time, 'maxTemp': d.maxTemp, 'minTemp': d.minTemp, 'code': d.code}).toList());

      await _queryD1(
        '''
        REPLACE INTO weather_grid_cache 
        (grid_id, city_name, current_temp, condition, aqi, high_low, hourly_forecast, daily_forecast, last_updated, uv_index) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          gridId,
          'Unknown', // city_name
          weather.temp,
          weather.weatherCode,
          weather.aqi,
          highLowStr,
          hourlyStr,
          dailyStr,
          DateTime.now().toUtc().toIso8601String(),
          weather.uvIndex
        ]
      );
      debugPrint("✅ Seeded fresh weather to Cloudflare D1 Cache.");
    } catch (e) {
      debugPrint("⚠️ D1 Cache Error (Seed): $e");
    }
  }

  static Future<WeatherModel?> getWeatherByCity(String cityName) async {
    try {
      final geoUrl = Uri.parse("https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(cityName)}&count=1");
      final geoResponse = await _apiClient.get(geoUrl).timeout(_apiTimeout);
      if (geoResponse.statusCode == 200) {
        final data = json.decode(geoResponse.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final lat = (data['results'][0]['latitude'] as num).toDouble();
          final lon = (data['results'][0]['longitude'] as num).toDouble();
          return await getWeather(lat, lon);
        }
      }
    } catch (e) {
      debugPrint("⚠️ Weather Geocoding Error: $e");
    }
    return null;
  }

  static String getWeatherCondition(int code) {
    if (code == 0) return "Clear Sky";
    if (code >= 1 && code <= 3) return "Partly Cloudy";
    if (code >= 45 && code <= 48) return "Foggy";
    if (code >= 51 && code <= 67) return "Rainy";
    if (code >= 71 && code <= 85) return "Snow"; // Added Snow fallback
    if (code >= 95) return "Thunderstorm";
    return "Cloudy";
  }

  static IconData getWeatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny_rounded;
    if (code >= 1 && code <= 3) return Icons.wb_cloudy_rounded;
    if (code >= 51) return Icons.grain_rounded;
    return Icons.cloud;
  }
}
