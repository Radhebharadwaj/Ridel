import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/map/map_style_helper.dart';
import 'package:ridel/features/map/map_engine/map_engine.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';
import 'package:ridel/features/map/widgets/search_sheet/map_search_sheet.dart';
import 'package:ridel/core/providers/app_navigation_provider.dart';
import 'package:ridel/features/map/widgets/map_theme_selector.dart';
import 'package:ridel/features/map/widgets/weather_floating_widget.dart';
import 'package:ridel/features/map/widgets/quick_action_buttons.dart';
import 'package:ridel/features/map/widgets/turn_by_turn_banner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ridel/core/utils/toast_service.dart';

import 'package:ridel/core/config/app_config.dart';
import 'package:ridel/main.dart';

class FullScreenMapPage extends StatefulWidget {
  final ValueNotifier<double> searchSheetProgressNotifier;
  final bool isMapTabActive;

  const FullScreenMapPage({
    super.key,
    required this.searchSheetProgressNotifier,
    required this.isMapTabActive,
  });

  @override
  State<FullScreenMapPage> createState() => _FullScreenMapPageState();
}

class _FullScreenMapPageState extends State<FullScreenMapPage>
    with TickerProviderStateMixin {
  bool _hasSnappedToRealGps = false; // 🚀 Reactive GPS snap guard
  static int mapBuildCount = 0;
  final Set<String> _addedImages = {};
  late AnimationController _fadeScaleController;
  String? _loadedMapStyle;

  bool _isMapReady = false;
  bool _isMapReadyToLoad = false;
  bool _hasMapError = false;
  MapLibreMapController? _tempController;
  MapThemeType? _currentTheme;
  CameraPosition? _currentCameraPosition;
  bool _hasInitialCentered =
      false; // 🚀 Task 2: Guard flag for initial auto-center
  final GlobalKey _mapKey = GlobalKey(
      debugLabel:
          'primary_map_view'); // 🚀 Static GlobalKey to prevent WebGL context teardowns

  final ValueNotifier<bool> _showScaleBarNotifier = ValueNotifier(false);
  Timer? _scaleBarTimer;

  final ValueNotifier<String> _scaleTextNotifier = ValueNotifier('0 m');
  final ValueNotifier<double> _scaleWidthNotifier = ValueNotifier(60.0);

  // 🚀 ADAPTIVE LOD CONTROLLER
  bool _isPerformanceMode = false;

  // 🚀 WEB GESTURE SHIELDS
  DateTime _lastTapTime = DateTime.now();
  Timer? _webLongPressTimer;

  void _togglePerformanceMode(bool enable) {
    if (!mounted || _tempController == null || _isPerformanceMode == enable) {
      return;
    }
    _isPerformanceMode = enable;

    // Performance mode toggling logic omitted since heavyLayerIds was removed
  }

  void _onCameraMove(CameraPosition? position) {
    // 🚀 FAST PATH: Just update local variable, DO NOT trigger Flutter rebuilds here!
    _currentCameraPosition = position;
  }

  void _onCameraIdle() {
    _togglePerformanceMode(
        false); // 🚀 Restore premium visuals once DOM has settled
    _onCameraIdleScaleBar();

    // 🚀 Update the LocationProvider so the rest of the app knows where the map is
    if (_currentCameraPosition != null) {
      final cam = _currentCameraPosition!;
      final currentZoom = cam.zoom;
      final lat = cam.target.latitude;

      double metersPerPixel =
          156543.03392 * cos(lat * pi / 180.0) / pow(2, currentZoom);
      double maxPixelWidth = 80.0;
      double maxMeters = metersPerPixel * maxPixelWidth;

      const scaleValues = [
        10,
        20,
        50,
        100,
        200,
        500,
        1000,
        2000,
        5000,
        10000,
        20000,
        50000,
        100000,
        200000,
        500000,
        1000000
      ];

      int chosenMeters = 10;
      for (int v in scaleValues) {
        if (v <= maxMeters) {
          chosenMeters = v;
        } else {
          break;
        }
      }

      double newWidth = chosenMeters / metersPerPixel;
      String newText = chosenMeters >= 1000
          ? '${chosenMeters ~/ 1000} km'
          : '$chosenMeters m';

      if (!mounted) return;
      _showScaleBarNotifier.value = true;
      _scaleTextNotifier.value = newText;
      _scaleWidthNotifier.value = newWidth.clamp(20.0, 150.0);

      _scaleBarTimer?.cancel();
      _scaleBarTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) _showScaleBarNotifier.value = false;
      });
    }

    // 🚀 Defer the state update until AFTER the current rendering frame finishes
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final mapProvider = Provider.of<MapProvider>(context, listen: false);
      final ctrl = mapProvider.controller ?? _tempController;
      if (ctrl != null) {
        try {
          final bounds = await ctrl.getVisibleRegion();
          LatLng? userLoc = mapProvider.currentLocation;
          if (userLoc != null) {
            bool isVisible = bounds.contains(userLoc);
            mapProvider.setUserVisibility(isVisible);
          }

          // Notify engine about zoom updates for UI scaling
          if (_currentCameraPosition != null) {
            mapProvider.updateMapCenter(
                _currentCameraPosition!.target, _currentCameraPosition!.zoom);
          } else {
            final cam = ctrl.cameraPosition;
            if (cam != null) {
              mapProvider.updateMapCenter(cam.target, cam.zoom);
            }
          }
        } catch (_) {}
      }
    });
  }

  void _onCameraIdleScaleBar() {
    if (_currentCameraPosition != null) {
      final cam = _currentCameraPosition!;
      final currentZoom = cam.zoom;
      final lat = cam.target.latitude;

      double metersPerPixel =
          156543.03392 * cos(lat * pi / 180.0) / pow(2, currentZoom);
      double maxPixelWidth = 80.0;
      double maxMeters = metersPerPixel * maxPixelWidth;

      const scaleValues = [
        10,
        20,
        50,
        100,
        200,
        500,
        1000,
        2000,
        5000,
        10000,
        20000,
        50000,
        100000,
        200000,
        500000,
        1000000
      ];

      int chosenMeters = 10;
      for (int v in scaleValues) {
        if (v <= maxMeters) {
          chosenMeters = v;
        } else {
          break;
        }
      }

      double newWidth = chosenMeters / metersPerPixel;
      String newText = chosenMeters >= 1000
          ? '${chosenMeters ~/ 1000} km'
          : '$chosenMeters m';

      if (!mounted) return;
      _showScaleBarNotifier.value = true;
      _scaleTextNotifier.value = newText;
      _scaleWidthNotifier.value = newWidth.clamp(20.0, 150.0);

      _scaleBarTimer?.cancel();
      _scaleBarTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) _showScaleBarNotifier.value = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint("🛠️ MAP LIFECYCLE: initState called.");
    _fadeScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    widget.searchSheetProgressNotifier.addListener(_onProgressChanged);

    // 🚀 NEW: Eager Weather Fetch has been moved to global_location_service.dart to ensure City-First Gating

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();

      final mapProvider = Provider.of<MapProvider>(context, listen: false);
      mapProvider.addListener(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_hasInitialCentered && mapProvider.currentLocation != null) {
            _attemptInitialCameraCenter();
          }
        });
      });

      // 🚀 REACTIVE PERMISSION HOOK: Snap to real GPS the instant it arrives
      final locService =
          Provider.of<GlobalLocationService>(context, listen: false);
      locService.addListener(() {
        final pos = locService.currentPosition;
        final ctrl = mapProvider.controller ?? _tempController;
        if (pos == null || ctrl == null) return;

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;

          // Only react if we have explicit permission and a valid coordinate
          final bool isVerifiedPhysicalGps =
              _isVerifiedPhysicalGps(pos, locService.hasLocationPermission);

          if (!isVerifiedPhysicalGps) {
            // Ensure tracking is off. If camera is somehow at street level, pull it up to 10.5
            try {
              ctrl.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
            } catch (_) {}
            final currentZoom = ctrl.cameraPosition?.zoom ?? 0.0;
            if (!_hasInitialCentered || currentZoom > 11.0) {
              _hasInitialCentered = true;
              await _safeAnimateCamera(
                LatLng(pos.latitude, pos.longitude),
                10.5,
                duration: const Duration(milliseconds: 800),
              );
            }
            return;
          }

          // Snipe ONLY if this is the first time we've verified real GPS
          if (isVerifiedPhysicalGps && !_hasSnappedToRealGps) {
            _hasSnappedToRealGps = true;
            _hasInitialCentered = true;

            if (!mapProvider.isRouteCalculated &&
                !mapProvider.isActiveNavigation) {
              try {
                ctrl.updateMyLocationTrackingMode(
                    MyLocationTrackingMode.tracking);
              } catch (_) {}
            }
            await Future.delayed(
                const Duration(milliseconds: 250)); // Allow puck to render

            await _safeAnimateCamera(
              LatLng(pos.latitude, pos.longitude),
              15.5,
              duration: const Duration(milliseconds: 1200),
            );

            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted &&
                  ctrl == (_tempController ?? mapProvider.controller)) {
                try {
                  ctrl.updateMyLocationTrackingMode(
                      MyLocationTrackingMode.none);
                } catch (_) {}
              }
            });
          }
        });
      });

      locService.currentCityName.addListener(() {
        final cityName = locService.currentCityName.value;
        final pos = locService.currentPosition;
        final ctrl =
            Provider.of<MapProvider>(context, listen: false).controller ??
                _tempController;

        if (ctrl == null || !mounted || cityName.trim().isEmpty) return;

        // 🛡️ GOLDEN RULE: If we lack verified high-precision physical GPS (< 100m accuracy + permission),
        // we MUST anchor over the resolved App Header city at strictly Zoom 10.5 (5km scale)!
        final bool isPhysicalGps = pos != null &&
            !pos.isMocked &&
            locService.hasLocationPermission &&
            pos.accuracy <= 150.0;

        if (!isPhysicalGps && pos != null) {
          debugPrint(
              "🏙️ [Header City Anchor] Header resolved '$cityName'. Anchoring camera at 5km regional overview (Zoom 10.5).");
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await _safeAnimateCamera(
              LatLng(pos.latitude, pos.longitude),
              10.5, // Strictly hold at regional 5km overview
              duration: const Duration(milliseconds: 1000),
            );
          });
        }
      });
    });
  }

  Future<void> _attemptInitialCameraCenter() async {
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    if (_hasInitialCentered || _tempController == null) return;

    final location = mapProvider.currentLocation;
    if (location != null && location.latitude != 0.0) {
      _hasInitialCentered = true;
      final locService =
          Provider.of<GlobalLocationService>(context, listen: false);
      final bool isPhysicalGps = _isVerifiedPhysicalGps(
          locService.currentPosition, locService.hasLocationPermission);

      try {
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;

        if (isPhysicalGps && !_hasSnappedToRealGps) {
          // 🚀 STAGE 1: VERIFIED HIGH-PRECISION GPS -> Allow Street Snipe
          _hasSnappedToRealGps = true;
          // Unlock the shield
          if (!mapProvider.isRouteCalculated &&
              !mapProvider.isActiveNavigation) {
            try {
              await _tempController!.updateMyLocationTrackingMode(
                  MyLocationTrackingMode.tracking);
            } catch (_) {}
          }
          await Future.delayed(const Duration(milliseconds: 250));
          if (!mounted) return;

          await _safeAnimateCamera(
            LatLng(location.latitude, location.longitude),
            15.5,
            duration: const Duration(milliseconds: 1200),
          );
        } else {
          // 🚀 STAGE 2: UNPERMISSIONED OR LOW-PRECISION IP -> Strictly hold at 5km+ altitude
          debugPrint(
              "⏳ [Startup] Low precision or unpermissioned. Anchoring at regional zoom 10.5.");
          // Keep shield locked!
          try {
            await _tempController!
                .updateMyLocationTrackingMode(MyLocationTrackingMode.none);
          } catch (_) {}
          await _safeAnimateCamera(
            LatLng(location.latitude, location.longitude),
            10.5,
            duration: const Duration(milliseconds: 800),
          );
        }
      } catch (e) {
        debugPrint("❌ Initial camera snap intercepted: $e");
      }
    }
  }

  Future<void> _initializeApp() async {
    // 1. Purana kachra saaf kar
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // 2. Chabi fetch kar (Map ko wait karwa)
    await AppConfig.fetchKeys();

    // 3. Check kar ki kya chabi sach mein aayi?
    if (AppConfig.olaMapsKey.isNotEmpty && AppConfig.olaMapsKey != "2") {
      if (mounted) {
        setState(() {
          _isMapReadyToLoad = true; // Chabi mil gayi, ab map dikha
        });
      }
      await _initMapStyle();
    } else {
      debugPrint("CRITICAL ERROR: Key fetch fail ho gayi ya null hai!");
      if (mounted) {
        setState(() {
          _hasMapError = true;
          _isMapReadyToLoad =
              true; // Show the map error UI instead of loader loop
          _isMapReady = true;
        });
      }
    }

    if (mounted) {
      setState(() {
        _isMapReady = true;
      });
    }
  }

  void _onProgressChanged() {
    final progress = widget.searchSheetProgressNotifier.value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (progress > 0.8 &&
          _fadeScaleController.status != AnimationStatus.forward &&
          _fadeScaleController.status != AnimationStatus.completed) {
        _fadeScaleController.forward();
      } else if (progress <= 0.8 &&
          _fadeScaleController.status != AnimationStatus.reverse &&
          _fadeScaleController.status != AnimationStatus.dismissed) {
        _fadeScaleController.reverse();
      }
    });
  }

  @override
  void dispose() {
    debugPrint(
        "🛠️ MAP LIFECYCLE: dispose called. WebGL context tearing down.");
    _tempController?.dispose();
    _showScaleBarNotifier.dispose();
    _scaleTextNotifier.dispose();
    _scaleWidthNotifier.dispose();
    widget.searchSheetProgressNotifier.removeListener(_onProgressChanged);
    _fadeScaleController.dispose();
    _scaleBarTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 🚀 Task 2: Bind System/App Appearance Change Listener
    // Automatically trigger the map style push when Theme.of(context).brightness changes
    final isSystemDark = Theme.of(context).brightness == Brightness.dark;
    final systemTheme = isSystemDark ? MapThemeType.dark : MapThemeType.light;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = Provider.of<MapProvider>(context, listen: false);
        final themeToSet = _currentTheme ?? systemTheme;
        provider.setTheme(themeToSet);
      }
    });
  }

  Future<void> _initMapStyle({bool updateExisting = false}) async {
    if (!mounted) return;
    if (!updateExisting) {
      // Intentionally left blank, state update removed as variable was unused
    }

    try {
      final isSystemDark = Theme.of(context).brightness == Brightness.dark;
      final isDark = _currentTheme != null
          ? (_currentTheme == MapThemeType.dark)
          : isSystemDark;
      final style = await MapStyleHelper.getOlaStyle(isSystemDark,
          themeType: _currentTheme);

      if (mounted) {
        setState(() {
          _loadedMapStyle = style;
        });

        final themeToSet =
            _currentTheme ?? (isDark ? MapThemeType.dark : MapThemeType.light);
        Provider.of<MapProvider>(context, listen: false).setTheme(themeToSet);
      }
    } catch (e) {
      debugPrint("❌ Error fixing Ola Style: $e");
      // removed empty setState
    }
  }

  @override
  Widget build(BuildContext context) {
    mapBuildCount++;
    debugPrint(
        "🛠️ MAP LIFECYCLE: build called (Count: $mapBuildCount). If this prints rapidly, we have a setState loop!");
    final bool isDesktop = MediaQuery.of(context).size.width >= 600;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final double topMargin =
        isDesktop ? 32.0 : MediaQuery.of(context).padding.top + 24.0;
    final double sideMargin = isDesktop ? 32.0 : 28.0;

    if (!_isMapReadyToLoad) {
      return const SizedBox
          .shrink(); // 🚀 Let the custom premium loader handle the UI
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      resizeToAvoidBottomInset: false,
      body: (!_isMapReady || _loadedMapStyle == null)
          ? const Center(child: PremiumMapSkeleton())
          : Stack(
              children: [
                Positioned.fill(
                  child: Builder(
                    builder: (context) {
                      if (_hasMapError) {
                        return Center(
                          child: Text(
                            "Failed to load map",
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black54,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        );
                      }

                      // Calculate safe initial position BEFORE passing it to MapLibre
                      final mapProvider =
                          Provider.of<MapProvider>(context, listen: false);
                      final userCurrentLocation = mapProvider.currentLocation;
                      final locService = Provider.of<GlobalLocationService>(
                          context,
                          listen: false);
                      final hasLocationPermission =
                          context.select<GlobalLocationService, bool>(
                              (s) => s.hasLocationPermission);
                      final currentPos = locService.currentPosition;
                      final bool isRealGps = _isVerifiedPhysicalGps(
                          currentPos, hasLocationPermission);

                      // 🚀 TASK 1: Dynamic Native Puck Visibility
                      final isRouteActive = context.select<MapProvider, bool>(
                          (p) => p.isRouteCalculated || p.isActiveNavigation);

                      final double safeLat =
                          userCurrentLocation?.latitude ?? 21.1458;
                      final double safeLng =
                          userCurrentLocation?.longitude ?? 79.0882;

                      debugPrint(
                          "🛠️ DEBUG INITIAL CAMERA: Lat:$safeLat, Lng:$safeLng");

                      return RepaintBoundary(
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: (PointerDownEvent event) {
                            // 🚀 INSTANT KILL-SWITCH
                            final mapProvider = Provider.of<MapProvider>(
                                context,
                                listen: false);
                            if (mapProvider.isAutoTracking) {
                              mapProvider.setAutoTracking(false);
                            }

                            // 🚀 TASK 2: SYNTHETIC WEB LONG-PRESS
                            if (kIsWeb) {
                              _webLongPressTimer?.cancel();
                              _webLongPressTimer = Timer(
                                  const Duration(milliseconds: 500), () async {
                                if (!mounted ||
                                    mapProvider.controller == null) {
                                  return;
                                }

                                if (mapProvider.isActiveNavigation ||
                                    mapProvider.engine.mapUIState.value ==
                                        MapUIState.navigating) {
                                  debugPrint(
                                      "Web simulated long-click ignored: Active navigation shield is ON.");
                                  return;
                                }

                                LatLng point = await mapProvider.controller!
                                    .toLatLng(Point(event.localPosition.dx,
                                        event.localPosition.dy));
                                mapProvider.setAutoTracking(false);
                                mapProvider.setUserPanning(true);
                                if (mapProvider.mapSelectionPlaceType != null) {
                                  mapProvider.setTargetDestination(point);
                                  mapProvider.addNativeDestinationPin(point);
                                } else {
                                  mapProvider.handleMapLongPress(point);
                                }
                              });
                            }
                          },
                          onPointerUp: (_) => _webLongPressTimer?.cancel(),
                          onPointerMove: (_) => _webLongPressTimer?.cancel(),
                          child: MapLibreMap(
                            key: _mapKey,
                            initialCameraPosition: const CameraPosition(
                              target: LatLng(28.6139,
                                  77.2090), // Default Regional Overview
                              zoom:
                                  10.5, // 🚀 Hard lock initial frame to >5km altitude
                            ),
                            styleString: _loadedMapStyle!,
                            // 🚀 CRITICAL FIX: Synchronize RenderMode with Enabled state
                            myLocationEnabled: isRealGps && !isRouteActive,
                            myLocationRenderMode: MyLocationRenderMode.normal,
                            myLocationTrackingMode: MyLocationTrackingMode.none,
                            minMaxZoomPreference:
                                const MinMaxZoomPreference(3.0, 18.5),
                            cameraTargetBounds: CameraTargetBounds(
                              LatLngBounds(
                                southwest: const LatLng(6.5,
                                    68.0), // Bottom-Left (Arabian Sea / Indian Ocean)
                                northeast: const LatLng(37.5,
                                    97.5), // Top-Right (Himalayas / North East)
                              ),
                            ),
                            onMapCreated: (controller) {
                              debugPrint(
                                  "✅ MAP ENGINE: onMapCreated fired. WebGL context locked.");
                              if (_tempController != null) return;
                              _tempController = controller;

                              final mapProvider = Provider.of<MapProvider>(
                                  context,
                                  listen: false);

                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                // 🚀 CRITICAL FIX 1: Engine ko controller pass karna zaroori hai!
                                mapProvider.engine.mapController = controller;
                                // Call proactive permission request and snap
                                mapProvider.initializeMapAndPermissions();
                              });

                              // 🚀 TASK 3: Explicitly sync initial theme on map startup
                              final isSystemDark =
                                  Theme.of(context).brightness ==
                                      Brightness.dark;
                              MapStyleHelper.getOlaStyle(
                                isSystemDark,
                                themeType: mapProvider.currentTheme,
                                showLabels: mapProvider.showLabels,
                                showPOIs: mapProvider.showPOIs,
                              ).then((styleString) {
                                controller.setStyle(styleString);
                              }).catchError((e) {
                                debugPrint("❌ Failed to set initial style: $e");
                              });

                              // Removed premature camera animation to prevent WebGL style race condition
                            },
                            onStyleLoadedCallback: () async {
                              final controller = _tempController;
                              if (controller == null) return;

                              // 🚀 CRITICAL FIX: Clear the image registry on every style reload!
                              // WebGL loses all textures when the style is swapped, so we must
                              // re-register every sprite from scratch.
                              _addedImages.clear();

                              Future<void> safeAddImage(
                                  String? id, Uint8List bytes) async {
                                if (id == null || id.trim().isEmpty) return;
                                if (_addedImages.contains(id)) {
                                  return; // Use boolean flag check to prevent JS interop calls
                                }
                                try {
                                  await controller.addImage(id, bytes);
                                  _addedImages.add(id);
                                } catch (e) {
                                  // Ignore if it already exists or fails
                                  debugPrint("Image add warning: $e");
                                }
                              }

                              try {
                                final Uint8List bytes =
                                    await MapProvider.loadAndResizeImage(
                                        'assets/images/custom_pin.png', 36);
                                await safeAddImage('custom_pin', bytes);
                              } catch (_) {}

                              try {
                                final Uint8List yellowPinBytes =
                                    await MapProvider.loadAndResizeImage(
                                        'assets/images/add_places.png', 32);
                                await safeAddImage(
                                    'intermediate_pin', yellowPinBytes);
                              } catch (_) {}

                              try {
                                // 🚀 CRITICAL FIX: Resize nav_puck to 40 pixels to prevent WebGL crash and giant icon bug!
                                final Uint8List puckBytes =
                                    await MapProvider.loadAndResizeImage(
                                        'assets/images/nav_puck.png', 40);
                                await safeAddImage('nav_puck', puckBytes);
                                debugPrint(
                                    "✅ Nav Puck Image successfully injected and resized");
                              } catch (e) {
                                debugPrint(
                                    "Safe Web Sprite Notice (nav_puck): $e");
                              }

                              try {
                                final Uint8List transparentPixel =
                                    Uint8List.fromList([
                                  137,
                                  80,
                                  78,
                                  71,
                                  13,
                                  10,
                                  26,
                                  10,
                                  0,
                                  0,
                                  0,
                                  13,
                                  73,
                                  72,
                                  68,
                                  82,
                                  0,
                                  0,
                                  0,
                                  1,
                                  0,
                                  0,
                                  0,
                                  1,
                                  8,
                                  6,
                                  0,
                                  0,
                                  0,
                                  31,
                                  21,
                                  196,
                                  137,
                                  0,
                                  0,
                                  0,
                                  11,
                                  73,
                                  68,
                                  65,
                                  84,
                                  8,
                                  215,
                                  99,
                                  96,
                                  0,
                                  2,
                                  0,
                                  0,
                                  5,
                                  0,
                                  1,
                                  226,
                                  38,
                                  5,
                                  155,
                                  0,
                                  0,
                                  0,
                                  0,
                                  73,
                                  69,
                                  78,
                                  68,
                                  174,
                                  66,
                                  96,
                                  130
                                ]);
                                await safeAddImage('Arrow', transparentPixel);
                              } catch (_) {}

                              try {
                                final Uint8List transparentPixel =
                                    Uint8List.fromList([
                                  137,
                                  80,
                                  78,
                                  71,
                                  13,
                                  10,
                                  26,
                                  10,
                                  0,
                                  0,
                                  0,
                                  13,
                                  73,
                                  72,
                                  68,
                                  82,
                                  0,
                                  0,
                                  0,
                                  1,
                                  0,
                                  0,
                                  0,
                                  1,
                                  8,
                                  6,
                                  0,
                                  0,
                                  0,
                                  31,
                                  21,
                                  196,
                                  137,
                                  0,
                                  0,
                                  0,
                                  11,
                                  73,
                                  68,
                                  65,
                                  84,
                                  8,
                                  215,
                                  99,
                                  96,
                                  0,
                                  2,
                                  0,
                                  0,
                                  5,
                                  0,
                                  1,
                                  226,
                                  38,
                                  5,
                                  155,
                                  0,
                                  0,
                                  0,
                                  0,
                                  73,
                                  69,
                                  78,
                                  68,
                                  174,
                                  66,
                                  96,
                                  130
                                ]);
                                await safeAddImage('arrow', transparentPixel);
                              } catch (_) {}

                              try {
                                final Uint8List transparentPixel =
                                    Uint8List.fromList([
                                  137,
                                  80,
                                  78,
                                  71,
                                  13,
                                  10,
                                  26,
                                  10,
                                  0,
                                  0,
                                  0,
                                  13,
                                  73,
                                  72,
                                  68,
                                  82,
                                  0,
                                  0,
                                  0,
                                  1,
                                  0,
                                  0,
                                  0,
                                  1,
                                  8,
                                  6,
                                  0,
                                  0,
                                  0,
                                  31,
                                  21,
                                  196,
                                  137,
                                  0,
                                  0,
                                  0,
                                  11,
                                  73,
                                  68,
                                  65,
                                  84,
                                  8,
                                  215,
                                  99,
                                  96,
                                  0,
                                  2,
                                  0,
                                  0,
                                  5,
                                  0,
                                  1,
                                  226,
                                  38,
                                  5,
                                  155,
                                  0,
                                  0,
                                  0,
                                  0,
                                  73,
                                  69,
                                  78,
                                  68,
                                  174,
                                  66,
                                  96,
                                  130
                                ]);
                                await safeAddImage(
                                    'custom-marker', transparentPixel);
                              } catch (e) {
                                debugPrint("Sprite pre-load handled: $e");
                              }

                              try {
                                // Ensure ALL required images are added to WebGL texture memory BEFORE any layer uses them
                                final List<String> requiredSpriteIds = [
                                  'custom_pin',
                                  'intermediate_pin',
                                  'nav_puck',
                                  'Arrow',
                                  'arrow',
                                  'custom-marker'
                                ];
                                for (final id in requiredSpriteIds) {
                                  if (!_addedImages.contains(id)) {
                                    try {
                                      // Register transparent pixel as fallback to prevent WebGL crash
                                      final Uint8List transparentPixel =
                                          Uint8List.fromList([
                                        137,
                                        80,
                                        78,
                                        71,
                                        13,
                                        10,
                                        26,
                                        10,
                                        0,
                                        0,
                                        0,
                                        13,
                                        73,
                                        72,
                                        68,
                                        82,
                                        0,
                                        0,
                                        0,
                                        1,
                                        0,
                                        0,
                                        0,
                                        1,
                                        8,
                                        6,
                                        0,
                                        0,
                                        0,
                                        31,
                                        21,
                                        196,
                                        137,
                                        0,
                                        0,
                                        0,
                                        11,
                                        73,
                                        68,
                                        65,
                                        84,
                                        8,
                                        215,
                                        99,
                                        96,
                                        0,
                                        2,
                                        0,
                                        0,
                                        5,
                                        0,
                                        1,
                                        226,
                                        38,
                                        5,
                                        155,
                                        0,
                                        0,
                                        0,
                                        0,
                                        73,
                                        69,
                                        78,
                                        68,
                                        174,
                                        66,
                                        96,
                                        130
                                      ]);
                                      await controller.addImage(
                                          id, transparentPixel);
                                      _addedImages.add(id);
                                    } catch (e) {
                                      debugPrint(
                                          "Sprite registration barrier: $e");
                                    }
                                  }
                                }
                                debugPrint(
                                    "✅ WebGL Sprite Registry fully verified. Safe to render layers.");
                              } catch (e) {
                                debugPrint(
                                    "⚠️ Sprite registration barrier notice: $e");
                              }

                              if (!context.mounted) return;
                              final mapProvider = Provider.of<MapProvider>(
                                  context,
                                  listen: false);
                              await mapProvider.engine.onMapCreated(
                                  controller,
                                  isDark,
                                  Provider.of<GlobalLocationService>(context,
                                      listen: false),
                                  this);

                              // 🚀 Task 1: Re-inject location tracking cleanly after style loads
                              try {
                                if (!context.mounted) return;
                                final locSvc =
                                    Provider.of<GlobalLocationService>(context,
                                        listen: false);
                                final pos = locSvc.currentPosition;
                                final bool isRealGps = pos != null &&
                                    !pos.isMocked &&
                                    mapProvider.hasLocationPermission;

                                if (isRealGps) {
                                  final isRouteActive =
                                      mapProvider.isRouteCalculated ||
                                          mapProvider.isActiveNavigation;
                                  if (!isRouteActive) {
                                    try {
                                      await controller
                                          .updateMyLocationTrackingMode(kIsWeb
                                              ? MyLocationTrackingMode.tracking
                                              : MyLocationTrackingMode
                                                  .trackingCompass);
                                    } catch (_) {}
                                  }
                                } else {
                                  try {
                                    await controller
                                        .updateMyLocationTrackingMode(
                                            MyLocationTrackingMode.none);
                                  } catch (_) {}
                                }
                              } catch (e) {
                                debugPrint(
                                    "❌ Puck restoration intercepted: $e");
                              }

                              // 🚀 Task 2: Auto-center on startup
                              if (!context.mounted) return;
                              final locSvc = Provider.of<GlobalLocationService>(
                                  context,
                                  listen: false);
                              final currentPos = locSvc.currentPosition;

                              if (currentPos != null &&
                                  _isVerifiedPhysicalGps(currentPos,
                                      locSvc.hasLocationPermission)) {
                                await _attemptInitialCameraCenter();
                              } else {
                                // Keep map firmly locked at initialCameraPosition (Zoom 10.5)
                                debugPrint(
                                    "⏳ [Startup] Holding at regional zoom 10.5 until exact GPS is verified.");
                              }
                            },
                            onMapClick: (point, latLng) async {
                              _lastTapTime =
                                  DateTime.now(); // 🚀 TASK 1: UPDATE DEBOUNCER
                              FocusScope.of(context).unfocus();
                              final mapProvider = Provider.of<MapProvider>(
                                  context,
                                  listen: false);

                              // 🚀 STRICT GUARD CLAUSE: Prevent accidental pin drops during active routing
                              if (mapProvider.isActiveNavigation ||
                                  mapProvider.engine.mapUIState.value ==
                                      MapUIState.navigating) {
                                debugPrint(
                                    "Map click ignored: Active navigation shield is ON.");
                                return;
                              }

                              // 1. Break tracking immediately to avoid snap-back on pin drop
                              if (mapProvider.controller != null) {
                                await mapProvider.controller!
                                    .updateMyLocationTrackingMode(
                                        MyLocationTrackingMode.none);
                              }

                              // PIN DROP LOGIC MOVED EXCLUSIVELY TO onMapLongClick

                              if (mapProvider.isFlying) {
                                mapProvider.stopCameraFlight();
                                return;
                              }

                              // 🚀 FIX: Guard against clearing destination state when a place/route is active.
                              // On web, onMapClick fires AFTER the synthetic long-press timer,
                              // which would nuke the targetDestination just set by the pin-drop flow.
                              final currentUIState =
                                  mapProvider.engine.mapUIState.value;
                              if (currentUIState == MapUIState.placeSelected ||
                                  currentUIState == MapUIState.routeDrawn ||
                                  mapProvider.isDestinationSelected) {
                                debugPrint(
                                    "Map click ignored: Destination is already selected (UIState: $currentUIState).");
                                return;
                              }

                              bool handled = await mapProvider.handleRouteClick(
                                  point, latLng);
                              if (!handled) {
                                mapProvider.clearTargetLocation();
                              }
                            },
                            onMapLongClick: (Point<double> point,
                                LatLng coordinates) async {
                              // 🚀 TASK 1: DOUBLE-TAP SHIELD
                              if (DateTime.now()
                                      .difference(_lastTapTime)
                                      .inMilliseconds <
                                  500) {
                                debugPrint(
                                    "Long-click BLOCKED by Double-Tap Shield.");
                                return;
                              }

                              final mapProvider = Provider.of<MapProvider>(
                                  context,
                                  listen: false);

                              // 🚀 STRICT GUARD CLAUSE: Prevent accidental pin drops during active routing
                              if (mapProvider.isActiveNavigation ||
                                  mapProvider.engine.mapUIState.value ==
                                      MapUIState.navigating) {
                                debugPrint(
                                    "Map long-click ignored: Active navigation shield is ON.");
                                return;
                              }

                              // 🚀 Free the camera from blue dot
                              mapProvider.setAutoTracking(false);
                              mapProvider.setUserPanning(true);

                              // 🚀 EXCLUSIVE PIN DROP DELEGATION
                              if (mapProvider.mapSelectionPlaceType != null) {
                                mapProvider.setTargetDestination(coordinates);
                                mapProvider
                                    .addNativeDestinationPin(coordinates);
                                return;
                              }

                              // 1. Always allow placing the visual destination pin and UI sheet!
                              mapProvider.handleMapLongPress(coordinates);

                              // 2. Only attempt auto-routing if physical GPS is actively verified
                              final locService =
                                  Provider.of<GlobalLocationService>(context,
                                      listen: false);
                              final bool isPhysicalGps = locService
                                      .hasLocationPermission &&
                                  locService.currentPosition != null &&
                                  !locService.currentPosition!.isMocked &&
                                  locService.currentPosition!.accuracy <= 150.0;

                              if (isPhysicalGps) {
                                mapProvider.calculateAndDrawNativeRoute(
                                    context, 'driving',
                                    isAutoTriggered: true);
                              } else {
                                debugPrint(
                                    "📍 [Pin Drop] Pin placed successfully. Auto-routing skipped until GPS is enabled.");
                              }
                            },

                            compassEnabled: false,
                            doubleClickZoomEnabled: true,
                            scrollGesturesEnabled: true,
                            zoomGesturesEnabled: true,
                            tiltGesturesEnabled: true,

                            // Removed duplicate myLocationEnabled

                            trackCameraPosition: false,

                            logoViewMargins: const Point(-5000, -5000),
                            attributionButtonMargins: const Point(-5000, -5000),
                            onCameraTrackingDismissed: () {
                              final mapProvider = Provider.of<MapProvider>(
                                  context,
                                  listen: false);
                              if (mapProvider.isActiveNavigation) {
                                mapProvider.setAutoTracking(false);
                                mapProvider.setUserPanning(true);
                              }
                              mapProvider.engine.onUserPannedMap();
                            },
                            onUserLocationUpdated: (location) {
                              if (!mounted) return;
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) async {
                                if (!context.mounted) return;
                                final mapProvider = Provider.of<MapProvider>(
                                    context,
                                    listen: false);
                                mapProvider
                                    .updateCurrentLocation(location.position);

                                // 🚀 ABSOLUTE LOCKDOWN: DO NOT AUTO-ZOOM HERE!
                                // We only allow zooming via explicit button taps or when the permission state machine
                                // in _attemptInitialCameraCenter actively verifies real GPS and mounts the Blue Dot.
                              });
                            },
                            onCameraIdle: _onCameraIdle,
                            onCameraMove: (position) {
                              if (!_isPerformanceMode) {
                                _togglePerformanceMode(
                                    true); // 🚀 Instantly drop complexity to save CPU/GPU for the panning animation
                              }
                              _onCameraMove(position);
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // 🚀 DROP PIN MODE CENTER OVERLAY
                Positioned.fill(
                  child: Selector<MapProvider, bool>(
                    selector: (context, provider) =>
                        provider.isDropPinMode || provider.isAddingStopMode,
                    builder: (context, showPin, child) {
                      if (!showPin) return const SizedBox.shrink();

                      return IgnorePointer(
                        child: Center(
                          child: FractionalTranslation(
                            // Shift it up by half its height so the bottom tip points to the exact center
                            translation: const Offset(0.0, -0.5),
                            child: Image.asset(
                              'assets/images/add_places.png',
                              height: 48,
                              width: 48,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // 🚀 0. SIRI-STYLE EDGE GLOW FOR TTS
                Positioned.fill(
                  child: IgnorePointer(
                    child: Selector<MapProvider, ValueNotifier<bool>>(
                      selector: (context, provider) => provider.isSpeaking,
                      builder: (context, isSpeakingNotifier, _) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: isSpeakingNotifier,
                          builder: (context, isSpeaking, _) {
                            // 🚀 FIX: Completely unmount from memory when not speaking
                            if (!isSpeaking) return const SizedBox.shrink();

                            return AnimatedOpacity(
                              duration: const Duration(milliseconds: 600),
                              curve: Curves.easeInOutCubic,
                              opacity: 1.0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.cyan.withValues(alpha: 0.15),
                                      blurRadius: 40,
                                      spreadRadius: 10,
                                    ),
                                    BoxShadow(
                                      color: Colors.purpleAccent
                                          .withValues(alpha: 0.15),
                                      blurRadius: 40,
                                      spreadRadius: -10,
                                    ),
                                  ],
                                  border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.8),
                                      width: kIsWeb ? 4.0 : 8.0),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),

                if (MediaQuery.sizeOf(context).width < 800)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: Builder(
                        builder: (context) {
                          final sheet = MapSearchSheet(
                            key: const ValueKey('map_search_sheet'),
                            isMapTabActive: widget.isMapTabActive,
                            onSearchModeChanged: (isActive) {},
                            onSearchSubmitted: (query) {},
                            onProgressChanged: (progress) {
                              if (mounted) {
                                widget.searchSheetProgressNotifier.value =
                                    progress;
                              }
                            },
                            onBackToPreviousTab: () {
                              Provider.of<AppNavigationProvider>(context,
                                      listen: false)
                                  .goBack();
                            },
                          );
                          return sheet;
                        },
                      ),
                    ),
                  ),

                // 🚀 1. SMOOTH WEATHER WIDGET (Mobile = Top Left, Desktop = Top Right)
                ValueListenableBuilder<bool>(
                  valueListenable: globalSidebarOpen,
                  builder: (context, isSidebarExpanded, _) {
                    return AnimatedPositioned(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        top: isDesktop
                            ? 16.0
                            : MediaQuery.paddingOf(context).top + 16.0,
                        left: isDesktop ? null : 16.0,
                        right: isDesktop ? 16.0 : null,
                        child: ValueListenableBuilder<double>(
                          valueListenable: widget.searchSheetProgressNotifier,
                          builder: (context, progress, _) {
                            double opacity = (progress <= 0.45)
                                ? 1.0
                                : (1.0 - ((progress - 0.45) / (0.90 - 0.45)))
                                    .clamp(0.0, 1.0);

                            return Selector<MapProvider, bool>(
                              selector: (context, provider) =>
                                  !provider.isActiveNavigation,
                              builder: (context, showWeather, child) {
                                final finalOpacity =
                                    showWeather ? opacity : 0.0;
                                return IgnorePointer(
                                  ignoring: finalOpacity == 0.0,
                                  child: Opacity(
                                    opacity: finalOpacity,
                                    child: child,
                                  ),
                                );
                              },
                              child: Builder(
                                builder: (context) {
                                  final weather = WeatherFloatingWidget(
                                      onMapThemeChanged: (isDark) {});
                                  return weather;
                                },
                              ),
                            );
                          },
                        ));
                  },
                ),

                // 🚀 2. PREMIUM SCALE BAR (Mobile = Top Right, Desktop = Bottom Left)
                ValueListenableBuilder<bool>(
                    valueListenable: globalSidebarOpen,
                    builder: (context, isSidebarOpen, _) {
                      // Exact placement logic based on device
                      final double? topOffset = isDesktop
                          ? null
                          : MediaQuery.of(context).padding.top + 16.0;
                      final double? bottomOffset = isDesktop ? 32.0 : null;
                      final double? rightOffset = isDesktop ? null : 16.0;
                      final double? leftOffset =
                          isDesktop ? (isSidebarOpen ? 260.0 : 20.0) : null;

                      return AnimatedPositioned(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        top: topOffset,
                        bottom: bottomOffset,
                        left: leftOffset,
                        right: rightOffset,
                        child: IgnorePointer(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _showScaleBarNotifier,
                            builder: (context, showScale, _) {
                              return ValueListenableBuilder<String>(
                                valueListenable: _scaleTextNotifier,
                                builder: (context, scaleText, _) {
                                  return ValueListenableBuilder<double>(
                                    valueListenable: _scaleWidthNotifier,
                                    builder: (context, scaleWidth, _) {
                                      return AnimatedOpacity(
                                        opacity: showScale ? 1.0 : 0.0,
                                        duration:
                                            const Duration(milliseconds: 250),
                                        child: PremiumScaleBar(
                                          width: scaleWidth,
                                          text: scaleText,
                                          isDark: isDark,
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      );
                    }),

                // 🚀 3. TURN-BY-TURN BANNER
                Positioned(
                  top: topMargin,
                  left: sideMargin,
                  right: sideMargin,
                  child: Builder(
                    builder: (context) {
                      final banner = TurnByTurnBanner(isDark: isDark);
                      return banner;
                    },
                  ),
                ),

                Positioned(
                  bottom: isDesktop
                      ? 32.0
                      : (MediaQuery.paddingOf(context).bottom + 124),
                  left: sideMargin,
                  child: Selector<MapProvider, bool>(
                    selector: (context, provider) =>
                        provider.isActiveNavigation,
                    builder: (context, isActiveNavigation, child) {
                      if (!isActiveNavigation) return const SizedBox.shrink();

                      final camera =
                          Provider.of<MapProvider>(context, listen: false)
                              .engine
                              .camera;
                      // 🚀 CRITICAL FIX: Do not permanently unmount if camera is momentarily null
                      if (camera == null) return const SizedBox.shrink();

                      return ValueListenableBuilder<bool>(
                        valueListenable: camera.isUserPanning,
                        builder: (context, isPanning, _) {
                          final isVisible = isPanning && isActiveNavigation;
                          return IgnorePointer(
                            ignoring: !isVisible,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: isVisible ? 1.0 : 0.0,
                              child: child,
                            ),
                          );
                        },
                      );
                    },
                    child: Builder(builder: (context) {
                      final content = RidelBounceButton(
                        onTap: () {
                          AppHaptics.selectionClick();
                          Provider.of<MapProvider>(context, listen: false)
                              .engine
                              .camera
                              ?.resetCompass();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(36),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(36),
                            child: RepaintBoundary(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                    sigmaX: kIsWeb ? 4.0 : 35.0,
                                    sigmaY: kIsWeb ? 4.0 : 35.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0B0E17)
                                        .withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(36),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.08),
                                      width: 1,
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.navigation_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        "Re-centre",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                      return content;
                    }),
                  ),
                ),

                ValueListenableBuilder<double>(
                  valueListenable: widget.searchSheetProgressNotifier,
                  builder: (context, progress, pillChild) {
                    if (isDesktop) {
                      return Positioned(
                        bottom: 32.0,
                        right: sideMargin,
                        child: pillChild!,
                      );
                    }
                    final double screenHeight =
                        MediaQuery.sizeOf(context).height;
                    const double buttonGap = 16.0;

                    // This formula guarantees the buttons ALWAYS stay exactly 'buttonGap'
                    // distance above the top edge of the sheet.
                    final double dynamicBottomPosition =
                        (screenHeight * progress) + buttonGap;

                    final opacity = (progress <= 0.45)
                        ? 1.0
                        : (1.0 - ((progress - 0.45) / (0.90 - 0.45)))
                            .clamp(0.0, 1.0);

                    return Positioned(
                      bottom: dynamicBottomPosition,
                      right: 16.0,
                      child: Opacity(
                        opacity: opacity,
                        child: pillChild!,
                      ),
                    );
                  },
                  child: Builder(
                    builder: (context) {
                      final content = Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (_) {},
                        onPointerMove: (_) {},
                        onPointerUp: (_) {},
                        onPointerSignal: (_) {},
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          onDoubleTap: () {},
                          onScaleStart: (_) {},
                          onScaleUpdate: (_) {},
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 🚀 THE RELOCATED COMPASS
                              Selector<MapProvider, MapLibreMapController?>(
                                selector: (context, provider) =>
                                    provider.controller,
                                builder: (context, controller, _) {
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12.0),
                                    child: AppleStyleCompass(
                                        controller: controller),
                                  );
                                },
                              ),
                              // 🍏 THE APPLE "PILL" (Map Settings + Locate Me)
                              Selector<MapProvider, bool>(
                                selector: (context, provider) =>
                                    !provider.isActiveNavigation ||
                                    !provider.isAutoTracking,
                                builder: (context, isVisible, child) {
                                  return IgnorePointer(
                                    ignoring: !isVisible,
                                    child: AnimatedOpacity(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      opacity: isVisible ? 1.0 : 0.0,
                                      child: child,
                                    ),
                                  );
                                },
                                child: Builder(builder: (context) {
                                  return MapControlsPill(
                                    onThemeTap: () {
                                      AppHaptics.heavyImpact();
                                      MapThemeSelector.show(context,
                                          currentTheme: _currentTheme ??
                                              (isDark
                                                  ? MapThemeType.dark
                                                  : MapThemeType.light),
                                          mapProvider: Provider.of<MapProvider>(
                                              context,
                                              listen: false),
                                          onThemeSelected: (selectedTheme) {
                                        _currentTheme = selectedTheme;
                                        Provider.of<MapProvider>(context,
                                                listen: false)
                                            .setTheme(selectedTheme);
                                      });
                                    },
                                    onLocateTap: () {
                                      AppHaptics.selectionClick();
                                      Future.microtask(() async {
                                        if (!context.mounted) return;
                                        final mapProvider =
                                            Provider.of<MapProvider>(context,
                                                listen: false);

                                        if (mapProvider.isActiveNavigation &&
                                            !mapProvider.isAutoTracking) {
                                          await mapProvider
                                              .recenter3DNavigation();
                                        } else if (mapProvider
                                                .isRouteCalculated &&
                                            !mapProvider.isActiveNavigation) {
                                          await mapProvider.start3DNavigation();
                                        } else if (mapProvider
                                                .targetDestination !=
                                            null) {
                                          final locService = Provider.of<
                                                  GlobalLocationService>(
                                              context,
                                              listen: false);
                                          if (locService.currentPosition ==
                                              null) {
                                            await locService
                                                .forceRefreshLocation();
                                          }
                                          if (!context.mounted) return;
                                          await mapProvider
                                              .calculateAndDrawNativeRoute(
                                                  context, 'driving');
                                        } else {
                                          await _handleLocateMeTapped(
                                              mapProvider);
                                        }
                                      });
                                    },
                                  );
                                }),
                              ),
                              if (isDesktop) ...[
                                const SizedBox(height: 16),
                                const DesktopZoomPill(),
                              ],
                            ],
                          ),
                        ),
                      );
                      return content;
                    },
                  ),
                ),
              ],
            ),
    );
  }

  // 🚀 HELPER: Evaluates true physical GPS using accuracy precision (< 100 meters) and regional bounds
  bool _isVerifiedPhysicalGps(Position? pos, bool hasPermission) {
    if (pos == null || !hasPermission || pos.isMocked) return false;

    // 1. Accuracy Check: IP/Cell-tower fallback accuracy is typically > 500m. True GPS is < 50m.
    // If accuracy is worse than 150 meters, DO NOT treat as street-level GPS!
    if (pos.accuracy > 150.0 || pos.accuracy == 0.0) {
      debugPrint(
          "🛑 [Accuracy Shield] Rejected location due to low precision (${pos.accuracy}m). Holding altitude.");
      return false;
    }

    // 2. Default City Bounding Box Shield (Delhi NCR & Nagpur fallback zones)
    final lat = pos.latitude;
    final lng = pos.longitude;
    final isDelhiFallback = (lat >= 28.40 && lat <= 28.88) &&
        (lng >= 76.85 && lng <= 77.40) &&
        (pos.accuracy > 100.0);
    final isNagpurFallback = (lat >= 21.00 && lat <= 21.30) &&
        (lng >= 78.90 && lng <= 79.20) &&
        (pos.accuracy > 100.0);
    final isZero = lat == 0.0 && lng == 0.0;

    return !isDelhiFallback && !isNagpurFallback && !isZero;
  }

  // 🚀 THE ABSOLUTE GATEKEEPER: Rewrites illegal street zooms!
  Future<void> _safeAnimateCamera(LatLng target, double requestedZoom,
      {Duration duration = const Duration(milliseconds: 1000)}) async {
    final mapController =
        Provider.of<MapProvider>(context, listen: false).controller ??
            _tempController;
    if (!mounted || mapController == null) return;

    final locService =
        Provider.of<GlobalLocationService>(context, listen: false);
    final pos = locService.currentPosition;

    // Must be verified physical GPS (< 150m accuracy, not mocked, permission granted)
    final bool isPhysicalGps = pos != null &&
        !pos.isMocked &&
        locService.hasLocationPermission &&
        pos.accuracy <= 150.0;

    double clampedZoom = requestedZoom;

    // 🚀 THE GOLDEN RULE: If we do NOT have physical GPS, clamp strictly to 10.5!
    // The map must calmly hold at the 5km overview until the Blue Dot officially mounts.
    if (!isPhysicalGps && requestedZoom > 11.0) {
      debugPrint(
          "🛑 [Golden Rule] Prevented dive to $requestedZoom. Blue Dot not mounted. Holding at 10.5!");
      clampedZoom = 10.5;
    }

    await mapController.animateCamera(
      CameraUpdate.newLatLngZoom(target, clampedZoom),
      duration: duration,
    );
  }

  Future<void> _igniteBlueDotAndSnipe(Position realPos) async {
    final mapController =
        Provider.of<MapProvider>(context, listen: false).controller ??
            _tempController;
    if (!mounted || mapController == null) return;

    // 1. Enable native location layer ONLY when we have a real, non-mocked coordinate and no route is active
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    if (!mapProvider.isRouteCalculated && !mapProvider.isActiveNavigation) {
      try {
        await mapController
            .updateMyLocationTrackingMode(MyLocationTrackingMode.tracking);
      } catch (_) {}
    }

    // 2. Wait 200ms for MapLibre to mount the Blue Dot on the WebGL canvas
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    // 3. Execute cinematic glide down to street level (200m scale)
    await _safeAnimateCamera(
      LatLng(realPos.latitude, realPos.longitude),
      15.5, // 🚀 STREET LEVEL SNIPE
      duration: const Duration(milliseconds: 1400),
    );
  }

  Future<void> _handleLocateMeTapped(MapProvider provider) async {
    final locService =
        Provider.of<GlobalLocationService>(context, listen: false);
    final permission = await Geolocator.checkPermission();
    final bool isServiceOn = await Geolocator.isLocationServiceEnabled();

    // 🚫 CASE 1: Permission Denied or GPS Off -> INTERCEPT & SHOW TOAST
    if (!mounted) return;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        !isServiceOn) {
      // Trigger interactive toast immediately. DO NOT move the map!
      ToastService.showActionToast(
        context,
        message: "Location permission needed to show your exact position.",
        actionLabel: "ENABLE",
        onActionTap: () async {
          if (kIsWeb) {
            await Geolocator.requestPermission();
          } else {
            if (permission == LocationPermission.deniedForever) {
              await Geolocator.openAppSettings();
            } else if (!isServiceOn) {
              await Geolocator.openLocationSettings();
            } else {
              await Geolocator.requestPermission();
            }
          }
          if (mounted) {
            Provider.of<GlobalLocationService>(context, listen: false)
                .initializeEcoLocation(isManualTrigger: true);
          }
        },
      );
      return;
    }

    // ✅ CASE 2: Permission Granted -> FETCH GPS & SNIPE
    final pos = locService.currentPosition;
    if (pos != null && !pos.isMocked && pos.accuracy <= 150.0) {
      // 🚀 UNLOCK SHIELD ON MANUAL USER ACTION
      await _igniteBlueDotAndSnipe(pos);
    } else {
      await locService.initializeEcoLocation(isManualTrigger: true);
    }
  }
}

// 🚀 NAYA SMART COMPASS WIDGET (APPLE STYLE) - OPTIMIZED WITH REPAINT BOUNDARY
class AppleStyleCompass extends StatefulWidget {
  final MapLibreMapController? controller;
  const AppleStyleCompass({super.key, required this.controller});

  @override
  State<AppleStyleCompass> createState() => _AppleStyleCompassState();
}

class _AppleStyleCompassState extends State<AppleStyleCompass> {
  final ValueNotifier<double> _bearingNotifier = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onCameraMove);
  }

  @override
  void didUpdateWidget(AppleStyleCompass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onCameraMove);
      widget.controller?.addListener(_onCameraMove);
    }
  }

  void _onCameraMove() {
    final newBearing = widget.controller?.cameraPosition?.bearing ?? 0.0;
    if ((_bearingNotifier.value - newBearing).abs() > 0.5) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bearingNotifier.value = newBearing;
      });
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onCameraMove);
    _bearingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget compassBody = ValueListenableBuilder<double>(
      valueListenable: _bearingNotifier,
      builder: (context, bearing, child) {
        final bool isVisible = bearing.abs() > 2.0;

        return AnimatedOpacity(
          opacity: isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !isVisible,
            // 🚀 PERFORMANCE FIX: GPU will only repaint the compass layer during map rotation, saving massive resources!
            child: RepaintBoundary(
              child: GestureDetector(
                onTap: () {
                  AppHaptics.mediumImpact();
                  widget.controller?.animateCamera(CameraUpdate.bearingTo(0.0));
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: RepaintBoundary(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                          sigmaX: kIsWeb ? 4.0 : 35.0,
                          sigmaY: kIsWeb ? 4.0 : 35.0),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: !isDark
                              ? Colors.white.withValues(alpha: 0.85)
                              : const Color(0xFF0B0E17).withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                          border: !isDark
                              ? Border.all(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  width: 1.0)
                              : Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  width: 1.0),
                          boxShadow: !isDark
                              ? [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4))
                                ]
                              : [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.4),
                                      blurRadius: 24,
                                      offset: const Offset(0, 12)),
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4)),
                                ],
                        ),
                        child: Transform.rotate(
                          angle: -bearing * (pi / 180.0),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // The authentic dial with ticks and red triangle
                              CustomPaint(
                                size: const Size(48, 48),
                                painter:
                                    AppleCompassDialPainter(isDark: isDark),
                              ),
                              // The center "N"
                              Text(
                                "N",
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    return compassBody;
  }
}

class DesktopDraggableSearchWrapper extends StatefulWidget {
  final Widget child;
  const DesktopDraggableSearchWrapper({super.key, required this.child});
  @override
  State<DesktopDraggableSearchWrapper> createState() =>
      _DesktopDraggableSearchWrapperState();
}

class _DesktopDraggableSearchWrapperState
    extends State<DesktopDraggableSearchWrapper> {
  double? _userLeftOffset;
  bool _isMoveMode = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final containerWidth = constraints.maxWidth;
      final double dynamicSheetWidth =
          (containerWidth * 0.40).clamp(450.0, 700.0);
      final bool canMove = containerWidth > (dynamicSheetWidth + 50);
      final double exactCenter = (containerWidth - dynamicSheetWidth) / 2;
      final double currentLeft = _userLeftOffset ?? exactCenter;

      Widget dragOverlay = Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: () {
                AppHaptics.heavyImpact();
                setState(() => _isMoveMode = false);
              },
              child: BackdropFilter(
                filter: ImageFilter.blur(
                    sigmaX: kIsWeb ? 4.0 : 10.0, sigmaY: kIsWeb ? 4.0 : 10.0),
                child: Container(color: Colors.black.withValues(alpha: 0.65)),
              ),
            ),
          ),
          Positioned(
            top: constraints.maxHeight * 0.15,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Adjust Sheet Position",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5)),
                const SizedBox(height: 12),
                const Text(
                    "Slide left or right to move • Double-tap anywhere to lock",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        AppHaptics.selectionClick();
                        setState(() => _isMoveMode = false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.3))),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 14),
                      ),
                      child: const Text("Done",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    if (_userLeftOffset != null) ...[
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          AppHaptics.selectionClick();
                          setState(() {
                            _userLeftOffset = null;
                            _isMoveMode = false;
                          });
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text("Reset Position",
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(100),
                              side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.3))),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                        ),
                      ),
                    ]
                  ],
                )
              ],
            ),
          ),
        ],
      );

      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: _isMoveMode ? dragOverlay : const SizedBox.shrink(),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: currentLeft,
            width: dynamicSheetWidth,
            child: AnimatedScale(
              scale: _isMoveMode ? 1.04 : 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: canMove
                    ? () {
                        AppHaptics.heavyImpact();
                        setState(() => _isMoveMode = !_isMoveMode);
                      }
                    : null,
                onPanUpdate: _isMoveMode
                    ? (details) {
                        setState(() {
                          _userLeftOffset = (currentLeft + details.delta.dx)
                              .clamp(20.0,
                                  containerWidth - dynamicSheetWidth - 20.0);
                        });
                      }
                    : null,
                child: IgnorePointer(
                  ignoring: _isMoveMode,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class PremiumMapSkeleton extends StatefulWidget {
  const PremiumMapSkeleton({super.key});

  @override
  State<PremiumMapSkeleton> createState() => _PremiumMapSkeletonState();
}

class _PremiumMapSkeletonState extends State<PremiumMapSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 3500), // Matched to Web's 3.5s
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161E28),
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RepaintBoundary(
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) {
                      return LinearGradient(
                        // Sweeps tightly from left to right
                        begin: Alignment(-2.0 + (_controller.value * 4), -0.5),
                        end: Alignment(-1.0 + (_controller.value * 4), 0.5),
                        colors: [
                          Colors.white
                              .withValues(alpha: 0.4), // Base dimmed state
                          Colors.white
                              .withValues(alpha: 0.8), // Shimmer highlight
                          Colors.white.withValues(alpha: 0.4), // Back to base
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ).createShader(bounds);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Solid colors so the ShaderMask srcIn correctly reveals them
                        const Icon(Icons.directions_bike,
                            color: Colors.white, size: 38),
                        const SizedBox(width: 8),

                        const Text(
                          'Maps',
                          style: TextStyle(
                            color: Colors.white, // Masking layer
                            fontSize: 32,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.5,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(width: 12),

                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                                alpha: 0.2), // Dimmer background mask
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'BETA',
                            style: TextStyle(
                              color: Colors.white, // Masking layer
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30.0),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
                    // 1.4s cycle within a 3.5s controller
                    final timeSeconds = _controller.value * 3.5;
                    final delay = index * 0.2;
                    final cycleTime = (timeSeconds - delay) % 1.4;

                    double offset = 0.0;
                    double opacity = 0.4;

                    if (cycleTime > 0 && cycleTime < 0.7) {
                      final t = cycleTime / 0.7;
                      final val = sin(t * pi);
                      offset = val * -8.0;
                      opacity = 0.4 + (val * 0.6);
                    }

                    return Transform.translate(
                      offset: Offset(0, offset),
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4.0),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AppleCompassDialPainter extends CustomPainter {
  final bool isDark;
  AppleCompassDialPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4.0; // Inner padding

    final tickPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.3)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final boldTickPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Draw subtle tick marks every 10 degrees
    for (int i = 0; i < 36; i++) {
      final angle = i * 10 * pi / 180;
      final isBold = i % 9 == 0; // Bold at every 90 degrees (N, E, S, W)
      final tickLength = isBold ? 4.0 : 2.5;

      final start = Offset(
        center.dx + (radius - tickLength) * sin(angle),
        center.dy - (radius - tickLength) * cos(angle),
      );
      final end = Offset(
        center.dx + radius * sin(angle),
        center.dy - radius * cos(angle),
      );

      // Skip the 0-degree tick to make room for the red North triangle
      if (i != 0) {
        canvas.drawLine(start, end, isBold ? boldTickPaint : tickPaint);
      }
    }

    // Draw the crisp Red North Triangle at the top edge
    final path = Path();
    path.moveTo(center.dx, 3.0); // Sharp Top tip
    path.lineTo(center.dx - 3.5, 9.0); // Bottom left
    path.lineTo(center.dx + 3.5, 9.0); // Bottom right
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFF3B30) // Apple Red
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// 📏 PREMIUM SCALE BAR (Glassmorphism Parity)
// ═══════════════════════════════════════════════════════════════════════════
class PremiumScaleBar extends StatelessWidget {
  final double width;
  final String text;
  final bool isDark;

  const PremiumScaleBar({
    super.key,
    required this.width,
    required this.text,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              text,
              key: ValueKey<String>(text),
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                shadows: [
                  Shadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.8),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            height: 2.5,
            width: width,
            decoration: BoxDecoration(
              color: isDark ? Colors.white : Colors.black87,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.6),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
