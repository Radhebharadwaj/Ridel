import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ridel/features/map/services/local_location_cache.dart';
import 'package:ridel/features/map/services/ola_maps_service.dart';

class LocationRepository extends ChangeNotifier {
  final LocalLocationCache _cache = LocalLocationCache();
  final OlaMapsService _olaService = OlaMapsService();

  String? _currentLocality;
  bool _isLoading = false;

  String? get currentLocality => _currentLocality;
  bool get isLoading => _isLoading;

  LocationRepository() {
    _loadInitialCache();
  }

  Future<void> _loadInitialCache() async {
    _currentLocality = await _cache.getCachedLocality();
    if (_currentLocality != null) {
      notifyListeners();
    }
  }

  Future<String?> getLocationName() async {
    // Immediately yield the cachedLocality to the UI if it exists.
    final cachedLocality = await _cache.getCachedLocality();
    if (cachedLocality != null) {
      _currentLocality = cachedLocality;
      notifyListeners();
    }

    _isLoading = true;
    notifyListeners();

    try {
      // Get the current device GPS coordinates
      final currentPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final currentLat = currentPos.latitude;
      final currentLng = currentPos.longitude;

      bool shouldFetchFromOla = false;
      final hasCache = await _cache.hasCache();

      if (hasCache) {
        final cachedLat = await _cache.getCachedLat();
        final cachedLng = await _cache.getCachedLng();

        if (cachedLat != null && cachedLng != null) {
          final distance = Geolocator.distanceBetween(
              cachedLat, cachedLng, currentLat, currentLng);
          
          // Trigger Condition: IF the distance is greater than 10000 meters (10 km)
          if (distance > 10000) {
            shouldFetchFromOla = true;
          }
        } else {
          shouldFetchFromOla = true;
        }
      } else {
        // OR if the cache is empty
        shouldFetchFromOla = true;
      }

      if (shouldFetchFromOla) {
        // call ola_maps_service.fetchCityFromOla
        final newCity = await _olaService.fetchCityFromOla(currentLat, currentLng);
        if (newCity != null) {
          _currentLocality = newCity;
          // Update the UI with the new city name and save the new name, lat, and lng to the cache
          await _cache.saveLocationCache(
            locality: newCity,
            lat: currentLat,
            lng: currentLng,
          );
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("Error in getLocationName: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    return _currentLocality;
  }

  // Task 4: Manual Refresh Capability
  Future<void> forceRefreshLocation(double lat, double lng) async {
    _isLoading = true;
    notifyListeners();

    try {
      // bypasses the 10km check, forces an Ola Maps API call, updates the cache, and refreshes the UI
      final newCity = await _olaService.fetchCityFromOla(lat, lng);
      if (newCity != null) {
        _currentLocality = newCity;
        await _cache.saveLocationCache(
          locality: newCity,
          lat: lat,
          lng: lng,
        );
      }
    } catch (e) {
      debugPrint("Error in forceRefreshLocation: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
