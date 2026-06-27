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

import 'package:ridel/features/profile/services/profile_repository.dart';
import 'package:permission_handler/permission_handler.dart';
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

  final ValueNotifier<bool> _showScaleBarNotifier = ValueNotifier(false);
  Timer? _scaleBarTimer;

  final ValueNotifier<String> _scaleTextNotifier = ValueNotifier('0 m');
  final ValueNotifier<double> _scaleWidthNotifier = ValueNotifier(60.0);

  bool _showPOIs = true;

  Symbol? _heroSymbol;

  // 🚀 ADAPTIVE LOD CONTROLLER
  bool _isPerformanceMode = false;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
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
      final style = await MapStyleHelper.getOlaStyle(isSystemDark, themeType: _currentTheme);

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

  void _showHeroBottomSheet(String name, LatLng coordinates) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctrl = Provider.of<MapProvider>(context, listen: false).controller ??
        _tempController;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      isScrollControlled: true,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.6),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24.0)),
              border: Border(
                  top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2), width: 1.0)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white30 : Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Coordinates: ${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)}",
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? Colors.white : Colors.black,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Search / Go',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (ctrl != null && _heroSymbol != null) {
        ctrl.removeSymbol(_heroSymbol!);
        _heroSymbol = null;
      }
    });
  }

  Future<void> _safeMoveCamera(LatLng target,
      {double? zoom, double? bearing, double? tilt, Duration? duration}) async {
    final mapController =
        Provider.of<MapProvider>(context, listen: false).controller ??
            _tempController;
    // ignore: unnecessary_null_comparison
    if (target.latitude == null || target.longitude == null) {
      debugPrint("🛑 NULL DETECTED: animateCamera received a null target!");
      return;
    }

    debugPrint(
        "🛠️ DEBUG ANIMATE CAMERA: Lat:${target.latitude}, Lng:${target.longitude}, Zoom:${zoom ?? 14.0}");

    if (mapController != null) {
      await mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: zoom ?? 14.0,
            tilt: tilt ?? 0.0,
            bearing: bearing ?? 0.0,
          ),
        ),
        duration: duration,
      );
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
                      final userCurrentLocation =
                          Provider.of<MapProvider>(context, listen: false)
                              .currentLocation;
                      final double safeLat =
                          userCurrentLocation?.latitude ?? 21.1458;
                      final double safeLng =
                          userCurrentLocation?.longitude ?? 79.0882;

                      debugPrint(
                          "🛠️ DEBUG INITIAL CAMERA: Lat:$safeLat, Lng:$safeLng");

                      return RepaintBoundary(
                        child: MapLibreMap(
                          key: const ValueKey('ridel_main_map'),
                          styleString: _loadedMapStyle!,
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

                            // 🚀 CRITICAL FIX 1: Engine ko controller pass karna zaroori hai!
                            final mapProvider = Provider.of<MapProvider>(
                                context,
                                listen: false);
                            mapProvider.engine.mapController = controller;

                            // 🚀 One-time location fetch on map start
                            Geolocator.getCurrentPosition(
                                    locationSettings: const LocationSettings(
                                        accuracy: LocationAccuracy.high))
                                .then((pos) {
                              final latLng =
                                  LatLng(pos.latitude, pos.longitude);
                              controller.animateCamera(
                                  CameraUpdate.newLatLngZoom(latLng, 16.0));
                            }).catchError((e) {
                              debugPrint("Initial location error: $e");
                            });
                          },
                          onStyleLoadedCallback: () async {
                            final controller = _tempController;
                            if (controller == null) return;

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
                            } catch (_) {}

                            if (!context.mounted) return;
                            final mapProvider = Provider.of<MapProvider>(
                                context,
                                listen: false);
                            mapProvider.engine.onMapCreated(
                                controller,
                                isDark,
                                Provider.of<GlobalLocationService>(context,
                                    listen: false),
                                this);

                            // Intentionally removed _isMapFullyLoaded setState
                          },
                          onMapClick: (point, latLng) async {
                            FocusScope.of(context).unfocus();
                            final mapProvider = Provider.of<MapProvider>(
                                context,
                                listen: false);

                            if (mapProvider.mapSelectionPlaceType != null) {
                              mapProvider.setTargetDestination(latLng);
                              mapProvider.addNativeDestinationPin(latLng);
                              // If you have _showConfirmationDialog in this file, keep it, otherwise ignore
                              return;
                            }

                            if (mapProvider.isFlying) {
                              mapProvider.stopCameraFlight();
                              return;
                            }

                            bool handled = await mapProvider.handleRouteClick(
                                point, latLng);
                            if (!handled) {
                              mapProvider.clearTargetLocation();
                            }
                          },
                          onMapLongClick:
                              (Point<double> point, LatLng coordinates) async {
                            final mapProvider = Provider.of<MapProvider>(
                                context,
                                listen: false);

                            // 🚀 Free the camera from blue dot
                            mapProvider.setAutoTracking(false);
                            mapProvider.setUserPanning(true);
                            mapProvider.handleMapLongPress(coordinates);

                            // 🚀 HERO POI INTERACTION
                            final controller =
                                mapProvider.controller ?? _tempController;
                            if (controller != null && _showPOIs) {
                              try {
                                final features = await controller
                                    .queryRenderedFeatures(point, [], null);
                                Map? poi;
                                for (var f in features) {
                                  if (f is Map && f['properties'] != null) {
                                    debugPrint(
                                        'DEBUG TAPPED FEATURE PROPERTIES: ${f['properties']}');
                                    if (f['properties']['name'] != null &&
                                        f['geometry'] != null) {
                                      poi ??=
                                          f; // Store the first named feature but keep looping to print all
                                    }
                                  }
                                }

                                if (poi != null) {
                                  final name =
                                      poi['properties']['name'].toString();

                                  AppHaptics.selectionClick();

                                  // Remove old hero symbol if exists
                                  if (_heroSymbol != null) {
                                    await controller.removeSymbol(_heroSymbol!);
                                  }

                                  // Add enlarged Hero pin
                                  _heroSymbol = await controller.addSymbol(
                                    SymbolOptions(
                                      geometry: coordinates,
                                      iconImage: 'custom_pin',
                                      iconSize: 1.5,
                                      iconAnchor: 'bottom',
                                    ),
                                  );

                                  // Smoothly offset camera so sheet doesn't cover marker and zoom in
                                  _safeMoveCamera(
                                    LatLng(coordinates.latitude - 0.0025,
                                        coordinates.longitude),
                                    zoom: 16.5,
                                  );

                                  if (!mounted) return;
                                  _showHeroBottomSheet(name, coordinates);
                                }
                              } catch (e) {
                                debugPrint("POI Query error: $e");
                              }
                            }
                          },
                          initialCameraPosition: CameraPosition(
                              target: LatLng(safeLat, safeLng),
                              zoom: userCurrentLocation == null ? 4.5 : 14.0,
                              tilt: 0.0,
                              bearing: 0.0),

                          compassEnabled: false,
                          doubleClickZoomEnabled: true,
                          scrollGesturesEnabled: true,
                          zoomGesturesEnabled: true,
                          tiltGesturesEnabled: true,

                          // 🚀 Dynamic Location Tracking Reverted
                          myLocationEnabled: Provider.of<MapProvider>(context, listen: false).showNativeBlueDot,
                          myLocationTrackingMode:
                              Provider.of<MapProvider>(context, listen: false)
                                      .isAutoTracking
                                  ? (kIsWeb
                                      ? MyLocationTrackingMode.tracking
                                      : MyLocationTrackingMode.trackingCompass)
                                  : MyLocationTrackingMode.none,
                          trackCameraPosition: true,
                          myLocationRenderMode: MyLocationRenderMode.normal,

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
                            // 🚀 STRICT GUARD: Prevent async context crashes (Fixes line 648)
                            if (!mounted) return;

                            // Push the state update outside the current render cycle
                            Future.microtask(() {
                              if (context.mounted) {
                                Provider.of<MapProvider>(context, listen: false)
                                    .updateCurrentLocation(location.position);
                              }
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
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  widget.searchSheetProgressNotifier.value =
                                      progress;
                                }
                              });
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
                    final screenSize = MediaQuery.sizeOf(context);

                    // 1. Calculate the exact top pixel coordinate of the sheet
                    final double availableHeight = screenSize.height -
                        MediaQuery.paddingOf(context).bottom;
                    final double sheetPhysicalHeight =
                        progress * availableHeight;

                    final double dynamicBottomMargin =
                        lerpDouble(44.0, 0.0, progress) ?? 44.0;

                    // -16.0px gap above the sheet to sit extremely close to the top of the Search Sheet.
                    final double dynamicBottomPosition = sheetPhysicalHeight +
                        dynamicBottomMargin +
                        MediaQuery.paddingOf(context).bottom -
                        16.0;

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
                                          showPOIs: _showPOIs,
                                          onPOIsToggled: (val) {
                                        setState(() {
                                          _showPOIs = val;
                                          _initMapStyle(updateExisting: true);
                                        });
                                      }, onThemeSelected: (selectedTheme) {
                                        setState(() {
                                          _currentTheme = selectedTheme;
                                          _initMapStyle();
                                        });
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

  Future<void> _handleLocateMeTapped(MapProvider mapProvider) async {
    debugPrint("🎯 [DEBUG] Locate Me button clicked!");

    bool isGranted = await Permission.location.isGranted;
    if (ProfileRepository.userCity.value == 'Location Disabled' || !isGranted) {
      if (mounted) {
        ToastService.showError(context, "Location permission is required.");
      }
      return;
    }

    try {
      // 🚨 CRITICAL: Append .timeout to prevent infinite browser deadlock
      LocationPermission permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 2));

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 2));
        if (permission == LocationPermission.denied) {
          throw Exception("Permission denied by user.");
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception("Permission permanently denied.");
      }

      // If granted, proceed:
      debugPrint("✅ [DEBUG] Permission granted. Fetching location...");
      if (!mounted) return;
      final position = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
      final userLatLng = LatLng(position.latitude, position.longitude);

      final mapController = mapProvider.controller ?? _tempController;

      if (mapController == null) return;

      // Fallback if _currentCameraPosition is null initially before the first move
      final currentCamera =
          _currentCameraPosition ?? mapController.cameraPosition;
      if (currentCamera == null) return;

      // Update the custom dot (Location provider state)
      Future.microtask(() {
        if (context.mounted) {
          mapProvider.updateCurrentLocation(userLatLng);
        }
      });

      await mapController
          .updateMyLocationTrackingMode(MyLocationTrackingMode.none);

      // 2. Calculate Distance from Camera Center to User
      final double distance = Geolocator.distanceBetween(
        currentCamera.target.latitude,
        currentCamera.target.longitude,
        userLatLng.latitude,
        userLatLng.longitude,
      );

      // 3. The Smart State Machine
      if (distance > 15.0) {
        // STATE 1: Far away -> Smooth "Fly To" animation
        await _safeMoveCamera(
          userLatLng,
          zoom: 16.5,
          tilt: 0.0,
          bearing: 0.0,
          duration: const Duration(
              milliseconds: 1800), // 🚀 1.8s smooth glide across the map
        );
        mapProvider.setAutoTracking(true);
      } else {
        // Already centered -> Toggle Tilt
        final currentTilt = currentCamera.tilt;

        if (currentTilt < 20.0) {
          // STATE 2: Flat -> Enter 3D Drive Mode (Cinematic Tilt)
          await _safeMoveCamera(
            userLatLng,
            zoom: 17.5, // Zoom in slightly for 3D
            tilt: 50.0, // Aggressive premium tilt
            bearing: currentCamera.bearing,
            duration:
                const Duration(milliseconds: 1200), // 🚀 1.2s elegant tilt up
          );
          mapProvider.setAutoTracking(true);
        } else {
          // STATE 3: Tilted -> Reset to Flat 2D
          await _safeMoveCamera(
            userLatLng,
            zoom: 16.5,
            tilt: 0.0,
            bearing: 0.0, // Reset North
            duration: const Duration(
                milliseconds: 900), // 🚀 0.9s snappy but smooth reset
          );
          mapProvider.setAutoTracking(true);
        }
      }
      if (mounted) setState(() {});
    } on TimeoutException catch (_) {
      // Catches the infinite hang caused by strict browser shields
      debugPrint(
          "⏳ [DEBUG] Geolocator timed out (Browser silently blocked it).");
      if (!mounted) return;
      final validContext = ToastService.navigatorKey.currentContext ?? context;
      if (validContext.mounted) {
        ToastService.showError(
          validContext,
          "Check site settings (🔒).",
          title: "Location Blocked",
          onTap: () {
            debugPrint("👆 [DEBUG] Error Toast Tapped!");
            if (kIsWeb) {
              // 🚨 Capture context immediately before the async gap
              final safeContext =
                  ToastService.navigatorKey.currentContext ?? context;

              Future.delayed(const Duration(milliseconds: 400), () {
                debugPrint(
                    "🟢 [DEBUG] 400ms delay finished, firing Warning Toast...");
                if (!safeContext.mounted) return;
                try {
                  // 🚨 Changed to showWarning to bypass the isMapScreen invisibility filter
                  ToastService.showWarning(safeContext,
                      "Click the lock icon (🔒) in your browser URL bar to allow location.",
                      title: "Browser Settings");
                } catch (e) {
                  debugPrint("🔴 [DEBUG] Failed to launch Warning Toast: $e");
                }
              });
            } else {
              Geolocator.openAppSettings().catchError((e) {
                debugPrint("⚠️ [DEBUG] Failed to open settings: $e");
                return false;
              });
            }
          },
        );
      }
    } catch (e) {
      // Catches standard denied exceptions
      debugPrint("📍 [DEBUG] Locate Me Error: $e");
      if (!mounted) return;
      final validContext = ToastService.navigatorKey.currentContext ?? context;
      if (validContext.mounted) {
        ToastService.showError(
          validContext,
          "Tap to grant access.",
          title: "Location Denied",
          onTap: () {
            debugPrint("👆 [DEBUG] Error Toast Tapped!");
            if (kIsWeb) {
              // 🚨 Capture context immediately before the async gap
              final safeContext =
                  ToastService.navigatorKey.currentContext ?? context;

              Future.delayed(const Duration(milliseconds: 400), () {
                debugPrint(
                    "🟢 [DEBUG] 400ms delay finished, firing Warning Toast...");
                if (!safeContext.mounted) return;
                try {
                  // 🚨 Changed to showWarning to bypass the isMapScreen invisibility filter
                  ToastService.showWarning(safeContext,
                      "Click the lock icon (🔒) in your browser URL bar to allow location.",
                      title: "Browser Settings");
                } catch (e) {
                  debugPrint("🔴 [DEBUG] Failed to launch Warning Toast: $e");
                }
              });
            } else {
              Geolocator.openAppSettings().catchError((e) {
                debugPrint("⚠️ [DEBUG] Failed to open settings: $e");
                return false;
              });
            }
          },
        );
      }
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
