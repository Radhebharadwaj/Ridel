import 'dart:async';
import 'dart:convert'; // 🚀 NEW: For JSON parsing
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http; // 🚀 NEW: For IP Fallback
import 'package:geocoding/geocoding.dart';
import 'package:ridel/features/profile/services/profile_repository.dart';

class GlobalLocationService extends ChangeNotifier {
  // --- STATE VARIABLES ---
  Position? _currentPosition;
  bool _isLocationServiceEnabled = false;
  LocationPermission _permission = LocationPermission.denied;
  bool _isUsingIpFallback = false; // 🚀 NEW: Track if we are using IP location
  String _currentCity = "Locating..."; // 🚀 NEW: Global city name
  String _currentState = "";
  
  // 🚀 NEW: Address Caching for Origin
  String? _currentAddressName;
  Position? _lastGeocodedPosition;

  // LIVE TRACKING & MAP ENGINE STREAMS
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isLiveTrackingActive = false;
  final StreamController<Position> _engineStreamController =
      StreamController<Position>.broadcast();

  // SPEED SMOOTHING (For MapEngine)
  final List<double> _speedHistory = [];
  double _currentSpeedKmph = 0.0;
  static const int _smoothingWindow = 5;

  // --- GETTERS ---
  Position? get currentPosition => _currentPosition;
  bool get hasValidLocation => _currentPosition != null;
  bool get isLiveTracking => _isLiveTrackingActive;
  double get currentSpeedKmph => _currentSpeedKmph;
  bool get isUsingIpFallback =>
      _isUsingIpFallback; // UI can show "Approximate Location"
  String get currentCity => _currentCity;
  String get currentState => _currentState;
  String? get currentAddressName => _currentAddressName;
  void setCurrentAddressName(String value) {
    _currentAddressName = value;
    notifyListeners();
  }
  Position? get lastGeocodedPosition => _lastGeocodedPosition;
  Stream<Position> get engineLocationStream => _engineStreamController.stream;

  // ==========================================
  // 1. APP STARTUP (PRODUCTION HARDENED GPS)
  // ==========================================
  Future<void> initializeEcoLocation({bool isManualTrigger = false}) async {
    _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();

    // 🚀 FIX: Agar GPS band hai, toh IP mat use karo. User ko GPS on karne bolo.
    if (!_isLocationServiceEnabled) {
      if (kIsWeb) {
        await _fetchLocationFromIP(); // Web par chalega
      } else {
        if (isManualTrigger) {
          await Geolocator.openLocationSettings();
        }
        _isUsingIpFallback = false;
        _currentCity = "City";
        ProfileRepository.userCity.value = "City";
        notifyListeners();
        return;
      }
    }

    _permission = await Geolocator.checkPermission();
    if (_permission == LocationPermission.denied) {
      _permission = await Geolocator.requestPermission();
    }

    // 🚀 FIX: Agar user ne permanently deny kar diya, toh app settings kholo
    if (_permission == LocationPermission.deniedForever) {
      if (isManualTrigger && !kIsWeb) {
        await Geolocator.openAppSettings();
      }
      _currentCity = "City";
      ProfileRepository.userCity.value = "City";
      notifyListeners();
      return;
    }

    if (_permission == LocationPermission.denied) {
      _currentCity = "City";
      ProfileRepository.userCity.value = "City";
      notifyListeners();
      return;
    }

    if (_permission == LocationPermission.whileInUse || _permission == LocationPermission.always) {
      try {
        _currentPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 8)); // 8 sec timeout thoda better hai

        _isUsingIpFallback = false;
        await _updateCityFromCoordinates(_currentPosition!.latitude, _currentPosition!.longitude);
        notifyListeners();
      } catch (e) {
        debugPrint("GPS Timeout/Error: $e");
        // Sirf timeout hone par hi IP fallback do
        await _fetchLocationFromIP(); 
      }
    }
  }

  Future<void> _updateCityFromCoordinates(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        _currentCity = place.locality?.isNotEmpty == true ? place.locality! 
                 : place.subAdministrativeArea?.isNotEmpty == true ? place.subAdministrativeArea! 
                 : place.administrativeArea?.isNotEmpty == true ? place.administrativeArea! 
                 : "Delhi";
        _currentState = place.administrativeArea ?? "";
        ProfileRepository.userCity.value = _currentCity; // 🚀 Update Header globally
      }
    } catch (e) {
      debugPrint("Global Reverse Geocoding Failed: $e");
    }
  }

  // ==========================================
  // 🚀 EFFICIENT ADDRESS CACHING FOR ORIGIN
  // ==========================================
  Future<void> fetchCurrentAddressIfNeeded() async {
    final Position? currentLoc = _currentPosition;
    if (currentLoc == null) return;

    // If we already have an address AND the user hasn't moved more than 50 meters, skip API call!
    if (_currentAddressName != null && _lastGeocodedPosition != null) {
      double distanceMoved = Geolocator.distanceBetween(
        _lastGeocodedPosition!.latitude, _lastGeocodedPosition!.longitude,
        currentLoc.latitude, currentLoc.longitude
      );
      if (distanceMoved < 50.0) {
        return; // Use cached address
      }
    }

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(currentLoc.latitude, currentLoc.longitude)
          .timeout(const Duration(seconds: 5));
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        // Construct a clean, human-readable address
        _currentAddressName = [place.street, place.subLocality, place.locality]
            .where((e) => e != null && e.isNotEmpty)
            .join(', ');
        
        if (_currentAddressName == null || _currentAddressName!.isEmpty) {
          _currentAddressName = _currentCity;
        }

        _lastGeocodedPosition = currentLoc;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Reverse Geocode for exact address failed: $e");
      // 🚨 FALLBACK: Show exact coordinates if API fails
      _currentAddressName = "${currentLoc.latitude.toStringAsFixed(5)}, ${currentLoc.longitude.toStringAsFixed(5)}";
      _lastGeocodedPosition = currentLoc;
      notifyListeners();
    }
  }

  // ==========================================
  // 🌐 THE MAGIC: IP-BASED FALLBACK
  // ==========================================
  Future<void> _fetchLocationFromIP() async {
    try {
      debugPrint("Fetching approximate location via IP...");
      // Free HTTPS IP API (No key required for basic use)
      final response = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // 🚀 Create a Mock 'Position' object so MapEngine doesn't crash
        _currentPosition = Position(
          latitude: data['latitude'],
          longitude: data['longitude'],
          timestamp: DateTime.now(),
          accuracy: 5000.0, // Low accuracy since it's an IP
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          isMocked: true, // Tells the app this is not exact GPS
        );

        _currentCity = data['city']?.toString() ?? "Unknown Location";
        _currentState = data['region']?.toString() ?? "";
        _isUsingIpFallback = true;
        notifyListeners();
        debugPrint(
            "IP Fallback Success: $_currentCity, $_currentState");
      }
    } catch (e) {
      debugPrint("IP Fallback completely failed: $e");
      // Agar IP API bhi fail ho jaye, toh Default India ka center de do (Nagpur)
      _setFallbackIndiaCenter();
    }
  }

  void _setFallbackIndiaCenter() {
    _currentPosition = Position(
      latitude: 21.1458, // Nagpur Center
      longitude: 79.0882,
      timestamp: DateTime.now(),
      accuracy: 10000.0, altitude: 0, altitudeAccuracy: 0, heading: 0,
      headingAccuracy: 0, speed: 0, speedAccuracy: 0, isMocked: true,
    );
    _currentCity = "Nagpur";
    _currentState = "Maharashtra";
    _isUsingIpFallback = true;
    notifyListeners();
  }

  // ==========================================
  // 2. ACTIVE MODE (LIVE NAVIGATION & SPEED)
  // ==========================================
  void startLiveTracking() {
    if (_isLiveTrackingActive) return;

    // Agar IP fallback use kar raha hai, toh live tracking on mat karo (kyunki speed 0 hi rahegi)
    if (_isUsingIpFallback) return;

    _isLiveTrackingActive = true;
    notifyListeners();

    if (kIsWeb) {
      Timer.periodic(const Duration(seconds: 3), (timer) async {
        if (!_isLiveTrackingActive) {
          timer.cancel();
          return;
        }
        try {
          // 🚀 Updated: Using LocationSettings for Web too
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );
          _updatePositionAndSpeed(pos);
        } catch (_) {}
      });
      return;
    }

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 3),
    ).listen((Position position) {
      _updatePositionAndSpeed(position);
    });
  }

  void _updatePositionAndSpeed(Position position) {
    _currentPosition = position;

    double rawSpeed = (position.speed * 3.6).clamp(0.0, 240.0);
    _speedHistory.add(rawSpeed);
    if (_speedHistory.length > _smoothingWindow) _speedHistory.removeAt(0);
    _currentSpeedKmph =
        _speedHistory.reduce((a, b) => a + b) / _speedHistory.length;

    if (!_engineStreamController.isClosed) {
      _engineStreamController.add(position);
    }
    notifyListeners();
  }

  // ==========================================
  // 3. STOP ACTIVE MODE
  // ==========================================
  void stopLiveTracking() {
    if (!_isLiveTrackingActive) return;

    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _isLiveTrackingActive = false;
    _speedHistory.clear();
    notifyListeners();
  }

  Future<void> forceRefreshLocation() async => await initializeEcoLocation();

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _engineStreamController.close();
    super.dispose();
  }
}
