import 'dart:async';
import 'package:flutter/foundation.dart';

enum MapMapType { defaultVector, satellite }

enum MapMode { explore, driving, transit, city3d }

class MapModeController {
  // ───── Granular ValueNotifiers (UI Optimization) ─────
  final ValueNotifier<MapMode> currentMode = ValueNotifier(MapMode.explore);
  final ValueNotifier<MapMapType> mapType =
      ValueNotifier(MapMapType.defaultVector);

  // Derived convenience notifiers (Updated atomically)
  final ValueNotifier<bool> isExploreMode = ValueNotifier(true);
  final ValueNotifier<bool> isDrivingMode = ValueNotifier(false);
  final ValueNotifier<bool> isTransitMode = ValueNotifier(false);
  final ValueNotifier<bool> is3DMode = ValueNotifier(false);
  final ValueNotifier<bool> isSatellite = ValueNotifier(false);

  // Detail toggles
  final ValueNotifier<bool> showTransitLayer = ValueNotifier(false);
  final ValueNotifier<bool> showTraffic = ValueNotifier(false);
  final ValueNotifier<bool> showPOIs = ValueNotifier(true);

  // Premium Transit States
  final ValueNotifier<bool> showTransitStations = ValueNotifier(true);
  final ValueNotifier<bool> showTransitLines = ValueNotifier(true);

  // ───── Rapid‑toggle protection (SEPARATE TIMERS TO PREVENT DEADLOCK) ─────
  bool _isApplyingModeChange = false;
  bool _isTogglingDetail = false;
  Timer? _modeDebounceTimer;
  Timer? _detailDebounceTimer;

  // ───── Mode switching with lock ─────
  void setMode(MapMode mode) {
    if (_isApplyingModeChange || currentMode.value == mode) {
      return; // Prevent redundant updates
    }
    _isApplyingModeChange = true;

    currentMode.value = mode;
    _updateDerivedModeNotifiers(mode);

    _modeDebounceTimer?.cancel();
    _modeDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      _isApplyingModeChange = false;
    });
  }

  void _updateDerivedModeNotifiers(MapMode mode) {
    isExploreMode.value = mode == MapMode.explore;
    isDrivingMode.value = mode == MapMode.driving;
    isTransitMode.value = mode == MapMode.transit;
    is3DMode.value = mode == MapMode.city3d;

    // Satellite + 3D combination fix (Auto-Fallback)
    if (mapType.value == MapMapType.satellite && mode == MapMode.city3d) {
      currentMode.value = MapMode.explore;
      is3DMode.value = false;
      isExploreMode.value = true;
    }
  }

  // ───── Map type (satellite / vector) ─────
  void setMapType(MapMapType type) {
    if (mapType.value == type) return;
    mapType.value = type;
    isSatellite.value = type == MapMapType.satellite;

    // 3D mode doesn’t work well on satellite – auto reset to Explore
    if (type == MapMapType.satellite && currentMode.value == MapMode.city3d) {
      setMode(MapMode.explore);
    }
  }

  // ───── Detail toggles with anti‑flood lock ─────
  void toggleTransitLayer() {
    if (_isTogglingDetail) return;
    _isTogglingDetail = true;
    showTransitLayer.value = !showTransitLayer.value;
    _resetDetailLock();
  }

  void toggleTraffic() {
    if (_isTogglingDetail) return;
    _isTogglingDetail = true;
    showTraffic.value = !showTraffic.value;
    _resetDetailLock();
  }

  void togglePOIs() {
    if (_isTogglingDetail) return;
    _isTogglingDetail = true;
    showPOIs.value = !showPOIs.value;
    _resetDetailLock();
  }

  void toggleTransitStations() {
    if (_isTogglingDetail) return;
    _isTogglingDetail = true;
    showTransitStations.value = !showTransitStations.value;
    _resetDetailLock();
  }

  void toggleTransitLines() {
    if (_isTogglingDetail) return;
    _isTogglingDetail = true;
    showTransitLines.value = !showTransitLines.value;
    _resetDetailLock();
  }

  void _resetDetailLock() {
    _detailDebounceTimer?.cancel();
    _detailDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      _isTogglingDetail = false;
    });
  }

  // ───── Bulletproof Lifecycle ─────
  void dispose() {
    _modeDebounceTimer?.cancel();
    _detailDebounceTimer?.cancel();

    currentMode.dispose();
    mapType.dispose();
    isExploreMode.dispose();
    isDrivingMode.dispose();
    isTransitMode.dispose();
    is3DMode.dispose();
    isSatellite.dispose();
    showTransitLayer.dispose();
    showTraffic.dispose();
    showPOIs.dispose();
    showTransitStations.dispose();
    showTransitLines.dispose();
  }
}
