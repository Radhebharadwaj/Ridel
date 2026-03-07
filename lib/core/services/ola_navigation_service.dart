import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter/material.dart';

class OlaNavigationService {
  // 🚀 THE BRIDGE: Ye same naam hum Android me use karenge
  static const MethodChannel _channel = MethodChannel('com.ridel/ola_nav');

  // 🔥 3D Navigation Start karne ka command
  static Future<void> startNavigation({
    required LatLng origin, 
    required LatLng destination,
  }) async {
    try {
      debugPrint("🚀 Flutter: Calling Android Native SDK...");
      
      // Android ko Start & End location bhejna
      final String result = await _channel.invokeMethod('startOlaNavigation', {
        'originLat': origin.latitude,
        'originLng': origin.longitude,
        'destLat': destination.latitude,
        'destLng': destination.longitude,
      });

      debugPrint("✅ Android SDK Replied: $result");
    } on PlatformException catch (e) {
      debugPrint("❌ Failed to start Native Navigation: '${e.message}'.");
    }
  }
}