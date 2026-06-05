import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

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
  static Future<WeatherModel?> getWeather(double lat, double lon) async {
    try {
      // 🚀 3. BUG FIX: forecast_days=7 tak badhaya aur daily weather_code add kiya
      final weatherUrl = Uri.parse(
          "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code,is_day,relative_humidity_2m,wind_speed_10m,apparent_temperature,uv_index&daily=weather_code,temperature_2m_max,temperature_2m_min&hourly=temperature_2m,weather_code&timezone=auto&forecast_days=7");

      final aqiUrl = Uri.parse(
          "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=$lat&longitude=$lon&current=us_aqi");

      // 🚀 4. TIMEOUT ADDED on Future.wait
      final responses = await Future.wait([
        _apiClient.get(weatherUrl).timeout(_apiTimeout),
        _apiClient.get(aqiUrl).timeout(_apiTimeout)
      ]);

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final wData = json.decode(responses[0].body);
        final aData = json.decode(responses[1].body);

        // --- SAFELY EXTRACT HOURLY DATA (Fixing Timezone Crash) ---
        List<HourlyWeather> hourlyList = [];
        final hours = wData['hourly']?['time'] as List?;
        final temps = wData['hourly']?['temperature_2m'] as List?;
        final codes = wData['hourly']?['weather_code'] as List?;

        if (hours != null && temps != null && codes != null) {
          // Exact current time string API se nikaalo
          String currentApiTime = wData['current']?['time'] ?? '';

          // Us string ko array me dhundo taaki correct timezone match ho
          int startIndex = hours.indexOf(currentApiTime);

          // Agar kisi wajah se match nahi hota, tab system time use karo as fallback
          if (startIndex == -1) startIndex = DateTime.now().hour;

          // Agle 25 ghante ka data loop karo (UI mein horizontally scroll karne ke liye)
          for (int i = startIndex;
              i < startIndex + 25 && i < hours.length;
              i++) {
            hourlyList.add(HourlyWeather(
                hours[i]?.toString().split('T')[1].substring(0, 5) ?? '',
                (temps[i] as num?)?.toDouble() ?? 0.0,
                (codes[i] as num?)?.toInt() ?? 0));
          }
        }

        // --- EXTRACT REAL DAILY DATA (Fixing Fake Math Bug) ---
        List<DailyWeather> dailyList = [];
        final dailyTimes = wData['daily']?['time'] as List?;
        final dailyMax = wData['daily']?['temperature_2m_max'] as List?;
        final dailyMin = wData['daily']?['temperature_2m_min'] as List?;
        final dailyCodes = wData['daily']?['weather_code'] as List?;

        if (dailyTimes != null &&
            dailyMax != null &&
            dailyMin != null &&
            dailyCodes != null) {
          for (int i = 0; i < dailyTimes.length; i++) {
            dailyList.add(DailyWeather(
                dailyTimes[i].toString(),
                (dailyMax[i] as num?)?.toDouble() ?? 0.0,
                (dailyMin[i] as num?)?.toDouble() ?? 0.0,
                (dailyCodes[i] as num?)?.toInt() ?? 0));
          }
        }

        return WeatherModel(
          temp:
              (wData['current']?['temperature_2m'] as num?)?.toDouble() ?? 0.0,
          weatherCode:
              (wData['current']?['weather_code'] as num?)?.toInt() ?? 0,
          aqi: (aData['current']?['us_aqi'] as num?)?.toInt() ?? 50,
          tempMax:
              (wData['daily']?['temperature_2m_max']?[0] as num?)?.toDouble() ??
                  0.0,
          tempMin:
              (wData['daily']?['temperature_2m_min']?[0] as num?)?.toDouble() ??
                  0.0,
          hourly: hourlyList,
          daily: dailyList, // 🚀 Real 7 din ka data attach kar diya
          humidity:
              (wData['current']?['relative_humidity_2m'] as num?)?.toInt() ?? 0,
          windSpeed:
              (wData['current']?['wind_speed_10m'] as num?)?.toDouble() ?? 0.0,
          feelsLike:
              (wData['current']?['apparent_temperature'] as num?)?.toDouble() ??
                  0.0,
          uvIndex:
              (wData['current']?['uv_index'] as num?)?.toDouble() ?? 0.0,
        );
      }
    } catch (e) {
      debugPrint("⚠️ Weather Fetch Error (Handled): $e");
    }
    return null; // Silent fail gracefully on error
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
