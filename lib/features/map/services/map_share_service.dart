import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ridel/core/services/global_location_service.dart'; // 🚀 Added Brain

class MapShareService {
  // 🚀 Require BuildContext to access the Brain
  static Future<void> shareCurrentLocation(BuildContext context) async {
    try {
      final locService = Provider.of<GlobalLocationService>(context, listen: false);

      // Agar kisi wajah se location nahi hai, toh 1 baar force refresh karo
      if (locService.currentPosition == null) {
        await locService.forceRefreshLocation();
      }

      final position = locService.currentPosition;
      
      if (position == null) {
        debugPrint("❌ Sharing failed: Location not available");
        // Aap chaho toh yahan ek ScaffoldMessenger (SnackBar) dikha sakte ho
        return;
      }

      // 🚀 Universal URL pattern for all platforms
      final String mapUrl = "https://maps.google.com/?q=${position.latitude},${position.longitude}";

      await Share.share(
        "Meri current location yahan hai:\n$mapUrl",
        subject: "Ridel Maps Location Share",
      );
      
    } catch (e) {
      debugPrint("Sharing error: $e");
    }
  }
}