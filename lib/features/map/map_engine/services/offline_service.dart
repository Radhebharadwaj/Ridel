import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart'; // REQUIRED for kIsWeb
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

class OfflineService {
  static const String _tileCachePrefix = 'tile_cache_';
  static const String _regionCachePrefix = 'region_cache_';
  static const Duration _tileCacheTTL = Duration(days: 7);
  static const int _maxTileCacheSize = 500; 
  
  static bool _isOnline = true;
  static final StreamController<bool> _networkController = StreamController<bool>.broadcast();
  
  static Future<bool> get isOnline async {
    if (kIsWeb) {
      // Browsers handle connection states internally, pinging Google throws CORS errors
      _isOnline = true; 
    } else {
      try {
        final response = await http.get(Uri.parse('https://www.google.com')).timeout(const Duration(seconds: 3));
        _isOnline = response.statusCode == 200;
      } catch (e) {
        _isOnline = false;
      }
    }
    
    _networkController.add(_isOnline);
    return _isOnline;
  }
  
  static Stream<bool> get networkStream => _networkController.stream;
  
  static Future<void> cacheTile({required String tileUrl, required List<int> tileData, required DateTime timestamp}) async {
    if (kIsWeb || !await _shouldCacheTile(tileUrl)) return; // Web local storage limit save
    
    final prefs = await SharedPreferences.getInstance();
    final cacheEntry = {'data': base64Encode(tileData), 'timestamp': timestamp.millisecondsSinceEpoch, 'url': tileUrl};
    await prefs.setString('$_tileCachePrefix${_hashUrl(tileUrl)}', json.encode(cacheEntry));
  }
  
  static Future<List<int>?> getCachedTile(String tileUrl) async {
    if (kIsWeb) return null;
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString('$_tileCachePrefix${_hashUrl(tileUrl)}');
    if (cachedJson == null) return null;
    try {
      final cacheEntry = json.decode(cachedJson);
      return base64Decode(cacheEntry['data']);
    } catch (_) { return null; }
  }
  
  static Future<bool> _shouldCacheTile(String tileUrl) async => tileUrl.contains('/tiles/');
  static String _hashUrl(String url) => url.hashCode.toString();
  
  static void initialize() {
    if (!kIsWeb) Timer.periodic(const Duration(seconds: 30), (_) async => await isOnline);
  }
}