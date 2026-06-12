import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:ridel/features/map/models/place_model.dart';

/// 🚀 The Universal Map Share Engine (Decoupled & Pure Utility)
class MapShareService {
  // 🚀 FIX: Per-Action Debounce prevents blocking unrelated share actions
  static final Map<String, DateTime> _lastShareTimes = {};
  static const Duration _shareDebounce = Duration(seconds: 2);

  // =========================================================================
  // 1. Share Current Live Location (Context-Free)
  // =========================================================================
  // UI Layer is now responsible for fetching location and handling errors/retries.
  static Future<void> shareCurrentLocation(LatLng position) async {
    if (_isDebounced('current_location')) return;

    if (position.latitude == 0.0 && position.longitude == 0.0) return;

    await _executeShare(
        "My Current Location", position.latitude, position.longitude);
  }

  // =========================================================================
  // 2. Share a Specific Place
  // =========================================================================
  static Future<void> sharePlace(PlaceModel place) async {
    if (_isDebounced('place_${place.placeId}')) return;

    if (place.latitude == 0.0 && place.longitude == 0.0) return;

    // 🚀 FIX: Fallback for empty place names
    final title = (place.name.trim().isEmpty) ? "Unknown Place" : place.name;

    await _executeShare(title, place.latitude, place.longitude,
        address: place.address);
  }

  // =========================================================================
  // 3. Share a Dropped Pin
  // =========================================================================
  static Future<void> shareCoordinate(LatLng coordinate,
      {String title = "Dropped Pin"}) async {
    if (_isDebounced('coordinate')) return;

    if (coordinate.latitude == 0.0 && coordinate.longitude == 0.0) return;

    await _executeShare(title, coordinate.latitude, coordinate.longitude);
  }

  // =========================================================================
  // 🚀 THE CORE SHARING ENGINE (Platform-Aware & Zero-Lag)
  // =========================================================================
  static Future<void> _executeShare(String title, double lat, double lng,
      {String? address}) async {
    try {
      String mapUrl = "";
      if (kIsWeb) {
        // Safe Web URL
        mapUrl = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
      } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
        // Native Apple Maps URL
        mapUrl = "maps://?ll=$lat,$lng&q=${Uri.encodeComponent(title)}";
      } else {
        // Fallback Native Google Maps
        mapUrl = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
      }

      String shareText = "📍 $title\n";
      if (address != null && address.trim().isNotEmpty) {
        shareText += "$address\n\n";
      }
      shareText += "View on Maps: $mapUrl";

      final result = await Share.share(
        shareText,
        subject: "Shared via Ridel Maps",
      );

      // Silent analytics hook could be added here checking result.status
      if (result.status == ShareResultStatus.dismissed) {
        debugPrint("Share dialog dismissed by user.");
      }
    } catch (e) {
      debugPrint("❌ Share execution failed: $e");
      // UI layer should use try-catch when calling these methods to show Snackbars
      throw Exception("Unable to open sharing options.");
    }
  }

  // =========================================================================
  // 🛡️ INTERNAL HELPERS
  // =========================================================================

  static bool _isDebounced(String actionKey) {
    final now = DateTime.now();
    if (_lastShareTimes.containsKey(actionKey)) {
      if (now.difference(_lastShareTimes[actionKey]!) < _shareDebounce) {
        return true;
      }
    }
    _lastShareTimes[actionKey] = now;
    return false;
  }
}
