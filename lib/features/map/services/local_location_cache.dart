import 'package:shared_preferences/shared_preferences.dart';

class LocalLocationCache {
  static const String _kCachedLocality = 'cachedLocality';
  static const String _kCachedLat = 'cachedLat';
  static const String _kCachedLng = 'cachedLng';

  Future<void> saveLocationCache({
    required String locality,
    required double lat,
    required double lng,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCachedLocality, locality);
    await prefs.setDouble(_kCachedLat, lat);
    await prefs.setDouble(_kCachedLng, lng);
  }

  Future<String?> getCachedLocality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCachedLocality);
  }

  Future<double?> getCachedLat() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kCachedLat);
  }

  Future<double?> getCachedLng() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kCachedLng);
  }

  Future<bool> hasCache() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_kCachedLocality) &&
        prefs.containsKey(_kCachedLat) &&
        prefs.containsKey(_kCachedLng);
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCachedLocality);
    await prefs.remove(_kCachedLat);
    await prefs.remove(_kCachedLng);
  }
}
