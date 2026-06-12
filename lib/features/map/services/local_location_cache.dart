import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';

class LocalLocationCache {
  static const String _keyLocality = 'cached_locality';
  static const String _keyLat = 'cached_lat';
  static const String _keyLng = 'cached_lng';
  static const double _validRadiusMeters = 10000.0; 

  Future<void> saveLocationCache({required String locality, required double lat, required double lng}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocality, locality);
    await prefs.setDouble(_keyLat, lat);
    await prefs.setDouble(_keyLng, lng);
  }

  Future<String?> getCachedLocality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLocality);
  }

  Future<bool> hasValidCache(double currentLat, double currentLng) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedLat = prefs.getDouble(_keyLat);
    final cachedLng = prefs.getDouble(_keyLng);

    if (cachedLat == null || cachedLng == null) return false;

    var p = 0.017453292519943295;
    var c = math.cos;
    var a = 0.5 - c((cachedLat - currentLat) * p)/2 + 
            c(currentLat * p) * c(cachedLat * p) * (1 - c((cachedLng - currentLng) * p))/2;
    var distanceMeters = 12742 * math.asin(math.sqrt(a)) * 1000;

    return distanceMeters <= _validRadiusMeters;
  }
}
