import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ridel/core/utils/toast_service.dart';

class LocationGuard {
  /// Checks location permissions and services.
  /// Requests permission if needed.
  /// Shows appropriate toasts on failure.
  /// Returns [true] if permission is granted and service is enabled, [false] otherwise.
  static Future<bool> checkAndRequestLocation(BuildContext context) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (context.mounted) {
        ToastService.showError(context, "Please turn on your device's GPS/Location service.", title: "GPS Disabled");
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (context.mounted) {
          ToastService.showError(context, "Location permission is required for this feature. Please enable it in settings.");
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ToastService.showError(context, "Location permission is required for this feature. Please enable it in settings.");
      }
      return false;
    }

    return true;
  }
}
