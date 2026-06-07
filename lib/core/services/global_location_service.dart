import 'dart:async';
import 'dart:convert'; // 🚀 NEW: For JSON parsing
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // 🚀 NEW: Needed for WidgetsBindingObserver
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http; // 🚀 NEW: For IP Fallback
import 'package:geocoding/geocoding.dart';
import 'package:ridel/features/profile/services/profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🚀 FIX 3: SharedPreferences
import 'package:ridel/core/services/weather_service.dart';

class GlobalLocationService extends ChangeNotifier with WidgetsBindingObserver {
  // --- STATE VARIABLES ---
  final ValueNotifier<Position?> currentPositionNotifier = ValueNotifier(null);
  final ValueNotifier<String?> currentCityName = ValueNotifier(null);
  bool _isLocationServiceEnabled = false;
  LocationPermission _permission = LocationPermission.denied;
  bool _isUsingIpFallback = false; // 🚀 NEW: Track if we are using IP location
  String _currentCity = "Locating..."; // 🚀 NEW: Global city name
  String _currentState = "";
  
  // 🚀 NEW: Address Caching for Origin
  String? _currentAddressName;
  Position? _lastCityGeocodedPosition;
  Position? _lastAddressGeocodedPosition;

  // LIVE TRACKING & MAP ENGINE STREAMS
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isLiveTrackingActive = false;
  final StreamController<Position> _engineStreamController =
      StreamController<Position>.broadcast();

  // SPEED SMOOTHING (For MapEngine)
  final List<double> _speedHistory = [];
  final ValueNotifier<double> currentSpeedKmphNotifier = ValueNotifier(0.0);
  static const int _smoothingWindow = 5;

  Timer? _debounceTimer; // 🚀 NEW: For debouncing API calls

  // --- GETTERS ---
  Position? get currentPosition => currentPositionNotifier.value;
  bool get hasValidLocation => currentPositionNotifier.value != null;
  bool get isLiveTracking => _isLiveTrackingActive;
  double get currentSpeedKmph => currentSpeedKmphNotifier.value;
  bool get isUsingIpFallback =>
      _isUsingIpFallback; // UI can show "Approximate Location"
  String get currentCity => _currentCity;
  String get currentState => _currentState;
  String? get currentAddressName => _currentAddressName;
  void setCurrentAddressName(String value) {
    _currentAddressName = value;
    notifyListeners();
  }
  Position? get lastCityGeocodedPosition => _lastCityGeocodedPosition;
  Position? get lastAddressGeocodedPosition => _lastAddressGeocodedPosition;
  Stream<Position> get engineLocationStream => _engineStreamController.stream;

  GlobalLocationService() {
    WidgetsBinding.instance.addObserver(this);
  }

  // 🚀 PHASE 1 (FIXED): PAUSE/RESUME GPS ON LIFECYCLE CHANGES
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_positionStreamSubscription == null) return;

    // 🚀 FIX 1: NEVER pause stream if active navigation is on!
    if (_isLiveTrackingActive) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      debugPrint("App is paused, pausing GPS stream...");
      _positionStreamSubscription?.pause();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint("App resumed, resuming GPS stream...");
      _positionStreamSubscription?.resume();
    }
  }

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
        _currentCity = "Select City"; // Prompt manual entry
        ProfileRepository.userCity.value = "Select City";
        notifyListeners();
        return;
      }
    }

    _permission = await Geolocator.checkPermission();
    
    // 🚀 FIX 3: FIRST-LAUNCH UX
    if (_permission == LocationPermission.denied) {
      final prefs = await SharedPreferences.getInstance();
      final hasPrompted = prefs.getBool('has_prompted_location') ?? false;

      if (!hasPrompted) {
        // Absolutely first launch! Auto-prompt to prevent terrible UX.
        _permission = await Geolocator.requestPermission();
        await prefs.setBool('has_prompted_location', true);
      } else if (isManualTrigger) {
        // User manually clicked the button later
        _permission = await Geolocator.requestPermission();
      } else {
        // Already prompted before, and this is an auto-startup. Fall back silently.
        await _fetchLocationFromIP(forceSelectCityUI: true);
        return;
      }
      
      // If after prompt it's still denied
      if (_permission == LocationPermission.denied) {
        await _fetchLocationFromIP(forceSelectCityUI: true);
        return;
      }
    }

    // 🚀 FIX: Agar user ne permanently deny kar diya, toh app settings kholo
    if (_permission == LocationPermission.deniedForever) {
      if (isManualTrigger && !kIsWeb) {
        await Geolocator.openAppSettings();
      }
      await _fetchLocationFromIP(forceSelectCityUI: true);
      return;
    }

    if (_permission == LocationPermission.whileInUse || _permission == LocationPermission.always) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 8)); // 8 sec timeout thoda better hai

        currentPositionNotifier.value = pos;
        _isUsingIpFallback = false;
        _lastCityGeocodedPosition = pos; // Set initial geocode pos
        await forceReverseGeocode(pos);
        
        // 🚀 TRIGGER WEATHER FETCH
        WeatherService.getWeather(pos.latitude, pos.longitude);
        
        notifyListeners(); // Notify city/fallback changes
      } catch (e) {
        debugPrint("GPS Timeout/Error: $e");
        // Sirf timeout hone par hi IP fallback do
        await _fetchLocationFromIP(); 
      }
    }
  }

  // 🚀 FIX 2: Check Distance & Refresh (Replaces Map Panning Spam)
  Future<void> _checkAndRefreshCity(Position newPos) async {
    if (_lastCityGeocodedPosition != null) {
      final distance = Geolocator.distanceBetween(
        _lastCityGeocodedPosition!.latitude, _lastCityGeocodedPosition!.longitude,
        newPos.latitude, newPos.longitude
      );
      if (distance < 5000) return; // Only re-geocode if moved more than 5km
    }

    debugPrint("Refreshing global city...");
    await forceReverseGeocode(newPos);
    _lastCityGeocodedPosition = newPos;
  }

  Future<void> forceReverseGeocode(Position pos) async {
    final lat = pos.latitude;
    final lng = pos.longitude;
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        _currentCity = place.locality?.isNotEmpty == true ? place.locality! 
                 : place.subAdministrativeArea?.isNotEmpty == true ? place.subAdministrativeArea! 
                 : place.administrativeArea?.isNotEmpty == true ? place.administrativeArea! 
                 : "Delhi";
        _currentState = place.administrativeArea ?? "";
        currentCityName.value = _currentCity;
        ProfileRepository.userCity.value = _currentCity; // 🚀 Update Header globally
      } else {
        throw Exception("Empty placemarks array");
      }
    } catch (e) {
      debugPrint("Global Reverse Geocoding Failed: $e. Attempting OSM Fallback...");
      try {
        final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng');
        final response = await http.get(url, headers: {'User-Agent': 'RidelApp'});
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final address = data['address'] as Map<String, dynamic>?;
          if (address != null) {
            String realCity = address['city'] ?? address['town'] ?? address['village'] ?? address['state'] ?? "Unknown Location";
            _currentCity = realCity;
            currentCityName.value = _currentCity;
            ProfileRepository.userCity.value = _currentCity;
          } else {
            throw Exception("No address object in OSM response");
          }
        } else {
          throw Exception("OSM returned status ${response.statusCode}");
        }
      } catch (fallbackError) {
        debugPrint("OSM Geocoding Fallback Failed: $fallbackError");
        _currentCity = "Unknown Location";
        currentCityName.value = _currentCity;
        ProfileRepository.userCity.value = _currentCity;
      }
    }
  }

  // ==========================================
  // 🚀 PHASE 7: EXPLICIT GPS HARD GATE FOR MAP/ROUTING
  // ==========================================
  Future<bool> requireLocationForMapServices(BuildContext context) async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      return true; // Already granted
    }

    if (!context.mounted) return false;

    // Show polite BottomSheet or Dialog to enforce requirement
    bool? userAgreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2129),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Location Required',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "We need your exact location to provide accurate routing, map services, and find rides near you. Please enable it to continue.",
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enable Location',
                style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (userAgreed == true) {
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return false; // User has to manually return from settings
      } else {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        await initializeEcoLocation(isManualTrigger: true);
        return true;
      }
    }
    return false;
  }

  // ==========================================
  // 🚀 EFFICIENT ADDRESS CACHING FOR ORIGIN
  // ==========================================
  Future<void> fetchCurrentAddressIfNeeded() async {
    final Position? currentLoc = currentPositionNotifier.value;
    if (currentLoc == null) return;

    // If we already have an address AND the user hasn't moved more than 50 meters, skip API call!
    if (_currentAddressName != null && _lastAddressGeocodedPosition != null) {
      double distanceMoved = Geolocator.distanceBetween(
        _lastAddressGeocodedPosition!.latitude, _lastAddressGeocodedPosition!.longitude,
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

        _lastAddressGeocodedPosition = currentLoc;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Reverse Geocode for exact address failed: $e");
      // 🚨 FALLBACK: Show exact coordinates if API fails
      _currentAddressName = "${currentLoc.latitude.toStringAsFixed(5)}, ${currentLoc.longitude.toStringAsFixed(5)}";
      _lastAddressGeocodedPosition = currentLoc;
      notifyListeners();
    }
  }

  // ==========================================
  // 🌐 MOCK CITY LOCATION (PHASE 7)
  // ==========================================
  void setMockLocationForCity(String city) {
    double lat = 28.6139; // Default Delhi
    double lng = 77.2090;

    String c = city.toLowerCase().trim();
    if (c == "delhi" || c == "new delhi") { lat = 28.6139; lng = 77.2090; }
    else if (c == "noida") { lat = 28.5355; lng = 77.3910; }
    else if (c == "gurugram" || c == "gurgaon") { lat = 28.4595; lng = 77.0266; }
    else if (c == "faridabad") { lat = 28.4089; lng = 77.3178; }
    else if (c == "ghaziabad") { lat = 28.6692; lng = 77.4538; }
    else if (c == "greater noida") { lat = 28.4744; lng = 77.5040; }

    currentPositionNotifier.value = Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 10000.0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      isMocked: true,
    );
    _currentCity = city;
    currentCityName.value = _currentCity;
    _isUsingIpFallback = true;
    notifyListeners();
  }

  // ==========================================
  // 🌐 THE MAGIC: IP-BASED FALLBACK
  // ==========================================
  Future<void> _fetchLocationFromIP({bool forceSelectCityUI = false}) async {
    try {
      debugPrint("Fetching approximate location via IP...");
      // Free HTTPS IP API (No key required for basic use)
      final response = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // 🚀 Create a Mock 'Position' object so MapEngine doesn't crash
        currentPositionNotifier.value = Position(
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

        _currentCity = forceSelectCityUI ? "Select City" : (data['city']?.toString() ?? "Unknown Location");
        _currentState = data['region']?.toString() ?? "";
        currentCityName.value = _currentCity;
        _isUsingIpFallback = true;
        ProfileRepository.userCity.value = _currentCity;
        notifyListeners();
        debugPrint(
            "IP Fallback Success: $_currentCity, $_currentState");
      }
    } catch (e) {
      debugPrint("IP Fallback completely failed: $e");
      // Agar IP API bhi fail ho jaye, toh Default India ka center de do (Nagpur)
      _setFallbackIndiaCenter(forceSelectCityUI: forceSelectCityUI);
    }
  }

  void _setFallbackIndiaCenter({bool forceSelectCityUI = false}) {
    currentPositionNotifier.value = Position(
      latitude: 21.1458, // Nagpur Center
      longitude: 79.0882,
      timestamp: DateTime.now(),
      accuracy: 10000.0, altitude: 0, altitudeAccuracy: 0, heading: 0,
      headingAccuracy: 0, speed: 0, speedAccuracy: 0, isMocked: true,
    );
    _currentCity = forceSelectCityUI ? "Select City" : "Nagpur";
    _currentState = "Maharashtra";
    currentCityName.value = _currentCity;
    _isUsingIpFallback = true;
    ProfileRepository.userCity.value = _currentCity;
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
    notifyListeners(); // Notify tracking state

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
    currentPositionNotifier.value = position;

    double rawSpeed = (position.speed * 3.6).clamp(0.0, 240.0);
    _speedHistory.add(rawSpeed);
    if (_speedHistory.length > _smoothingWindow) _speedHistory.removeAt(0);
    currentSpeedKmphNotifier.value =
        _speedHistory.reduce((a, b) => a + b) / _speedHistory.length;

    if (!_engineStreamController.isClosed) {
      _engineStreamController.add(position);
    }
    
    // 🚀 FIX 2: Check distance and trigger reverse geocoding if moved
    _checkAndRefreshCity(position);
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
    notifyListeners(); // Notify tracking state change
  }

  Future<void> forceRefreshLocation() async => await initializeEcoLocation();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    _positionStreamSubscription?.cancel();
    _engineStreamController.close();
    currentPositionNotifier.dispose();
    currentSpeedKmphNotifier.dispose();
    currentCityName.dispose();
    super.dispose();
  }
}

