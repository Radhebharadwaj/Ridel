import 'dart:async';
import 'dart:convert'; // 🚀 NEW: For JSON parsing
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // 🚀 NEW: Needed for WidgetsBindingObserver
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:http/http.dart' as http; // 🚀 NEW: For IP Fallback
// Native geocoding removed, using Ola Maps.
import 'package:ridel/features/profile/services/profile_repository.dart';
import 'package:ridel/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🚀 FIX 3: SharedPreferences
import 'package:ridel/core/services/weather_service.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';

class GlobalLocationService extends ChangeNotifier with WidgetsBindingObserver {
  // --- STATE VARIABLES ---
  final ValueNotifier<Position?> currentPositionNotifier = ValueNotifier(null);
  final ValueNotifier<double> currentHeadingNotifier = ValueNotifier(0.0);
  final ValueNotifier<String> currentCityName = ValueNotifier('Locating...');
  double? cachedLat;
  double? cachedLng;
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
  StreamSubscription<CompassEvent>? _compassStreamSubscription;
  bool _isLiveTrackingActive = false;
  final StreamController<Position> _engineStreamController =
      StreamController<Position>.broadcast();

  // SPEED SMOOTHING (For MapEngine)
  final List<double> _speedHistory = [];
  final ValueNotifier<double> currentSpeedKmphNotifier = ValueNotifier(0.0);
  static const int _smoothingWindow = 5;

  Timer? _debounceTimer; // 🚀 NEW: For debouncing API calls

  // --- GETTERS ---
  bool get hasLocationPermission => _permission == LocationPermission.whileInUse || _permission == LocationPermission.always;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  Position? get currentPosition => currentPositionNotifier.value;
  bool get hasValidLocation => currentPositionNotifier.value != null;
  bool get isLiveTracking => _isLiveTrackingActive;
  double get currentSpeedKmph => currentSpeedKmphNotifier.value;
  double get currentHeading => currentHeadingNotifier.value;
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
    
    // 🚀 Auto-Trigger Reverse Geocoding when position changes
    currentPositionNotifier.addListener(() {
      final pos = currentPositionNotifier.value;
      if (pos != null && !_isUsingIpFallback) {
        _checkAndRefreshCity(pos);
      }
    });
  }

  // 🚀 PHASE 1 (FIXED): PAUSE/RESUME GPS ON LIFECYCLE CHANGES
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // 🚀 Check permission on resume to auto-trigger pipeline
    if (state == AppLifecycleState.resumed) {
      Geolocator.checkPermission().then((perm) {
        if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
          if (currentCityName.value == "Location Disabled" || currentCityName.value == "Locating...") {
            initializeEcoLocation(isManualTrigger: false);
          }
        }
      });
    }

    if (_positionStreamSubscription == null) return;

    // 🚀 FIX 1: NEVER pause stream if active navigation is on!
    if (_isLiveTrackingActive) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      debugPrint("App is paused, pausing GPS stream...");
      _positionStreamSubscription?.pause();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint("App resumed, resuming GPS stream...");
      _positionStreamSubscription?.resume();
      _compassStreamSubscription?.resume();
    }
  }

  // 🚀 TASK 1: Decouple & Elevate the Auto-Detect Logic
  Future<void> autoDetectAndSetRegion({bool isManualTrigger = false}) async {
    await initializeEcoLocation(isManualTrigger: isManualTrigger);
    
    // 🚀 TASK 3: Wire the Weather Cascade (Moved to resolveCityName)
    
    // 🚀 TASK 4: Aggressive UI Rebuild
    notifyListeners();
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
        _currentCity = "Location Disabled"; // Prompt manual entry
        ProfileRepository.userCity.value = "Location Disabled";
        currentCityName.value = "Location Disabled";
        notifyListeners();
        return;
      }
    }

    _permission = await Geolocator.checkPermission();
    
    // 🚀 FIX 3: FIRST-LAUNCH UX
    if (_permission == LocationPermission.denied) {
      if (isManualTrigger) {
        // User manually clicked the button to detect region
        _permission = await Geolocator.requestPermission();
        
        // 🚀 INSTANT BROADCAST: Notify UI immediately after permission granted!
        if (_permission == LocationPermission.whileInUse || _permission == LocationPermission.always) {
          _currentCity = "Locating...";
          currentCityName.value = "Locating...";
          ProfileRepository.userCity.value = "Locating...";
          notifyListeners();
          
          await autoDetectAndSetRegion(); // Task 1: Wire the Permission Grant Hook
          notifyListeners();
          return;
        }
      } else {
        // Crucial: Do NOT prompt for permission on startup if it's denied.
        // Only auto-fetch if it is already granted.
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
      // 🚀 INSTANT BROADCAST: If already granted, show locating state immediately
      if (_currentCity == "Location Disabled" || _currentCity == "Select City" || currentCityName.value == "Location Disabled") {
        _currentCity = "Locating...";
        currentCityName.value = "Locating...";
        ProfileRepository.userCity.value = "Locating...";
        notifyListeners();
      }

      // 🚀 OPTIMIZATION: Fast Cache for Location (Native Only)
      try {
        if (!kIsWeb) {
          final lastPos = await Geolocator.getLastKnownPosition();
          if (lastPos != null && currentPositionNotifier.value == null) {
            debugPrint("⚡ Instant Location: Using last known position.");
            currentPositionNotifier.value = lastPos;
            _isUsingIpFallback = false;
            
            return; // 🚀 Nuke the satellite delay by returning early!
          }
        }
      } on Object catch (_) {}

      try {
        Position pos;
        if (!kIsWeb) {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low, // 🚀 Changed to Low for instant region extraction
            ),
          ).timeout(const Duration(seconds: 8));
        } else {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high, // Web-safe accuracy
            ),
          ).timeout(const Duration(seconds: 8));
        }

        currentPositionNotifier.value = pos;
        _isUsingIpFallback = false;
        
        // 🚀 TRIGGER WEATHER FETCH (Moved to resolveCityName)
        
        notifyListeners(); // Notify city/fallback changes
      } on Object catch (e) {
        debugPrint("GPS Timeout/Error: $e");
        
        Position? lastPos;
        try {
          if (!kIsWeb) {
            lastPos = await Geolocator.getLastKnownPosition();
          }
        } on Object catch (_) {}
        
        if (lastPos != null) {
          debugPrint("Using last known position as safety net.");
          currentPositionNotifier.value = lastPos;
          _isUsingIpFallback = false;
          
          // Weather fetch moved to resolveCityName
          notifyListeners();
        } else {
          await _fetchLocationFromIP();
        }
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
      if (distance < 5000 && _currentCity != "Locating..." && _currentCity != "Location Disabled") return; // Only re-geocode if moved more than 5km
    }

    debugPrint("Refreshing global city...");
    _lastCityGeocodedPosition = newPos; // 🚀 FIX: Assign IMMEDIATELY to prevent overlap queues
    await resolveCityName(newPos.latitude, newPos.longitude);
  }

  String _sanitizeCityName(String rawName) {
    if (rawName.isEmpty) return "Locating...";
    String clean = rawName
        .replaceAll(RegExp(r'^(New|West|East|North|South)\s+', caseSensitive: false), '')
        .trim();
    if (clean.isEmpty) return "Locating...";
    return clean[0].toUpperCase() + clean.substring(1).toLowerCase();
  }

  Future<void> resolveCityName(double currentLat, double currentLng, {bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final savedLat = prefs.getDouble('cachedLat');
      final savedLng = prefs.getDouble('cachedLng');
      final savedCity = prefs.getString('cachedLocality');

      if (savedLat != null && savedLng != null && savedCity != null) {
        final distance = Geolocator.distanceBetween(savedLat, savedLng, currentLat, currentLng);
        if (distance < 15000) {
          _currentCity = savedCity;
          currentCityName.value = savedCity;
          ProfileRepository.userCity.value = savedCity;
          cachedLat = savedLat;
          cachedLng = savedLng;
          return;
        }
      }
    }

    String? newCity;
    try {
      final apiKey = AppConfig.olaMapsKey;
      if (apiKey.isEmpty) throw Exception("Ola Maps API Key missing");

      final url = Uri.parse('https://api.olamaps.io/places/v1/reverse-geocode?latlng=$currentLat,$currentLng&api_key=$apiKey');
      final response = await http.get(url, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = await compute(jsonDecode, response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final result = data['results'][0];
          if (result['address_components'] != null) {
            final components = result['address_components'] as List;
            for (var comp in components) {
              final types = comp['types'] as List;
              if (types.contains('locality') || types.contains('city')) {
                newCity = comp['short_name'] ?? comp['long_name'];
                break;
              }
            }
            if (newCity == null) {
              for (var comp in components) {
                final types = comp['types'] as List;
                if (types.contains('sub_locality') || types.contains('neighborhood') || types.contains('sub_locality_level_1')) {
                  newCity = comp['short_name'] ?? comp['long_name'];
                  break;
                }
              }
            }
          }
          if (newCity == null) {
            final formatted = result['formatted_address'] as String?;
            if (formatted != null && formatted.isNotEmpty) {
               final parts = formatted.split(',');
               if (parts.isNotEmpty) {
                  newCity = parts[0].trim();
               }
            }
          }
        }
      }
    } catch (e) {
      // Ola Maps failed, proceed to fallback silently
    }

    if (newCity == null) {
      try {
        final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?lat=$currentLat&lon=$currentLng&format=json');
        final response = await http.get(url, headers: {
          'User-Agent': 'Ridel_App_v1.0 (contact@ridelapp.com)' 
        }).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = await compute(jsonDecode, response.body);
          if (data['address'] != null) {
            final address = data['address'];
            newCity = address['city'] ?? 
                      address['town'] ?? 
                      address['village'] ?? 
                      address['state_district'] ?? 
                      address['county'];
          }
        }
      } catch (e) {
        // Fallback failed silently
      }
    }

    newCity ??= "Current Location";

    newCity = _sanitizeCityName(newCity);

    prefs.setDouble('cachedLat', currentLat);
    prefs.setDouble('cachedLng', currentLng);
    prefs.setString('cachedLocality', newCity);
    
    _currentCity = newCity;
    currentCityName.value = newCity;
    ProfileRepository.userCity.value = newCity;
    cachedLat = currentLat;
    cachedLng = currentLng;
    
    // 🚀 THE FIX: Instantly match and switch the region in the DB
    await _autoMatchAndSwitchRegion(newCity);
    
    debugPrint("🌤️ [WeatherService] Valid city resolved ($newCity). Fetching weather now...");
    WeatherService.getWeatherByCity(newCity);
    
    notifyListeners();
  }

  Future<void> _autoMatchAndSwitchRegion(String detectedCity) async {
    final detectedLower = detectedCity.toLowerCase().trim();
    dynamic matchedRegion;

    // Standard fallback master regions list
    final List<Map<String, dynamic>> fallbackRegions = [
      {
        "region_id": "delhi",
        "display_name": "Delhi NCR",
        "covered_cities": [
          "delhi", "new delhi", "noida", "gurugram", 
          "gurgaon", "faridabad", "ghaziabad", "greater noida"
        ]
      }
    ];

    for (final region in fallbackRegions) {
      final coveredCities = region['covered_cities'] as List;
      bool isMatch = coveredCities.any((c) {
        String dbCity = c.toString().toLowerCase().trim();
        return detectedLower.contains(dbCity) || dbCity.contains(detectedLower);
      });

      if (isMatch) {
        matchedRegion = region;
        break;
      }
    }

    if (matchedRegion != null) {
      await DatabaseHelper.instance.switchCity(matchedRegion['region_id']);
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
        
        // 🚀 INSTANT BROADCAST
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          _currentCity = "Locating...";
          currentCityName.value = "Locating...";
          ProfileRepository.userCity.value = "Locating...";
          notifyListeners();
          
          await autoDetectAndSetRegion(); // Task 1: Wire the Permission Grant Hook
          notifyListeners();
          return true;
        }
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        await autoDetectAndSetRegion(isManualTrigger: true);
        return true;
      }
    }
    return false;
  }

  // ==========================================
  // 🚀 EFFICIENT ADDRESS CACHING FOR ORIGIN
  // ==========================================
  bool _isFetchingAddress = false;

  Future<void> fetchCurrentAddressIfNeeded() async {
    final Position? currentLoc = currentPositionNotifier.value;
    if (currentLoc == null || _isFetchingAddress) return;

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

    _isFetchingAddress = true;
    _lastAddressGeocodedPosition = currentLoc; // Assign early to avoid queue overlapping

    try {
      final apiKey = AppConfig.olaMapsKey;
      if (apiKey.isEmpty) throw Exception("Ola Maps API Key missing");

      final url = Uri.parse(
          'https://api.olamaps.io/places/v1/reverse-geocode?latlng=${currentLoc.latitude},${currentLoc.longitude}&api_key=$apiKey');

      final response = await http.get(url, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = await compute(jsonDecode, response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final result = data['results'][0];
          
          _currentAddressName = result['formatted_address'] ?? result['name'] ?? _currentCity;
          notifyListeners();
        } else {
          throw Exception("Empty results in Ola Maps response");
        }
      } else {
        throw Exception("Ola Maps API Error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Ola Maps Geocoding Failed: $e");
      // 🚨 FALLBACK: Show exact coordinates if API fails
      _currentAddressName = "${currentLoc.latitude.toStringAsFixed(5)}, ${currentLoc.longitude.toStringAsFixed(5)}";
      notifyListeners();
    } finally {
      _isFetchingAddress = false;
    }
  }

  // ==========================================
  // 🌐 MOCK CITY LOCATION (PHASE 7)
  // ==========================================
  void setMockLocationForCity(String city) {
    double lat = 28.6139; // Default Delhi
    double lng = 77.2090;

    String c = city.toLowerCase().trim();
    if (c == "delhi" || c == "new delhi") { lat = 28.6139; lng = 77.2090; _currentState = "Delhi"; }
    else if (c == "noida") { lat = 28.5355; lng = 77.3910; _currentState = "Uttar Pradesh"; }
    else if (c == "gurugram" || c == "gurgaon") { lat = 28.4595; lng = 77.0266; _currentState = "Haryana"; }
    else if (c == "faridabad") { lat = 28.4089; lng = 77.3178; _currentState = "Haryana"; }
    else if (c == "ghaziabad") { lat = 28.6692; lng = 77.4538; _currentState = "Uttar Pradesh"; }
    else if (c == "greater noida") { lat = 28.4744; lng = 77.5040; _currentState = "Uttar Pradesh"; }
    else { _currentState = ""; }

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
        final data = await compute(jsonDecode, response.body);

        String fetchedCityName = data['city']?.toString() ?? "Location Disabled";
        if (fetchedCityName.trim().isEmpty || fetchedCityName.toLowerCase().contains('select city') || fetchedCityName == "Current Location") {
            fetchedCityName = 'Location Disabled';
        }

        // 🚀 SAFEGUARD: Fallback mapped coordinates instead of IP center points
        _applyCityFallbackCoordinates(fetchedCityName);



        _currentCity = forceSelectCityUI ? "Location Disabled" : fetchedCityName;
        _currentState = forceSelectCityUI ? "Location Disabled" : (data['region']?.toString() ?? "");
        currentCityName.value = _currentCity;
        _isUsingIpFallback = true;
        ProfileRepository.userCity.value = _currentCity;
        if (!forceSelectCityUI && _currentCity != "Location Disabled") {
          WeatherService.getWeatherByCity(_currentCity);
        }
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

  void _setFallbackIndiaCenter({bool forceSelectCityUI = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedLat = prefs.getDouble('cachedLat') ?? 28.6139; // Default to Delhi NCR instead of Nagpur
    final cachedLng = prefs.getDouble('cachedLng') ?? 77.2090;

    currentPositionNotifier.value = Position(
      latitude: cachedLat,
      longitude: cachedLng,
      timestamp: DateTime.now(),
      accuracy: 10000.0, altitude: 0, altitudeAccuracy: 0, heading: 0,
      headingAccuracy: 0, speed: 0, speedAccuracy: 0, 
      isMocked: true, // 🚀 STRICTLY MARK AS MOCKED
    );
    _currentCity = forceSelectCityUI ? "Location Disabled" : "Location Disabled";
    _currentState = forceSelectCityUI ? "Location Disabled" : "Location Disabled";
    currentCityName.value = _currentCity;
    _isUsingIpFallback = true;
    ProfileRepository.userCity.value = _currentCity;
    notifyListeners();
  }

  void _applyCityFallbackCoordinates(String cityName) {
    double lat = 28.6139; // Default Delhi NCR
    double lng = 77.2090;

    final cleanCity = cityName.toLowerCase().trim();
    if (cleanCity.contains("delhi") || cleanCity.contains("noida") || cleanCity.contains("gurugram")) {
      lat = 28.6139; lng = 77.2090;
    } else if (cleanCity.contains("mumbai")) {
      lat = 19.0760; lng = 72.8777;
    } else if (cleanCity.contains("bengaluru") || cleanCity.contains("bangalore")) {
      lat = 12.9716; lng = 77.5946;
    } else if (cleanCity.contains("kolkata")) {
      lat = 22.5726; lng = 88.3639;
    }

    currentPositionNotifier.value = Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 10000.0, altitude: 0, altitudeAccuracy: 0, heading: 0,
      headingAccuracy: 0, speed: 0, speedAccuracy: 0,
      isMocked: true, // 🚀 CRITICAL: Tells the map NOT to zoom to street level!
    );

    // Trigger weather fetch moved to resolveCityName
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
        } on Object catch (_) {}
      });
      return;
    }

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 50),
    ).listen((Position position) {
      _updatePositionAndSpeed(position);
    }, onError: (error) {
      debugPrint("📍 [DEBUG] GPS stream lost or glitched: $error");
    });

    if (!kIsWeb) {
      _compassStreamSubscription?.cancel();
      _compassStreamSubscription = FlutterCompass.events?.listen((event) {
        if (event.heading != null) {
          currentHeadingNotifier.value = event.heading!;
        }
      });
    }
  }

  void _updatePositionAndSpeed(Position position) {
    currentPositionNotifier.value = position;
    
    if (kIsWeb) {
      if (position.speed > 0.5) {
        currentHeadingNotifier.value = position.heading;
      }
    } else {
      // On native, heading is managed by compass
    }

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

    _isLiveTrackingActive = false;
    _positionStreamSubscription?.cancel();
    _compassStreamSubscription?.cancel();
    debugPrint("🛑 STOPPED Live GPS Tracking");
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
    currentHeadingNotifier.dispose();
    currentCityName.dispose();
    super.dispose();
  }
}

