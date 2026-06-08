import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/cupertino.dart';
import 'package:ridel/core/config/app_config.dart';

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
  
  static DateTime? lastFetchTime;
  static String? lastFetchQuery;
  static bool _isFetching = false;

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
    if (data['daily'] != null && data['daily'].isNotEmpty) {
      final today = data['daily'][0];
      if (today['hour'] != null) {
        for (var h in today['hour']) {
          final cond = h['condition'] ?? {};
          parsedHourly.add(HourlyWeather(
            h['time']?.toString() ?? '',
            (h['temp_c'] as num?)?.toDouble() ?? (h['temp'] as num?)?.toDouble() ?? 0.0,
            (cond['code'] as num?)?.toInt() ?? (h['code'] as num?)?.toInt() ?? 0,
          ));
        }
      }
    }

    int finalAqi = 50;
    if (data['current'] != null && data['current']['air_quality'] != null) {
      var aq = data['current']['air_quality'];
      if (aq['pm2_5'] != null) {
         double pm25 = (aq['pm2_5'] as num).toDouble();
         if (pm25 <= 30) { finalAqi = ((pm25 / 30) * 50).round(); }
         else if (pm25 <= 60) { finalAqi = (50 + ((pm25 - 30) / 30) * 50).round(); }
         else if (pm25 <= 90) { finalAqi = (100 + ((pm25 - 60) / 30) * 100).round(); }
         else if (pm25 <= 120) { finalAqi = (200 + ((pm25 - 90) / 30) * 100).round(); }
         else if (pm25 <= 250) { finalAqi = (300 + ((pm25 - 120) / 130) * 100).round(); }
         else { finalAqi = (400 + ((pm25 - 250) / 100) * 100).clamp(400, 500).round(); }
      } else if (aq['us-epa-index'] != null) {
        int epa = (aq['us-epa-index'] as num).toInt();
        switch (epa) {
          case 1: finalAqi = 42; break;
          case 2: finalAqi = 75; break;
          case 3: finalAqi = 135; break;
          case 4: finalAqi = 180; break;
          case 5: finalAqi = 250; break;
          case 6: finalAqi = 400; break;
        }
      }
    } else if (data['aqi'] != null) {
      int rawAqi = (data['aqi'] as num).toInt();
      if (rawAqi >= 1 && rawAqi <= 6) {
        switch (rawAqi) {
          case 1: finalAqi = 42; break;
          case 2: finalAqi = 75; break;
          case 3: finalAqi = 135; break;
          case 4: finalAqi = 180; break;
          case 5: finalAqi = 250; break;
          case 6: finalAqi = 400; break;
        }
      } else {
        finalAqi = rawAqi;
      }
    }

    return WeatherModel(
      temp: (data['temp'] as num?)?.toDouble() ?? 0.0,
      weatherCode: (data['condition'] as num?)?.toInt() ?? 0,
      aqi: finalAqi,
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
    String query = "$lat,$lon";
    if (currentWeather.value != null && lastFetchTime != null && lastFetchQuery == query) {
      if (DateTime.now().difference(lastFetchTime!).inMinutes < 60) {
        return currentWeather.value;
      }
    }

    if (_isFetching) return null;
    _isFetching = true;

    try {
      final url = Uri.parse(
          'https://ridel.ridel.workers.dev/api/weather?lat=$lat&lng=$lon');

      debugPrint('🚀 Sending Weather Request to: $url');

      final response = await _apiClient.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'admin-secret': AppConfig.appSecretPasskey,
        },
      ).timeout(_apiTimeout);

      if (response.statusCode == 200) {
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
      } else {
        debugPrint('❌ HTTP ERROR: ${response.statusCode} | ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ WEATHER FETCH EXCEPTION: $e');
      return null;
    } finally {
      _isFetching = false;
    }
  }

  static Future<WeatherModel?> getWeatherByCity(String city) async {
    if (city.isEmpty || city == 'Select City') {
      debugPrint('⚠️ Weather Fetch Skipped: Invalid City Name');
      return null;
    }

    if (currentWeather.value != null && lastFetchTime != null && lastFetchQuery == city) {
      if (DateTime.now().difference(lastFetchTime!).inMinutes < 60) {
        return currentWeather.value;
      }
    }

    if (_isFetching) return null;
    _isFetching = true;

    try {
      final url =
          Uri.parse('https://ridel.ridel.workers.dev/api/weather?city=$city');

      debugPrint('🚀 Sending Weather Request to: $url');

      final response = await _apiClient.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'admin-secret':
              AppConfig.appSecretPasskey, // 🔒 Wapas secure path lag gaya
        },
      ).timeout(_apiTimeout);

      if (response.statusCode == 200) {
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
      } else {
        debugPrint('❌ HTTP ERROR: ${response.statusCode} | ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ WEATHER FETCH EXCEPTION: $e');
      return null;
    } finally {
      _isFetching = false;
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
