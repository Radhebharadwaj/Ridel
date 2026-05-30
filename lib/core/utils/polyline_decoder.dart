import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class PolylineDecoder {
  static List<LatLng> decode(String polyline) {
    List<LatLng> coordinates = [];
    int index = 0, len = polyline.length;
    int lat = 0, lng = 0;

    try {
      while (index < len) {
        int b;
        int result = 0;
        int multiplier = 1; // 🚀 Use multiplier instead of bitwise shift (<<)

        // Decode Latitude Offset
        do {
          if (index >= len) break;
          b = polyline.codeUnitAt(index++) - 63;
          result += (b & 0x1f) * multiplier;
          multiplier *= 32;
        } while (b >= 0x20);

        // 🚀 Use Arithmetic instead of bitwise NOT (~) and Right Shift (>>)
        int dlat = (result & 1) != 0 ? -((result ~/ 2) + 1) : (result ~/ 2);
        lat += dlat;

        result = 0;
        multiplier = 1;

        // Decode Longitude Offset
        do {
          if (index >= len) break;
          b = polyline.codeUnitAt(index++) - 63;
          result += (b & 0x1f) * multiplier;
          multiplier *= 32;
        } while (b >= 0x20);

        int dlng = (result & 1) != 0 ? -((result ~/ 2) + 1) : (result ~/ 2);
        lng += dlng;

        // Apply 1e5 precision
        double finalLat = lat / 100000.0;
        double finalLng = lng / 100000.0;

        // 🚀 Strict Bounds Filter
        if (finalLat >= -90.0 && finalLat <= 90.0 && finalLng >= -180.0 && finalLng <= 180.0) {
          coordinates.add(LatLng(finalLat, finalLng));
        }
      }
    } catch (e) {
      debugPrint("🚨 DECODER ERROR: $e");
    }

    return coordinates;
  }
}
