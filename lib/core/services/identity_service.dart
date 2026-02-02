import 'package:flutter/foundation.dart'; // kIsWeb ke liye
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:universal_io/io.dart'; // ✅ Web-safe Platform import (pubspec me universal_io hona chahiye)

class IdentityService {
  
  // ✅ Fixed Location Logic (Web + Mobile Safe)
  Future<Map<String, String?>> getLocationInfo() async {
    try {
      // 1. Service Check
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw "Location services disabled.";
      }

      // 2. Permission Check
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw "Location permission denied.";
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw "Location permissions are permanently denied.";
      }

      // 3. Get Position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 4. Convert to Address (Try-Catch for Web stability)
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          return {
            'country_code': place.isoCountryCode ?? 'IN',
            'state_code': _getStateCode(place.administrativeArea),
            'current_city': place.locality ?? place.subAdministrativeArea ?? place.administrativeArea,
          };
        }
      } catch (e) {
        // Web par agar Geocoding fail ho, toh Coordinates return karo (Fallback)
        debugPrint("Geocoding failed (Expected on Web): $e");
        return {
          'country_code': 'GPS',
          'state_code': '',
          'current_city': '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
        };
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
    
    // Fail hua toh null return karo
    return {
      'country_code': null,
      'state_code': null,
      'current_city': null,
    };
  }

  String? _getStateCode(String? stateName) {
    if (stateName == null) return null;
    
    // Indian States Map
    const stateMap = {
      'Andhra Pradesh': 'AP', 'Arunachal Pradesh': 'AR', 'Assam': 'AS',
      'Bihar': 'BR', 'Chhattisgarh': 'CG', 'Goa': 'GA', 'Gujarat': 'GJ',
      'Haryana': 'HR', 'Himachal Pradesh': 'HP', 'Jharkhand': 'JH',
      'Karnataka': 'KA', 'Kerala': 'KL', 'Madhya Pradesh': 'MP',
      'Maharashtra': 'MH', 'Manipur': 'MN', 'Meghalaya': 'ML',
      'Mizoram': 'MZ', 'Nagaland': 'NL', 'Odisha': 'OD', 'Punjab': 'PB',
      'Rajasthan': 'RJ', 'Sikkim': 'SK', 'Tamil Nadu': 'TN',
      'Telangana': 'TS', 'Tripura': 'TR', 'Uttar Pradesh': 'UP',
      'Uttarakhand': 'UK', 'West Bengal': 'WB', 'Delhi': 'DL',
      'Jammu and Kashmir': 'JK', 'Ladakh': 'LA', 'Puducherry': 'PY',
      'Chandigarh': 'CH',
    };
    
    return stateMap[stateName] ?? (stateName.length >= 2 ? stateName.substring(0, 2).toUpperCase() : stateName.toUpperCase());
  }

  // ✅ Web-Safe Device Info
  // (Agar universal_io error de, toh pubspec.yaml me `universal_io: ^2.2.2` add karna)
}