import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:ridel/core/config/app_config.dart';

final http.Client _apiClient = http.Client();
const Duration _apiTimeout = Duration(seconds: 5);

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
}

class WeatherService {
  static final ValueNotifier<WeatherModel?> currentWeather =
      ValueNotifier(null);

  static WeatherModel _parseWeatherData(Map<String, dynamic> data) {
    List<ForecastDayModel> parsedDaily = [];
    if (data['daily'] != null) {
      for (var d in data['daily']) {
        final dayInfo = d['day'] ?? {};
        final cond = dayInfo['condition'] ?? {};
        parsedDaily.add(ForecastDayModel(
          d['date']?.toString() ?? '',
          (dayInfo['maxtemp_c'] as num?)?.toDouble() ?? 0.0,
          (dayInfo['mintemp_c'] as num?)?.toDouble() ?? 0.0,
          (cond['code'] as num?)?.toInt() ?? 0,
          cond['text']?.toString() ?? '',
          cond['icon']?.toString() ?? '',
        ));
      }
    }

    List<HourlyWeather> parsedHourly = [];
    if (data['hourly'] != null) {
      for (var h in data['hourly']) {
        parsedHourly.add(HourlyWeather(
          h['time']?.toString() ?? '',
          (h['temp'] as num?)?.toDouble() ?? 0.0,
          (h['code'] as num?)?.toInt() ?? 0,
        ));
      }
    }

    return WeatherModel(
      temp: (data['temp'] as num?)?.toDouble() ?? 0.0,
      weatherCode: (data['condition'] as num?)?.toInt() ?? 0,
      aqi: (data['aqi'] as num?)?.toInt() ?? 50,
      tempMax: parsedDaily.isNotEmpty ? parsedDaily.first.maxTemp : 0.0,
      tempMin: parsedDaily.isNotEmpty ? parsedDaily.first.minTemp : 0.0,
      daily: parsedDaily,
      hourly: parsedHourly,
      humidity: (data['humidity'] as num?)?.toInt() ?? 0,
      windSpeed: (data['windSpeed'] as num?)?.toDouble() ?? 0.0,
      feelsLike: (data['feelsLike'] as num?)?.toDouble() ?? 0.0,
      uvIndex: (data['uvIndex'] as num?)?.toDouble() ?? 0.0,
    );
  }

  static Future<WeatherModel?> getWeather(double lat, double lon) async {
    try {
      final url = Uri.parse(
          'https://ridel.ridel.workers.dev/api/weather?lat=$lat&lng=$lon');

      debugPrint('🚀 Sending Weather Request to: $url');

      final response = await _apiClient.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'admin-secret': AppConfig
              .appSecretPasskey, // Updated to match Cloudflare expectation
        },
      ).timeout(_apiTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        if (json['success'] == true) {
          final data = json['results'] ?? json['data'];
          final freshWeather = _parseWeatherData(data);
          currentWeather.value = freshWeather;
          return freshWeather;
        } else {
          throw Exception(json['error'] ?? 'Unknown API Error');
        }
      } else {
        debugPrint('❌ HTTP ERROR: ${response.statusCode} | ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ WEATHER FETCH EXCEPTION: $e');
      return null;
    }
  }

  static Future<WeatherModel?> getWeatherByCity(String city) async {
    try {
      final url =
          Uri.parse('https://ridel.ridel.workers.dev/api/weather?city=$city');

      debugPrint('🚀 Sending Weather Request to: $url');

      final response = await _apiClient.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'ADMIN-SECRET': AppConfig.appSecretPasskey,
        },
      ).timeout(_apiTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        if (json['success'] == true) {
          final data = json['results'] ?? json['data'];
          final freshWeather = _parseWeatherData(data);
          currentWeather.value = freshWeather;
          return freshWeather;
        } else {
          throw Exception(json['error'] ?? 'Unknown API Error');
        }
      } else {
        debugPrint('❌ HTTP ERROR: ${response.statusCode} | ${response.body}');
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

  static IconData getWeatherIcon(int code) {
    if (code == 1000) return Icons.wb_sunny_rounded;
    if (code >= 1003 && code <= 1009) return Icons.wb_cloudy_rounded;
    if (code >= 1150 && code <= 1201) return Icons.grain_rounded;
    return Icons.cloud;
  }
}
