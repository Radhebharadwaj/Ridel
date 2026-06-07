// lib/core/services/app_config_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ======================================================================
// 🚀 App Status Enum — Drives full-screen enforcement layer
// ======================================================================
enum AppStatus { normal, updateRequired, maintenance }

// ======================================================================
// 🌐 AppConfigService — Cloudflare CDN Config + 24hr Cache
// ======================================================================
class AppConfigService {
  static final AppConfigService _instance = AppConfigService._internal();
  factory AppConfigService() => _instance;
  AppConfigService._internal();

  static const String _configUrl = 'https://ridel.pages.dev/app_config.json';
  static const String _cacheKey = 'app_config_cache';
  static const String _cacheTimestampKey = 'app_config_cache_timestamp';
  static const Duration _cacheDuration = Duration(hours: 24);

  Map<String, dynamic>? _cachedConfig;

  // ------------------------------------------------------------------
  // 📡 Fetch config with 24-hour SharedPreferences cache
  // ------------------------------------------------------------------
  Future<Map<String, dynamic>?> fetchConfig({bool forceRefresh = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ✅ Check local cache first (unless force refresh)
      if (!forceRefresh) {
        final cachedJson = prefs.getString(_cacheKey);
        final cachedTimestamp = prefs.getInt(_cacheTimestampKey);

        if (cachedJson != null && cachedTimestamp != null) {
          final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedTimestamp);
          final elapsed = DateTime.now().difference(cachedAt);

          if (elapsed < _cacheDuration) {
            _cachedConfig = jsonDecode(cachedJson) as Map<String, dynamic>;
            debugPrint('☁️ AppConfig loaded from 24hr cache');
            return _cachedConfig;
          }
        }
      }

      // 🌐 Cache expired or missing — fetch from Cloudflare CDN
      final response = await http
          .get(Uri.parse(_configUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final config = jsonDecode(response.body) as Map<String, dynamic>;

        // 💾 Save to SharedPreferences with fresh timestamp
        await prefs.setString(_cacheKey, response.body);
        await prefs.setInt(
            _cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);

        _cachedConfig = config;
        debugPrint('☁️ AppConfig fetched fresh from CDN');
        return config;
      } else {
        debugPrint('⚠️ AppConfig CDN returned ${response.statusCode}');
        // Fallback to stale cache if network fails
        return _fallbackToStaleCache(prefs);
      }
    } catch (e) {
      debugPrint('🚨 AppConfig fetch error: $e');
      // Fallback to stale cache on any error
      final prefs = await SharedPreferences.getInstance();
      return _fallbackToStaleCache(prefs);
    }
  }

  Map<String, dynamic>? _fallbackToStaleCache(SharedPreferences prefs) {
    final cachedJson = prefs.getString(_cacheKey);
    if (cachedJson != null) {
      _cachedConfig = jsonDecode(cachedJson) as Map<String, dynamic>;
      debugPrint('☁️ AppConfig using stale cache as fallback');
      return _cachedConfig;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // 🔍 Parse Config Fields
  // ------------------------------------------------------------------
  String? get minVersion => _cachedConfig?['min_version'] as String?;
  String? get latestVersion => _cachedConfig?['latest_version'] as String?;

  bool get isMaintenanceActive {
    final maintenance = _cachedConfig?['maintenance'];
    if (maintenance is Map<String, dynamic>) {
      return maintenance['is_active'] == true;
    }
    return false;
  }

  String? get maintenanceMessage {
    final maintenance = _cachedConfig?['maintenance'];
    if (maintenance is Map<String, dynamic>) {
      return maintenance['message'] as String?;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // 🚦 checkAppStatus() — Core enforcement logic
  // ------------------------------------------------------------------
  Future<AppStatus> checkAppStatus() async {
    final config = await fetchConfig();

    // If config is null (network + cache both failed), allow app usage
    if (config == null) return AppStatus.normal;

    // 🛑 Maintenance check takes priority
    if (isMaintenanceActive) return AppStatus.maintenance;

    // 🔄 Version enforcement check
    final minVer = minVersion;
    if (minVer == null) return AppStatus.normal;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g., "1.0.0"

      if (_isVersionBelow(currentVersion, minVer)) {
        return AppStatus.updateRequired;
      }
    } catch (e) {
      debugPrint('🚨 PackageInfo error: $e');
      // Can't determine version — don't block the user
    }

    return AppStatus.normal;
  }

  // ------------------------------------------------------------------
  // 🔢 Semantic version comparison: is current < minimum?
  // ------------------------------------------------------------------
  bool _isVersionBelow(String current, String minimum) {
    final currentParts = current.split('.').map(int.tryParse).toList();
    final minimumParts = minimum.split('.').map(int.tryParse).toList();

    // Pad to 3 parts (major.minor.patch)
    while (currentParts.length < 3) {
      currentParts.add(0);
    }
    while (minimumParts.length < 3) {
      minimumParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      final curr = currentParts[i] ?? 0;
      final min = minimumParts[i] ?? 0;
      if (curr < min) return true;
      if (curr > min) return false;
    }
    return false; // Equal versions = not below
  }
}
