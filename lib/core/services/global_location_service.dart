import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class GlobalLocationService extends ChangeNotifier {
  // --- STATE VARIABLES ---
  Position? _currentPosition;
  bool _isLocationServiceEnabled = false;
  LocationPermission _permission = LocationPermission.denied;
  
  // LIVE TRACKING & MAP ENGINE STREAMS
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isLiveTrackingActive = false;
  final StreamController<Position> _engineStreamController = StreamController<Position>.broadcast();

  // SPEED SMOOTHING (For MapEngine)
  final List<double> _speedHistory = [];
  double _currentSpeedKmph = 0.0;
  static const int _smoothingWindow = 5; 

  // --- GETTERS ---
  Position? get currentPosition => _currentPosition;
  bool get hasValidLocation => _currentPosition != null;
  bool get isLiveTracking => _isLiveTrackingActive;
  double get currentSpeedKmph => _currentSpeedKmph;
  Stream<Position> get engineLocationStream => _engineStreamController.stream;

  // ==========================================
  // 1. APP STARTUP (ECO MODE)
  // ==========================================
  Future<void> initializeEcoLocation() async {
    _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!_isLocationServiceEnabled) return;

    _permission = await Geolocator.checkPermission();
    if (_permission == LocationPermission.denied) {
      _permission = await Geolocator.requestPermission();
      if (_permission == LocationPermission.denied || _permission == LocationPermission.deniedForever) return;
    }

    try {
      _currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high).timeout(const Duration(seconds: 4));
      notifyListeners(); 
    } catch (_) {}
  }

  // ==========================================
  // 2. ACTIVE MODE (LIVE NAVIGATION & SPEED)
  // ==========================================
  void startLiveTracking() {
    if (_isLiveTrackingActive) return;

    _isLiveTrackingActive = true;
    notifyListeners();

    // Custom Web Fallback (Because Web Stream is buggy)
    if (kIsWeb) {
      Timer.periodic(const Duration(seconds: 3), (timer) async {
        if (!_isLiveTrackingActive) {
          timer.cancel();
          return;
        }
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        _updatePositionAndSpeed(pos);
      });
      return;
    }

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3, 
      ),
    ).listen((Position position) {
      _updatePositionAndSpeed(position);
    });
  }

  void _updatePositionAndSpeed(Position position) {
    _currentPosition = position;
    
    // Speed Math
    double rawSpeed = (position.speed * 3.6).clamp(0.0, 240.0);
    _speedHistory.add(rawSpeed);
    if (_speedHistory.length > _smoothingWindow) _speedHistory.removeAt(0);
    _currentSpeedKmph = _speedHistory.reduce((a, b) => a + b) / _speedHistory.length;

    // Notify Map Engine & UI
    if (!_engineStreamController.isClosed) _engineStreamController.add(position);
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

  // Helpers
  Future<void> forceRefreshLocation() async => await initializeEcoLocation();

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _engineStreamController.close();
    super.dispose();
  }
}