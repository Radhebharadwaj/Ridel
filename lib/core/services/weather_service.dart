import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/cupertino.dart';

final http.Client _apiClient = http.Client();
const Duration _apiTimeout = Duration(seconds: 15);

class ForecastDayModel {
  final String date;
  final double maxTemp;
  final double minTemp;
  final int conditionCode;
  final String conditionText;
  final String conditionIcon;

  ForecastDayModel(this.date, this.maxTemp, this.minTemp, this.conditionCode,
      this.conditionText, this.conditionIcon);
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
  final String condition;
  final int aqi;
  final double tempMax;
  final double tempMin;
  final List<ForecastDayModel> daily;
  final List<HourlyWeather> hourly;
  final int humidity;
  final double windSpeed;
  final double feelsLike;
  final double uvIndex;

  WeatherModel({
    required this.temp,
    required this.weatherCode,
    required this.condition,
    required this.aqi,
    required this.tempMax,
    required this.tempMin,
    required this.daily,
    required this.hourly,
    required this.humidity,
    required this.windSpeed,
    required this.feelsLike,
    required this.uvIndex,
  });

  factory WeatherModel.fromJson(Map<String, dynamic> json) {
    // Handle both nested {data: {...}} and flat responses gracefully
    final data = json['data'] ?? json; 

    return WeatherModel(
      temp: (data['temp'] as num?)?.toDouble() ?? 0.0,
      feelsLike: (data['feelsLike'] as num?)?.toDouble() ?? 0.0,
      weatherCode: (data['weatherCode'] as num?)?.toInt() ?? 0,
      condition: data['condition']?.toString() ?? "--",
      humidity: (data['humidity'] as num?)?.toInt() ?? 0,
      windSpeed: (data['windSpeed'] as num?)?.toDouble() ?? 0.0,
      uvIndex: (data['uvIndex'] as num?)?.toDouble() ?? 0.0,
      tempMax: (data['tempMax'] as num?)?.toDouble() ?? 0.0,
      tempMin: (data['tempMin'] as num?)?.toDouble() ?? 0.0,
      aqi: (data['aqi'] as num?)?.toInt() ?? 0,
      
      // 🚀 STRICT ARRAY PARSING TO FIX '0°' BUG
      hourly: (data['hourly'] as List<dynamic>?)?.map((h) => HourlyWeather(
        h['time']?.toString() ?? '',
        (h['temp'] as num?)?.toDouble() ?? 0.0,
        (h['code'] as num?)?.toInt() ?? 0,
      )).toList() ?? [],
      
      daily: (data['daily'] as List<dynamic>?)?.map((d) => ForecastDayModel(
        d['date']?.toString() ?? '',
        (d['maxTemp'] as num?)?.toDouble() ?? 0.0,
        (d['minTemp'] as num?)?.toDouble() ?? 0.0,
        (d['conditionCode'] as num?)?.toInt() ?? 0,
        d['conditionText']?.toString() ?? '',
        d['conditionIcon']?.toString() ?? '',
      )).toList() ?? [],
    );
  }
}

class WeatherService {
  static final ValueNotifier<WeatherModel?> currentWeather =
      ValueNotifier(null);
  
  static DateTime? lastFetchTime;
  static String? lastFetchQuery;


  static WeatherModel _parseWeatherData(Map<String, dynamic> data) {
    return WeatherModel.fromJson(data);
  }

  static final Map<String, Future<WeatherModel?>> _activeRequests = {};

  static Future<WeatherModel?> getWeather(double lat, double lon) async {
    String query = "$lat,$lon";
    if (currentWeather.value != null && lastFetchTime != null && lastFetchQuery == query) {
      if (DateTime.now().difference(lastFetchTime!).inMinutes < 60) {
        return currentWeather.value;
      }
    }

    if (_activeRequests.containsKey(query)) {
      debugPrint('🛡️ Weather Fetch Deduplicated (Already active) for: $query');
      return await _activeRequests[query];
    }

    final future = _fetchWeatherInternal(lat, lon, query);
    _activeRequests[query] = future;

    try {
      return await future;
    } finally {
      _activeRequests.remove(query);
    }
  }

  static Future<WeatherModel?> _fetchWeatherInternal(double lat, double lon, String query) async {
    try {
      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = Uri.parse(
          'https://ridel.ridel.workers.dev/api/weather?lat=$lat&lng=$lon&t=$timestamp');

      debugPrint('🚀 Sending Weather Request to: $url');

      final response = await _apiClient.get(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(_apiTimeout);

      if (response.statusCode == 200) {
        try {
          final json = jsonDecode(response.body);

          if (json['success'] == true) {
            final data = json['results'] ?? json['data'];
            final freshWeather = _parseWeatherData(data);
            currentWeather.value = freshWeather;
            lastFetchTime = DateTime.now();
            lastFetchQuery = query;
            return freshWeather;
          } else {
            throw Exception(json['error'] ?? 'Unknown API Error');
          }
        } catch (e) {
          debugPrint('Weather JSON Parse Error: $e');
          return null;
        }
      } else {
        debugPrint('❌ HTTP ERROR: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ WEATHER FETCH EXCEPTION: $e');
      return null;
    }
  }

  static Future<WeatherModel?> getWeatherByCity(String city, {double? lat, double? lng}) async {
    if (city.isEmpty || city == 'Select City') {
      debugPrint('⚠️ Weather Fetch Skipped: Invalid City Name');
      return null;
    }

    if (currentWeather.value != null && lastFetchTime != null && lastFetchQuery == city) {
      if (DateTime.now().difference(lastFetchTime!).inMinutes < 60) {
        return currentWeather.value;
      }
    }

    if (_activeRequests.containsKey(city)) {
      debugPrint('🛡️ Weather Fetch Deduplicated (Already active) for: $city');
      return await _activeRequests[city];
    }

    final future = _fetchWeatherByCityInternal(city, lat, lng);
    _activeRequests[city] = future;

    try {
      return await future;
    } finally {
      _activeRequests.remove(city);
    }
  }

  static Future<WeatherModel?> _fetchWeatherByCityInternal(String city, double? lat, double? lng) async {
    try {
      // 🚀 FIX: ALWAYS append lat and lng to the URL
      final double finalLat = lat ?? 28.6139;
      final double finalLng = lng ?? 77.2090;
      final url = Uri.parse(
          'https://ridel.ridel.workers.dev/api/weather?lat=$finalLat&lng=$finalLng&city=${Uri.encodeComponent(city)}');

      debugPrint('🚀 Sending Weather Request to: $url');

      final response = await _apiClient.get(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(_apiTimeout);

      if (response.statusCode == 200) {
        try {
          final json = jsonDecode(response.body);

          if (json['success'] == true) {
            final data = json['results'] ?? json['data'];
            final freshWeather = _parseWeatherData(data);
            currentWeather.value = freshWeather;
            lastFetchTime = DateTime.now();
            lastFetchQuery = city;
            return freshWeather;
          } else {
            throw Exception(json['error'] ?? 'Unknown API Error');
          }
        } catch (e) {
          debugPrint('Weather JSON Parse Error: $e');
          return null;
        }
      } else {
        debugPrint('❌ HTTP ERROR: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ WEATHER FETCH EXCEPTION: $e');
      return null;
    }
  }

  static String getWeatherCondition(int code) {
    if (code == 1000) return 'Sunny';
    if (code >= 1003 && code <= 1009) return 'Cloudy';
    if (code >= 1150 && code <= 1201) return 'Rain';
    if (code >= 1210 && code <= 1230) return 'Snow';
    if (code >= 1273 && code <= 1282) return 'Storm';
    return 'Clear';
  }

  static IconData getWeatherIcon(int code, {bool isDay = true}) {
    if (code == 1000) return isDay ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_stars_fill;
    if (code == 1003) return isDay ? CupertinoIcons.cloud_sun_fill : CupertinoIcons.cloud_moon_fill;
    if (code == 1006 || code == 1009) return CupertinoIcons.cloud_fill;
    if (code == 1030 || code == 1135 || code == 1148) return CupertinoIcons.cloud_fog_fill;
    if (code == 1063 || (code >= 1150 && code <= 1183)) return CupertinoIcons.cloud_drizzle_fill;
    if (code >= 1186 && code <= 1201) return CupertinoIcons.cloud_heavyrain_fill;
    if (code >= 1210 && code <= 1237) return CupertinoIcons.snow;
    if (code >= 1273 && code <= 1282) return CupertinoIcons.cloud_bolt_rain_fill;
    return CupertinoIcons.cloud_fill;
  }
}
