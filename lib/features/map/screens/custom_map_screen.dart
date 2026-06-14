import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/map/map_style_helper.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/saved_places_service.dart';

import '../map_engine/map_engine.dart';
import '../map_engine/controllers/map_mode_controller.dart';
import 'package:ridel/core/providers/app_navigation_provider.dart';
import 'package:ridel/features/map/models/place_model.dart';
import 'package:ridel/features/map/services/place_api_services.dart';
import 'package:ridel/core/widgets/ridel_glass.dart';

class CustomMapScreen extends StatefulWidget {
  final bool isDark;
  final bool isMapTabActive;
  final ValueChanged<double>? onCardProgress;
  final ValueChanged<bool>? onThemeChanged;
  final ValueChanged<bool>? onWeatherVisibilityChanged;
  final ValueChanged<bool>? onMapInteraction;
  final double searchSheetProgress;

  const CustomMapScreen({
    super.key,
    required this.isDark,
    required this.isMapTabActive,
    this.onCardProgress,
    this.onThemeChanged,
    this.onWeatherVisibilityChanged,
    this.onMapInteraction,
    this.searchSheetProgress = 0.0,
  });

  @override
  State<CustomMapScreen> createState() => _CustomMapScreenState();
}

class _CustomMapScreenState extends State<CustomMapScreen>
    with TickerProviderStateMixin {
  late MapEngine _engine;
  GlobalLocationService? _locationService;

  late AnimationController _cardAnimController;
  late Animation<double> _fluidAnimation;
  late AnimationController _extrusionAnimController;
  late AnimationController _entryAnimController;

  final ValueNotifier<double> _zoomNotifier = ValueNotifier(14.5);
  final ValueNotifier<double> _tiltNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> _bearingNotifier = ValueNotifier(0.0);
  final ValueNotifier<bool> _zoomScaleVisible = ValueNotifier(false);
  final ValueNotifier<double> _sheetProgress = ValueNotifier<double>(0.0);

  // 🚀 OPTIMIZATION 1: Changed to ValueNotifier to stop continuous setState rebuilds during map pan
  final ValueNotifier<String> _interactionState = ValueNotifier("none");

  bool _isWeatherVisible = true;
  Timer? _interactionDebounceTimer;
  Timer? _zoomScaleDebounceTimer;

  bool _wasInIndia = true;
  bool _hasMapBeenOpened = false;

  /// Tracks whether the user has explicitly overridden the map theme
  /// via the theme selector. If false, _currentTheme follows the system.
  bool _userOverrodeTheme = false;
  late MapThemeType _currentTheme;

  @override
  void initState() {
    super.initState();
    _hasMapBeenOpened = widget.isMapTabActive;

    // 🚀 FIX: Derive initial map theme from the system brightness
    _currentTheme = widget.isDark ? MapThemeType.dark : MapThemeType.light;

    _engine = MapEngine();
    _engine.state.addListener(() {
      if (mounted) setState(() {});
    });

    _updateStyleFuture();

    _cardAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fluidAnimation = CurvedAnimation(
        parent: _cardAnimController, curve: Curves.easeOutCubic);
    _cardAnimController.addListener(() {
      if (widget.onCardProgress != null) {
        widget.onCardProgress!(_fluidAnimation.value);
      }
    });

    _extrusionAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _extrusionAnimController.addListener(() {
      _engine.updateExtrusionProgress(_extrusionAnimController.value);
    });

    _entryAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));

    if (widget.isMapTabActive) {
      _entryAnimController.forward();
    }

    Provider.of<MapProvider>(context, listen: false)
        .addListener(_onMapSearchTriggered);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _locationService =
          Provider.of<GlobalLocationService>(context, listen: false);
      _locationService?.addListener(_onLocationUpdated);
    });
  }

  String? _currentMapStyle;
  bool _isFetchingStyle = false;

  void _updateStyleFuture() async {
    if (!mounted) return;
    setState(() => _isFetchingStyle = true);

    String styleStr = await MapStyleHelper.getOlaStyle(
      _engine.isDarkTheme,
      themeType: _currentTheme,
    );

    // 🚀 PATCH: Inject missing glyphs required by MapLibre for text-field rendering
    try {
      final decoded = jsonDecode(styleStr) as Map<String, dynamic>;
      if (!decoded.containsKey('glyphs') ||
          decoded['glyphs'] == null ||
          decoded['glyphs'].toString().isEmpty) {
        decoded['glyphs'] =
            "https://api.olamaps.io/tiles/fonts/{fontstack}/{range}.pbf";
        styleStr = jsonEncode(decoded);
      }
    } catch (e) {
      debugPrint("Map style parsing error: $e");
    }

    if (!mounted) return;

    // We must use setState so MapLibreMap's didUpdateWidget handles the styleString update safely
    setState(() {
      _currentMapStyle = styleStr;
      _isFetchingStyle = false;
    });

    // 🚀 FIX: Keep MapProvider's route theme in sync
    Provider.of<MapProvider>(context, listen: false).setTheme(_currentTheme);
  }

  void _onMapSearchTriggered() {
    final provider = Provider.of<MapProvider>(context, listen: false);
    if (provider.targetLocation != null) {
      final target = provider.targetLocation!;
      _engine.executeSearchFlight(target, place: provider.tappedPlaceFromMap);

      provider.targetLocation = null;
      provider.isCinematicSearch = false;

      provider.setTargetDestination(target);
      provider.setDestinationSelected(true);
      provider.engine.setUIState(MapUIState.placeSelected);
    }
  }

  void _onLocationUpdated() {
    if (!mounted || _locationService?.currentPosition == null) {
      return;
    }
    final provider = Provider.of<MapProvider>(context, listen: false);
    if (provider.isNavigatingToStation) {
      provider.checkIfArrived(
        _locationService!.currentPosition!.latitude,
        _locationService!.currentPosition!.longitude,
        () {
          AppHaptics.heavyImpact();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Arrived at the destination!"),
              backgroundColor: Colors.green));
          Provider.of<AppNavigationProvider>(context, listen: false).setTab(1);
        },
      );
    }
  }

  @override
  void dispose() {
    _locationService?.removeListener(_onLocationUpdated);
    Provider.of<MapProvider>(context, listen: false)
        .removeListener(_onMapSearchTriggered);
    _interactionDebounceTimer?.cancel();
    _zoomScaleDebounceTimer?.cancel();
    _cardAnimController.dispose();
    _extrusionAnimController.dispose();
    _entryAnimController.dispose();
    _zoomNotifier.dispose();
    _tiltNotifier.dispose();
    _bearingNotifier.dispose();
    _zoomScaleVisible.dispose();
    _sheetProgress.dispose();
    _interactionState.dispose(); // 🚀 Disposed ValueNotifier
    _engine.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CustomMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.searchSheetProgress != oldWidget.searchSheetProgress) {
      _sheetProgress.value = widget.searchSheetProgress;
    }

    if (widget.isMapTabActive && !_hasMapBeenOpened) {
      setState(() => _hasMapBeenOpened = true);
    }

    if (widget.isMapTabActive && !oldWidget.isMapTabActive) {
      _entryAnimController.forward();
    } else if (!widget.isMapTabActive && oldWidget.isMapTabActive) {
      _entryAnimController.reverse();
    }

    if (oldWidget.isDark != widget.isDark) {
      _engine.isDarkTheme = widget.isDark;
      if (_engine.mode.is3DMode.value) {
        _engine.layers?.updateBuildingExtrusion(1.0, widget.isDark);
      }

      // 🚀 FIX: Sync map theme with global brightness change —
      // ONLY if the user hasn't manually overridden via the theme selector.
      if (!_userOverrodeTheme) {
        _currentTheme = widget.isDark ? MapThemeType.dark : MapThemeType.light;
      }
      _updateStyleFuture();
      setState(() {});
    }
  }

  void _onCameraMove() {
    if (_engine.mapController == null ||
        _engine.mapController!.cameraPosition == null) {
      return;
    }
    final cam = _engine.mapController!.cameraPosition!;

    bool currentlyInIndia = (cam.target.latitude >= 8.0 &&
        cam.target.latitude <= 37.0 &&
        cam.target.longitude >= 68.0 &&
        cam.target.longitude <= 97.0);
    if (_wasInIndia != currentlyInIndia) {
      _wasInIndia = currentlyInIndia;
      _updateStyleFuture();
      setState(() {});
    }

    bool isZoomChanged = (cam.zoom - _zoomNotifier.value).abs() > 0.001;
    // 🚀 Now reading from ValueNotifier
    if (isZoomChanged && _interactionState.value != "tilt") {
      _zoomScaleVisible.value = true;
      _zoomScaleDebounceTimer?.cancel();
      _zoomScaleDebounceTimer = Timer(const Duration(milliseconds: 800),
          () => _zoomScaleVisible.value = false);
    }
    if (!isZoomChanged && _interactionState.value != "tilt") {
      _setMapInteractionState("pan");
    }

    _zoomNotifier.value = cam.zoom;
    _tiltNotifier.value = cam.tilt;
    _bearingNotifier.value = cam.bearing;
    _checkWeatherVisibility(cam.zoom, cam.target);
  }

  void _checkWeatherVisibility(double zoom, LatLng target) {
    var r = 6371;
    var dLat = (target.latitude - 28.6139) * (math.pi / 180);
    var dLon = (target.longitude - 77.2090) * (math.pi / 180);
    var a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(28.6139 * (math.pi / 180)) *
            math.cos(target.latitude * (math.pi / 180)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    double distFromCenter =
        r * (2 * math.atan2(math.sqrt(a), math.sqrt(1 - a)));

    bool shouldShow = zoom >= 12.0 &&
        distFromCenter <= 6.0 &&
        _engine.mode.currentMode.value == MapMode.explore;
    if (_isWeatherVisible != shouldShow) {
      _isWeatherVisible = shouldShow;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.onWeatherVisibilityChanged != null) {
          widget.onWeatherVisibilityChanged!(_isWeatherVisible);
        }
      });
    }
  }

  void _setMapInteractionState(String newState) {
    // 🚀 Update ValueNotifier without setState to prevent full rebuilds
    if (_interactionState.value != newState) {
      _interactionState.value = newState;
      if (widget.onMapInteraction != null) {
        widget.onMapInteraction!(newState == "tilt");
      }
    }
    _interactionDebounceTimer?.cancel();
    if (newState == "pan") {
      _interactionDebounceTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted && _interactionState.value != "tilt") {
          _interactionState.value = "none";
          if (widget.onMapInteraction != null) {
            widget.onMapInteraction!(false);
          }
        }
      });
    }
  }

  void _toggleCard() {
    if (_cardAnimController.isCompleted) {
      _cardAnimController.reverse();
    } else {
      _cardAnimController.forward();
    }
  }

  void _showConfirmationDialog(
      BuildContext context, String type, LatLng coordinates) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Set as $type?",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                    },
                    child: const Text("Choose Another"),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      final mapProvider =
                          Provider.of<MapProvider>(context, listen: false);
                      // Save the place via SavedPlacesService
                      try {
                        final savedPlacesService =
                            Provider.of<SavedPlacesService>(context,
                                listen: false);
                        savedPlacesService.savePlace(
                            context,
                            type.toLowerCase(),
                            coordinates.latitude,
                            coordinates.longitude);
                      } catch (e) {
                        debugPrint("Failed to get SavedPlacesService");
                      }

                      mapProvider.setMapSelectionMode(null);
                      mapProvider.clearSearchSession(context);
                      Navigator.pop(ctx);
                    },
                    child: const Text(
                      "Yes, Set Location",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasMapBeenOpened) {
      return Container(color: widget.isDark ? Colors.black : Colors.white);
    }

    final isLightMode = Theme.of(context).brightness == Brightness.light;

    final bool isDesktop = MediaQuery.of(context).size.width >= 800;
    final bool showControls = isDesktop || widget.isMapTabActive;

    final double minSheetHeight = MediaQuery.of(context).padding.bottom + 106.0;
    final double maxSheetHeight = MediaQuery.of(context).size.height * 0.90;
    final double cappedProgress = widget.searchSheetProgress.clamp(0.0, 0.4);
    final double currentSheetHeight =
        minSheetHeight + (cappedProgress * (maxSheetHeight - minSheetHeight));
    final double dynamicBottomPosition = currentSheetHeight + 24.0;

    double buttonOpacity = 1.0;
    if (!isDesktop && widget.searchSheetProgress > 0.4) {
      buttonOpacity =
          (1.0 - ((widget.searchSheetProgress - 0.4) * 10)).clamp(0.0, 1.0);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          if (_currentMapStyle == null)
            PremiumMapSkeleton(isDark: widget.isDark)
          else
            MapLibreMap(
              styleString: _currentMapStyle!,
              initialCameraPosition: const CameraPosition(
                  target: LatLng(28.6139, 77.2090),
                  zoom: 14.5,
                  tilt: 0.0,
                  bearing: 0),
              minMaxZoomPreference: const MinMaxZoomPreference(4.5, 20.0),
              compassEnabled: false,
              logoViewMargins: const math.Point(-5000, -5000),
              attributionButtonMargins: const math.Point(-5000, -5000),
              doubleClickZoomEnabled: true,
              scrollGesturesEnabled: true,
              zoomGesturesEnabled: true,
              tiltGesturesEnabled: true,
              myLocationEnabled: true,
              myLocationTrackingMode: kIsWeb
                  ? MyLocationTrackingMode.tracking
                  : MyLocationTrackingMode.trackingCompass,
              myLocationRenderMode: kIsWeb
                  ? MyLocationRenderMode.normal
                  : MyLocationRenderMode.compass,
              trackCameraPosition: true,
              onCameraTrackingDismissed: () {
                final provider =
                    Provider.of<MapProvider>(context, listen: false);
                if (provider.isActiveNavigation) {
                  provider.setAutoTracking(false);
                }
                _engine.onUserPannedMap();
              },
              onMapClick: (point, latlng) async {
                final mapProvider =
                    Provider.of<MapProvider>(context, listen: false);

                if (mapProvider.mapSelectionPlaceType != null) {
                  mapProvider.setTargetDestination(latlng);
                  _showConfirmationDialog(
                      context, mapProvider.mapSelectionPlaceType!, latlng);
                  return;
                }

                if (mapProvider.isFlying) {
                  mapProvider.stopCameraFlight();
                  return;
                }

                AppHaptics.selectionClick();
                FocusScope.of(context).unfocus();

                await mapProvider.handleMapTap(point, latlng);
                mapProvider.addNativeDestinationPin(latlng);

                if (!mounted) return; // 🚀 CRITICAL SAFEGUARD ADDED
                mapProvider.targetDestination = latlng;
                mapProvider.setDestinationSelected(true);

                // if (!context.mounted) return;
                // await mapProvider.autoDrawRouteTo(latlng, context);
              },
              onMapLongClick: (point, latlng) async {
                AppHaptics.heavyImpact();
                _engine.camera?.animateSearchFlight(latlng);

                final provider =
                    Provider.of<MapProvider>(context, listen: false);
                provider.addNativeDestinationPin(latlng);

                // 🧭 Set destination for the AnimatedMapPin overlay
                provider.setTargetDestination(latlng);

                await provider.drawDroppedPin(latlng);

                PlaceModel? place;
                try {
                  place = await PlaceEnrichmentService()
                      .reverseGeocode(latlng.latitude, latlng.longitude);
                } catch (e) {
                  debugPrint("Reverse Geocode skipped: $e");
                }

                if (!mounted) {
                  return; // 🚀 CRITICAL SAFEGUARD ADDED (No background crashes)
                }

                final finalPlace = place ??
                    PlaceModel(
                        placeId: "dropped_pin_${latlng.latitude}",
                        name: "Dropped Pin",
                        address:
                            "${latlng.latitude.toStringAsFixed(4)}, ${latlng.longitude.toStringAsFixed(4)}",
                        latitude: latlng.latitude,
                        longitude: latlng.longitude,
                        categories: ["Pin"]);

                provider.setTappedPlace(finalPlace);
                provider.setDestinationSelected(true);
                _engine.executeSearchFlight(latlng, place: finalPlace);
              },
              onMapCreated: (controller) {
                controller.addListener(_onCameraMove);

                // 🧭 CRITICAL FIX: Store the controller on MapProvider's engine
                // so that provider.controller is non-null for AnimatedMapPin
                // and all other consumers that project LatLng → screen coords.
                final mapProvider =
                    Provider.of<MapProvider>(context, listen: false);
                mapProvider.engine.mapController = controller;
              },
              onStyleLoadedCallback: () {
                final mapProvider =
                    Provider.of<MapProvider>(context, listen: false);
                final mapController = mapProvider.controller;
                if (mapController != null) {
                  final locService = Provider.of<GlobalLocationService>(context,
                      listen: false);
                  _engine.onMapCreated(
                      mapController, widget.isDark, locService, this);
                }
              },
              onCameraIdle: () {
                if (_engine.mapController == null ||
                    _engine.mapController!.cameraPosition == null) {
                  return;
                }
                Provider.of<MapProvider>(context, listen: false)
                    .updateMapCenter(
                        _engine.mapController!.cameraPosition!.target,
                        _engine.mapController!.cameraPosition!.zoom);
              },
            ),
          if (_isFetchingStyle)
            Positioned.fill(
              child: Container(
                color: widget.isDark
                    ? Colors.black.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.3),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        color: widget.isDark
                            ? Colors.black.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.5),
                        child: const CircularProgressIndicator(
                            color: Color(0xFF00E5FF)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 110,
            left: 0,
            right: 0,
            child: Consumer<MapProvider>(
              builder: (context, provider, child) {
                return AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: provider.isDestinationSelected ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !provider.isDestinationSelected,
                    child: Center(
                      child: RidelGlass(
                        borderRadius: BorderRadius.circular(30),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildModeButton(context, provider,
                                  CupertinoIcons.car_detailed, 'driving'),
                              _buildModeButton(context, provider,
                                  Icons.motorcycle_rounded, 'twowheeler'),
                              _buildModeButton(context, provider,
                                  Icons.directions_walk_rounded, 'walking'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 100),
            right: 20,
            bottom: isDesktop ? 40 : dynamicBottomPosition,
            // 🚀 ValueListenableBuilder wrap to update opacity during map pan without full screen rebuild
            child: ValueListenableBuilder<String>(
                valueListenable: _interactionState,
                builder: (context, interactionStateValue, child) {
                  final provider = Provider.of<MapProvider>(context);
                  final bool isTiltingActive = interactionStateValue == "tilt";

                  bool showPill =
                      !provider.isActiveNavigation || !provider.isAutoTracking;

                  double finalControlOpacity =
                      (isTiltingActive || !showControls || !showPill)
                          ? 0.0
                          : buttonOpacity;
                  bool ignoreControls = isTiltingActive ||
                      !showControls ||
                      buttonOpacity == 0.0 ||
                      !showPill;

                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: finalControlOpacity,
                    child: IgnorePointer(
                      ignoring: ignoreControls,
                      child: Consumer<MapProvider>(
                        builder: (context, provider, child) {
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder:
                                (Widget child, Animation<double> animation) {
                              return ScaleTransition(
                                  scale: animation,
                                  child: FadeTransition(
                                      opacity: animation, child: child));
                            },
                            child: provider.isDestinationSelected
                                ? GestureDetector(
                                    key: const ValueKey('directions_btn'),
                                    onTap: () async {
                                      AppHaptics.heavyImpact();
                                      await provider
                                          .calculateAndDrawNativeRoute(
                                              context, provider.currentNavMode);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 12),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.black.withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(30),
                                        border: Border.all(
                                            color: const Color(0xFF00E5FF),
                                            width: 1.5),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF00E5FF)
                                                .withValues(alpha: 0.3),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                              CupertinoIcons
                                                  .arrow_turn_up_right,
                                              color: Color(0xFF00E5FF),
                                              size: 20),
                                          SizedBox(width: 8),
                                          Text(
                                            "Directions",
                                            style: TextStyle(
                                                color: Color(0xFF00E5FF),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : GestureDetector(
                                    key: const ValueKey('locate_btn'),
                                    onTap: () {
                                      final p = Provider.of<MapProvider>(
                                          context,
                                          listen: false);
                                      if (p.currentRouteResult != null &&
                                          !p.isActiveNavigation) {
                                        p.start3DNavigation();
                                      } else if (p.isActiveNavigation &&
                                          !p.isAutoTracking) {
                                        p.recenter3DNavigation();
                                      } else {
                                        p.engine.onLocateMeTapped();
                                      }
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(50),
                                      child: BackdropFilter(
                                        filter: ui.ImageFilter.blur(
                                            sigmaX: 24.0, sigmaY: 24.0),
                                        child: Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            color: isLightMode
                                                ? Colors.white
                                                    .withValues(alpha: 0.65)
                                                : const Color(0xFF1E1E1E),
                                            shape: BoxShape.circle,
                                            border: isLightMode
                                                ? Border.all(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.8),
                                                    width: 1.0)
                                                : null,
                                            boxShadow: isLightMode
                                                ? [
                                                    BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                                alpha: 0.05),
                                                        blurRadius: 16,
                                                        offset:
                                                            const Offset(0, 4))
                                                  ]
                                                : [
                                                    BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                                alpha: 0.3),
                                                        blurRadius: 8,
                                                        offset:
                                                            const Offset(0, 4))
                                                  ],
                                          ),
                                          child: Center(
                                            child: Icon(
                                                CupertinoIcons.location_fill,
                                                color: isLightMode
                                                    ? Colors.black87
                                                    : Colors.white),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                    ),
                  );
                }),
          ),
          Positioned(
            right: 20,
            top: MediaQuery.of(context).padding.top + 20,
            child: ValueListenableBuilder<double>(
              valueListenable: _sheetProgress,
              builder: (context, progress, child) {
                final double offsetY = -(progress * 250);
                double opacity = 1.0;
                if (progress > 0.6) {
                  opacity = (1.0 - ((progress - 0.6) / 0.4)).clamp(0.0, 1.0);
                }

                return IgnorePointer(
                  ignoring: opacity <= 0.05,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.translate(
                      offset: Offset(0, offsetY),
                      child: child,
                    ),
                  ),
                );
              },
              // 🚀 Second ValueListenableBuilder for Map Aesthetics Button Opacity
              child: ValueListenableBuilder<String>(
                  valueListenable: _interactionState,
                  builder: (context, interactionStateValue, child) {
                    final provider = Provider.of<MapProvider>(context);
                    final bool isTiltingActive =
                        interactionStateValue == "tilt";

                    bool showPill = !provider.isActiveNavigation ||
                        !provider.isAutoTracking;

                    double finalControlOpacity =
                        (isTiltingActive || !showControls || !showPill)
                            ? 0.0
                            : buttonOpacity;
                    bool ignoreControls = isTiltingActive ||
                        !showControls ||
                        buttonOpacity == 0.0 ||
                        !showPill;

                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: finalControlOpacity,
                      child: IgnorePointer(
                        ignoring: ignoreControls,
                        child: AnimatedBuilder(
                          animation: _fluidAnimation,
                          builder: (context, child) {
                            double progress = _fluidAnimation.value;
                            double width = ui.lerpDouble(
                                50, isDesktop ? 250 : 250, progress)!;
                            double height = ui.lerpDouble(
                                50, isDesktop ? 60 : 300, progress)!;

                            return RepaintBoundary(
                              // 🚀 PERFORMANCE FIX: GPU blurring cached
                              child: Container(
                                width: width,
                                height: height,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                      progress > 0.5 ? 24 : 100),
                                  boxShadow: isLightMode
                                      ? [
                                          BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.05),
                                              blurRadius: 16,
                                              offset: const Offset(0, 4))
                                        ]
                                      : [
                                          BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.4),
                                              blurRadius: 24,
                                              offset: const Offset(0, 12)),
                                          BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.2),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4)),
                                        ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                      progress > 0.5 ? 24 : 100),
                                  child: BackdropFilter(
                                    filter: ui.ImageFilter.blur(
                                        sigmaX: 25.0, sigmaY: 25.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isLightMode
                                            ? Colors.white
                                                .withValues(alpha: 0.65)
                                            : const Color(0xFF0B0E17)
                                                .withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(
                                            progress > 0.5 ? 24 : 100),
                                        border: isLightMode
                                            ? Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.8),
                                                width: 1.0)
                                            : Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.08),
                                                width: 1.0),
                                      ),
                                      child: Stack(
                                        children: [
                                          if (progress > 0.1)
                                            Opacity(
                                              opacity: progress,
                                              child: SingleChildScrollView(
                                                physics:
                                                    const BouncingScrollPhysics(),
                                                child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 16,
                                                      vertical: 20),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  left: 8),
                                                          child: Text(
                                                              "Map Themes",
                                                              style: TextStyle(
                                                                  color: isLightMode
                                                                      ? Colors
                                                                          .black87
                                                                      : Colors
                                                                          .white,
                                                                  fontSize: 18,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold))),
                                                      const SizedBox(
                                                          height: 12),
                                                      _buildThemeSlider(),
                                                      if (isDesktop)
                                                        IconButton(
                                                            icon: Icon(
                                                                Icons.close,
                                                                color: widget.isDark
                                                                    ? Colors
                                                                        .white54
                                                                    : Colors
                                                                        .black54,
                                                                size: 20),
                                                            onPressed:
                                                                _toggleCard),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (progress < 0.9)
                                            Opacity(
                                              opacity: 1 - progress,
                                              child: GestureDetector(
                                                onTap: _toggleCard,
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                child: Center(
                                                  child: Icon(
                                                      CupertinoIcons
                                                          .square_stack_3d_up,
                                                      color: isLightMode
                                                          ? Colors.black87
                                                          : Colors.white,
                                                      size: 22),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSlider() {
    final isDark = widget.isDark;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1E1E).withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 15,
              spreadRadius: 2)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Map Aesthetics",
              style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildThemeBtn("Dark Mode", Icons.dark_mode_rounded,
                  MapThemeType.dark, isDark),
              _buildThemeBtn("Light Mode", Icons.light_mode_rounded,
                  MapThemeType.light, isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeBtn(
      String title, IconData icon, MapThemeType type, bool isDark) {
    bool isSelected = _currentTheme == type;
    return GestureDetector(
      onTap: () {
        AppHaptics.selectionClick();
        setState(() {
          _currentTheme = type;
          _userOverrodeTheme = true; // User explicitly chose a map theme
          _updateStyleFuture();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : Colors.black)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : (isDark ? Colors.white24 : Colors.black12)),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 24,
                color: isSelected
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? Colors.white54 : Colors.black54)),
            const SizedBox(height: 6),
            Text(title,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? (isDark ? Colors.black : Colors.white)
                        : (isDark ? Colors.white54 : Colors.black54))),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(
      BuildContext context, MapProvider provider, IconData icon, String mode) {
    final isSelected = provider.currentNavMode == mode;
    return GestureDetector(
      onTap: () async {
        AppHaptics.lightImpact();
        await provider.setNavMode(context, mode);
        if (!context.mounted) return;
        await provider.calculateAndDrawNativeRoute(context, mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isSelected
              ? const Color(0xFF00E5FF)
              : (Theme.of(context).brightness == Brightness.light
                  ? Colors.black54
                  : Colors.white54),
        ),
      ),
    );
  }
}

class PremiumMapSkeleton extends StatefulWidget {
  final bool isDark;
  const PremiumMapSkeleton({super.key, required this.isDark});
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
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor =
        widget.isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE0E0E0);
    final highlightColor =
        widget.isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F5F5);
    final bgColor = widget.isDark ? const Color(0xFF05070B) : Colors.white;

    return Container(
      color: bgColor,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              return LinearGradient(
                colors: [baseColor, highlightColor, baseColor],
                stops: const [0.1, 0.5, 0.9],
                begin: const Alignment(-1.0, -0.3),
                end: const Alignment(1.0, 0.3),
                transform:
                    SlidingGradientTransform(slidePercent: _controller.value),
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: Stack(
          children: [
            // Fake Map Elements (Blocks/Roads)
            Positioned(top: 100, left: 20, child: _buildFakeBlock(120, 150)),
            Positioned(top: 120, right: 40, child: _buildFakeBlock(180, 80)),
            Positioned(top: 300, left: -20, child: _buildFakeBlock(250, 200)),
            Positioned(
                bottom: 200, right: 20, child: _buildFakeBlock(150, 250)),
            Positioned(bottom: 50, left: 50, child: _buildFakeBlock(200, 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildFakeBlock(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
    );
  }
}

class SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const SlidingGradientTransform({required this.slidePercent});
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
        bounds.width * (slidePercent * 2 - 1), 0.0, 0.0);
  }
}
