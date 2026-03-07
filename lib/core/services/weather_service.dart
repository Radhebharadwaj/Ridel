import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

class WeatherModel {
  final double temp;
  final int weatherCode;
  final int aqi;
  final double tempMax;
  final double tempMin;
  final List<HourlyWeather> hourly;
  final int humidity;
  final double windSpeed;
  final double feelsLike;

  WeatherModel({
    required this.temp,
    required this.weatherCode,
    required this.aqi,
    required this.tempMax,
    required this.tempMin,
    required this.hourly,
    required this.humidity,
    required this.windSpeed,
    required this.feelsLike,
  });
}

class HourlyWeather {
  final String time;
  final double temp;
  final int code;
  HourlyWeather(this.time, this.temp, this.code);
}

class WeatherService {
  static Future<WeatherModel?> getWeather(double lat, double lon) async {
    try {
      final weatherUrl = Uri.parse(
          "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code,is_day,relative_humidity_2m,wind_speed_10m,apparent_temperature&daily=temperature_2m_max,temperature_2m_min&hourly=temperature_2m,weather_code&timezone=auto&forecast_days=1");
      
      final aqiUrl = Uri.parse(
          "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=$lat&longitude=$lon&current=us_aqi");

      final responses = await Future.wait([http.get(weatherUrl), http.get(aqiUrl)]);

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final wData = json.decode(responses[0].body);
        final aData = json.decode(responses[1].body);

        List<HourlyWeather> hourlyList = [];
        final hours = wData['hourly']['time'] as List;
        final temps = wData['hourly']['temperature_2m'] as List;
        final codes = wData['hourly']['weather_code'] as List;
        
        int nowHour = DateTime.now().hour;
        for (int i = nowHour; i < nowHour + 5 && i < hours.length; i++) {
          hourlyList.add(HourlyWeather(hours[i].toString().split('T')[1].substring(0, 5), temps[i].toDouble(), codes[i]));
        }

        return WeatherModel(
          temp: wData['current']['temperature_2m'].toDouble(),
          weatherCode: wData['current']['weather_code'],
          aqi: aData['current']['us_aqi'] ?? 50,
          tempMax: wData['daily']['temperature_2m_max'][0].toDouble(),
          tempMin: wData['daily']['temperature_2m_min'][0].toDouble(),
          hourly: hourlyList,
          humidity: wData['current']['relative_humidity_2m'],
          windSpeed: wData['current']['wind_speed_10m'].toDouble(),
          feelsLike: wData['current']['apparent_temperature'].toDouble(),
        );
      }
    } catch (e) {
      debugPrint("⚠️ Weather Error: $e");
    }
    return null;
  }
  
  // 🔥 FIX: Ye Method Missing tha, ab add kar diya hai
  static String getWeatherCondition(int code) {
    if (code == 0) return "Clear Sky";
    if (code >= 1 && code <= 3) return "Partly Cloudy";
    if (code >= 45 && code <= 48) return "Foggy";
    if (code >= 51 && code <= 67) return "Rainy";
    if (code >= 95) return "Thunderstorm";
    return "Cloudy";
  }

  // 🔥 Helper Icon
  static IconData getWeatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny_rounded;
    if (code >= 1 && code <= 3) return Icons.wb_cloudy_rounded;
    if (code >= 51) return Icons.grain_rounded;
    return Icons.cloud;
  }
}