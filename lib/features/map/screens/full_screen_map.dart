import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/map/map_style_helper.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/features/map/widgets/search_sheet/map_search_sheet.dart';
import 'package:ridel/features/map/widgets/map_theme_selector.dart';
import 'package:ridel/features/map/widgets/weather_floating_widget.dart';

import 'package:ridel/features/map/widgets/turn_by_turn_banner.dart';

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
  late AnimationController _fadeScaleController;
  late Animation<double> _fadeScaleAnimation;

  String? _resolvedStyleJson;
  bool _isLoadingStyle = true;
  bool _hasMapBooted = false; // Prevents background WebGL allocation
  Brightness? _lastBrightness;
  MapLibreMapController? _tempController;

  MapThemeType? _currentTheme;
  bool _userOverrodeMapTheme = false;

  // 🚀 The map widget strictly acts as a passive canvas
  double _sheetExtent = 0.3;

  final GlobalKey _searchSheetKey = GlobalKey();
  final GlobalKey<WeatherFloatingWidgetState> _weatherWidgetKey =
      GlobalKey<WeatherFloatingWidgetState>();

  @override
  void initState() {
    super.initState();
    _fadeScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeScaleAnimation = CurvedAnimation(
      parent: _fadeScaleController,
      curve: Curves.easeOutCubic,
    );
    widget.searchSheetProgressNotifier.addListener(_onProgressChanged);
  }

  void _onProgressChanged() {
    final progress = widget.searchSheetProgressNotifier.value;
    if (progress > 0.8 &&
        _fadeScaleController.status != AnimationStatus.forward &&
        _fadeScaleController.status != AnimationStatus.completed) {
      _fadeScaleController.forward();
    } else if (progress <= 0.8 &&
        _fadeScaleController.status != AnimationStatus.reverse &&
        _fadeScaleController.status != AnimationStatus.dismissed) {
      _fadeScaleController.reverse();
    }
  }

  @override
  void dispose() {
    widget.searchSheetProgressNotifier.removeListener(_onProgressChanged);
    _fadeScaleController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentBrightness = Theme.of(context).brightness;
    // 🚀 CRITICAL FIX: Prevent reload glitch on keyboard open or screen resize
    if (_lastBrightness != currentBrightness || _resolvedStyleJson == null) {
      _lastBrightness = currentBrightness;

      // 🚀 FIX: Auto-sync map theme to system brightness (unless user overrode)
      if (!_userOverrodeMapTheme) {
        _currentTheme = currentBrightness == Brightness.dark
            ? MapThemeType.dark
            : MapThemeType.light;
      }

      _fetchAndFixOlaStyle(currentBrightness);
    }
  }

  Future<void> _fetchAndFixOlaStyle(Brightness brightness) async {
    if (!mounted) return;
    setState(() {
      _isLoadingStyle = true;
    });

    try {
      final isDark = brightness == Brightness.dark;
      String finalStyle =
          await MapStyleHelper.getOlaStyle(isDark, themeType: _currentTheme);

      if (mounted) {
        setState(() {
          _resolvedStyleJson = finalStyle;
          _isLoadingStyle = false;
          _lastBrightness = brightness;
        });

        // 🚀 FIX: Sync MapProvider's route theme so polyline colors match
        final themeToSet =
            _currentTheme ?? (isDark ? MapThemeType.dark : MapThemeType.light);
        Provider.of<MapProvider>(context, listen: false).setTheme(themeToSet);
      }
    } catch (e) {
      debugPrint("❌ Error fixing Ola Style: $e");
    }
  }

  // 🚀 HELPER: Mobile par PointerInterceptor memory khata hai, isliye conditionally render karenge
  Widget _buildPointerSafeWrapper({required Widget child}) {
    return kIsWeb ? PointerInterceptor(child: child) : child;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMapTabActive && !_hasMapBooted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _hasMapBooted = true);
      });
    }

    // Removing the conditional early return to prevent WebGL tearing

    final bool isDesktop = MediaQuery.of(context).size.width >= 600;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final double topMargin =
        isDesktop ? 32.0 : MediaQuery.of(context).padding.top + 24.0;
    final double sideMargin = isDesktop ? 32.0 : 20.0;

    if (_isLoadingStyle || _resolvedStyleJson == null) {
      return PremiumMapSkeleton(isDark: isDark);
    }

    return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Stack(
            children: [
              Positioned.fill(
                child: Builder(
                  builder: (context) {
                    final mapProvider =
                        Provider.of<MapProvider>(context, listen: false);
                    return Listener(
                        behavior: HitTestBehavior.deferToChild,
                        onPointerMove: (event) {
                          if (_weatherWidgetKey.currentState?.isExpanded ==
                              true) {
                            _weatherWidgetKey.currentState?.collapse();
                          }
                          if (mapProvider.isActiveNavigation) {
                            mapProvider.setUserPanning(true);
                          }
                        },
                        child: MapLibreMap(
                          styleString: _resolvedStyleJson!,
                          onMapCreated: (controller) {
                            _tempController = controller;
                          },
                          onStyleLoadedCallback: () async {
                            if (_tempController != null) {
                              await mapProvider.engine.onMapCreated(
                                  _tempController!,
                                  isDark,
                                  Provider.of<GlobalLocationService>(context,
                                      listen: false),
                                  this);

                              // 0. Silence corrupt layer spam
                              try {
                                await mapProvider.engine.mapController?.removeLayer('bridge_transit_rail_hatching');
                              } catch (e) {
                                // Ignore if it doesn't exist
                              }

                              // 1. Turn on the GPS stream (mounts the blue dot)
                              await mapProvider.engine.mapController?.updateMyLocationTrackingMode(MyLocationTrackingMode.tracking);
                              // 2. Wait for the engine to register the layer
                              await Future.delayed(const Duration(milliseconds: 150));
                              // 3. Drop the camera lock, but keep the blue dot alive
                              await mapProvider.engine.mapController?.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
                            }
                          },
                          onMapClick: (point, latLng) async {
                            if (_weatherWidgetKey.currentState?.isExpanded ==
                                true) {
                              _weatherWidgetKey.currentState?.collapse();
                            }
                            FocusScope.of(context).unfocus();
                            bool handled = await mapProvider.handleRouteClick(
                                point, latLng);
                            if (!handled) {
                              mapProvider.clearTargetLocation();
                            }
                          },
                          onMapLongClick: (point, latLng) async {
                            AppHaptics.heavyImpact();

                            // 1. Force native layer to drop tracking immediately to prevent WebGL from fighting the flight
                            await mapProvider.engine.mapController?.updateMyLocationTrackingMode(MyLocationTrackingMode.none);

                            // 2. CRITICAL FIX: Event loop breaker to safely disengage WebGL tracking lock
                            await Future.delayed(
                                const Duration(milliseconds: 50));

                            // 3. Resolve destination and place data non-blockingly (already decoupled)
                            mapProvider.handleMapTap(point, latLng);
                          },
                          initialCameraPosition: const CameraPosition(
                              target: LatLng(28.6139, 77.2090), zoom: 12.0),
                          compassEnabled: false,
                          myLocationEnabled: true,
                          myLocationTrackingMode: MyLocationTrackingMode.none, // 🚀 Passive Canvas Lock
                          myLocationRenderMode: MyLocationRenderMode.normal,
                          logoViewMargins:
                              kIsWeb ? null : const Point(-100, -100),
                          attributionButtonMargins:
                              kIsWeb ? null : const Point(-100, -100),
                          onCameraTrackingDismissed: () {
                            mapProvider.engine.onUserPannedMap();
                            if (mapProvider.isActiveNavigation) {
                              mapProvider.setUserPanning(true);
                            }
                          },
                          onUserLocationUpdated: (location) {
                            final pos = location.position;
                            mapProvider.updateCurrentLocation(pos);
                            mapProvider.updateNavigationPuck(
                              pos,
                              location.heading?.trueHeading ??
                                  location.bearing ??
                                  0.0,
                            );
                          },

                          // 🚀 NAYA BULLETPROOF CODE YAHAN SE PASTE KAR:
                          onCameraIdle: () async {
                            final ctrl =
                                mapProvider.controller ?? _tempController;
                            if (ctrl != null) {
                              try {
                                final bounds = await ctrl.getVisibleRegion();

                                // 1. Pehle provider se location nikalne ki koshish karo
                                LatLng? userLoc = mapProvider.currentLocation;

                                // 3. Agar location mil gayi, toh Bounds Check karo!
                                if (userLoc != null) {
                                  bool isVisible = bounds.contains(userLoc);
                                  mapProvider.setUserVisibility(isVisible);
                                }
                              } catch (_) {
                                // Suppressed error
                              }
                            }
                          },
                        ));
                  },
                ),
              ),

              // 🚀 0. SIRI-STYLE EDGE GLOW FOR TTS
              Positioned.fill(
                child: IgnorePointer(
                  child: Consumer<MapProvider>(
                    builder: (context, mapProvider, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: mapProvider.isSpeaking,
                        builder: (context, isSpeaking, _) {
                          return AnimatedOpacity(
                            duration: isSpeaking
                                ? const Duration(milliseconds: 600)
                                : const Duration(milliseconds: 1500),
                            curve: Curves.easeInOutCubic,
                            opacity: isSpeaking ? 1.0 : 0.0,
                            child: ImageFiltered(
                              imageFilter:
                                  ImageFilter.blur(sigmaX: 80.0, sigmaY: 80.0),
                              child: ShaderMask(
                                shaderCallback: (Rect bounds) {
                                  return const SweepGradient(
                                    colors: [
                                      Colors.cyan,
                                      Colors.purpleAccent,
                                      Colors.pinkAccent,
                                      Colors.cyan
                                    ],
                                  ).createShader(bounds);
                                },
                                blendMode: BlendMode.srcIn,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    border: Border.all(
                                        color: Colors.white, width: 30.0),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              // 🚀 1. SMOOTH WEATHER WIDGET (Mobile = Left, Desktop = Right)
              Positioned(
                top: topMargin,
                left: sideMargin,
                right: sideMargin,
                child: Consumer<MapProvider>(
                  builder: (context, mapProvider, child) {
                    final bool showWeather = !mapProvider.isActiveNavigation && _sheetExtent <= 0.5;
                    return IgnorePointer(
                      ignoring: !showWeather,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: showWeather ? 1.0 : 0.0,
                        child: child,
                      ),
                    );
                  },
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    alignment:
                        isDesktop ? Alignment.topRight : Alignment.topLeft,
                    child: _buildPointerSafeWrapper(
                      child: WeatherFloatingWidget(
                        key: _weatherWidgetKey,
                        onMapThemeChanged: (isDark) {},
                      ),
                    ),
                  ),
                ),
              ),

              // 🚀 2. APPLE-STYLE COMPASS (Top Right par aayega)
              Positioned(
                top: topMargin + (isDesktop ? 70 : 0),
                right: sideMargin,
                child:
                    Consumer<MapProvider>(builder: (context, mapProvider, _) {
                  return _buildPointerSafeWrapper(
                    child:
                        AppleStyleCompass(controller: mapProvider.controller),
                  );
                }),
              ),

              // 🚀 3. TURN-BY-TURN BANNER
              Positioned(
                top: topMargin,
                left: sideMargin,
                right: sideMargin,
                child: TurnByTurnBanner(isDark: isDark),
              ),

              Positioned(
                bottom: isDesktop
                    ? 32.0
                    : (MediaQuery.paddingOf(context).bottom + 124),
                left: sideMargin,
                child: Consumer<MapProvider>(
                  builder: (context, mapProvider, child) {
                    if (mapProvider.engine.camera == null) {
                      return const SizedBox.shrink();
                    }
                    return ValueListenableBuilder<bool>(
                        valueListenable:
                            mapProvider.engine.camera!.isUserPanning,
                        builder: (context, isPanning, _) {
                          if (!isPanning || !mapProvider.isActiveNavigation) {
                            return const SizedBox.shrink();
                          }
                          return _buildPointerSafeWrapper(
                            child: RidelBounceButton(
                              onTap: () {
                                AppHaptics.selectionClick();
                                mapProvider.engine.camera!.resetCompass();
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(36),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.4),
                                      blurRadius: 24,
                                      offset: const Offset(0, 12),
                                    ),
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(36),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                        sigmaX: 24, sigmaY: 24),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 14),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0B0E17)
                                            .withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(36),
                                        border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.08),
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
                        });
                  },
                ),
              ),

              AnimatedPositioned(
                duration: const Duration(milliseconds: 0),
                bottom: isDesktop ? 32.0 : (MediaQuery.sizeOf(context).height * _sheetExtent) + 16.0,
                right: sideMargin,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _sheetExtent > 0.5 ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: _sheetExtent > 0.6,
                    child: AnimatedBuilder(
                      animation: _fadeScaleAnimation,
                      builder: (context, animChild) {
                        final animValue =
                            (1.0 - _fadeScaleAnimation.value).clamp(0.0, 1.0);
                        return Transform.scale(
                          scale: animValue,
                          alignment: Alignment.bottomCenter,
                          child: Opacity(
                            opacity: animValue,
                            child: animChild,
                          ),
                        );
                      },
                      child: Consumer<MapProvider>(
                      builder: (context, mapProvider, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 🍏 THE APPLE "PILL" (Map Settings + Locate Me)
                        IgnorePointer(
                          ignoring: !(!mapProvider.isActiveNavigation ||
                              !mapProvider.isAutoTracking),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: (!mapProvider.isActiveNavigation ||
                                    !mapProvider.isAutoTracking)
                                ? 1.0
                                : 0.0,
                            child: _buildPointerSafeWrapper(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(50),
                                  boxShadow: !isDark
                                      ? [
                                          BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.08),
                                              blurRadius: 12,
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
                                  borderRadius: BorderRadius.circular(50),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                        sigmaX: 20.0, sigmaY: 20.0),
                                    child: Container(
                                      width: 48,
                                      decoration: BoxDecoration(
                                          color: !isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.75)
                                              : const Color(0xFF0B0E17)
                                                  .withValues(alpha: 0.75),
                                          borderRadius:
                                              BorderRadius.circular(50),
                                          border: !isDark
                                              ? Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.9),
                                                  width: 1.0)
                                              : Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.08),
                                                  width: 1.0)),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              AppHaptics.heavyImpact();
                                              MapThemeSelector.show(context,
                                                  currentTheme: _currentTheme ??
                                                      (isDark
                                                          ? MapThemeType.dark
                                                          : MapThemeType.light),
                                                  onThemeSelected:
                                                      (selectedTheme) {
                                                setState(() {
                                                  _currentTheme = selectedTheme;
                                                  _userOverrodeMapTheme = true;
                                                  _fetchAndFixOlaStyle(
                                                      Theme.of(context)
                                                          .brightness);
                                                });
                                              });
                                            },
                                            child: SizedBox(
                                              height: 52,
                                              width: 48,
                                              child: Center(
                                                  child: Icon(Icons.map,
                                                      color: isDark
                                                          ? Colors.white70
                                                          : Colors.black87,
                                                      size: 20)),
                                            ),
                                          ),
                                          Container(
                                              height: 1,
                                              width: 48,
                                              color: isDark
                                                  ? Colors.white
                                                      .withValues(alpha: 0.10)
                                                  : Colors.black
                                                      .withValues(alpha: 0.10)),
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              AppHaptics.selectionClick();

                                              Future.microtask(() async {
                                                if (mapProvider
                                                        .isActiveNavigation &&
                                                    !mapProvider
                                                        .isAutoTracking) {
                                                  // STATE 4: RE-CENTER
                                                  debugPrint(
                                                      "📍 Re-Center Tapped!");
                                                  await mapProvider
                                                      .recenter3DNavigation();
                                                } else if (mapProvider
                                                        .isRouteCalculated &&
                                                    !mapProvider
                                                        .isActiveNavigation) {
                                                  // STATE 3: START NAVIGATION
                                                  debugPrint(
                                                      "🚀 Start Navigation Tapped! Entering 3D Mode...");
                                                  await mapProvider
                                                      .start3DNavigation();
                                                } else if (mapProvider
                                                        .targetDestination !=
                                                    null) {
                                                  // STATE 2: GET DIRECTIONS
                                                  debugPrint(
                                                      "🛣️ Fetching Route...");
                                                  if (!context.mounted) return;
                                                  await mapProvider
                                                      .calculateAndDrawNativeRoute(
                                                          context, 'driving');
                                                } else {
                                                  // STATE 1: LOCATE ME (Default)
                                                  debugPrint(
                                                      "📍 Locate Me Tapped!");
                                                  await _handleLocateMeTapped(
                                                      mapProvider);
                                                }
                                              });
                                            },
                                            child: SizedBox(
                                              height: 52,
                                              width: 48,
                                              child: Center(
                                                child: AnimatedSwitcher(
                                                  duration: const Duration(
                                                      milliseconds: 300),
                                                  transitionBuilder:
                                                      (Widget child,
                                                          Animation<double>
                                                              animation) {
                                                    return ScaleTransition(
                                                        scale: animation,
                                                        child: child);
                                                  },
                                                  child: _buildDynamicIcon(
                                                      context, mapProvider),
                                                ),
                                              ),
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
                        // 🚀 3. ZOOM PILL: Sirf Desktop par dikhega, mobile par clean layout!
                        if (isDesktop) ...[
                          const SizedBox(height: 16),
                          _buildPointerSafeWrapper(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: !isDark
                                    ? [
                                        BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.15),
                                            blurRadius: 12,
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
                                borderRadius: BorderRadius.circular(24),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                      sigmaX: 25.0, sigmaY: 25.0),
                                  child: Container(
                                    width: 48,
                                    decoration: BoxDecoration(
                                        color: !isDark
                                            ? Colors.white
                                            : const Color(0xFF0B0E17)
                                                .withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(24),
                                        border: !isDark
                                            ? Border.all(
                                                color: Colors.black
                                                    .withValues(alpha: 0.04),
                                                width: 1.0)
                                            : Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.08),
                                                width: 1.0)),
                                    child: Column(
                                      children: [
                                        _ContinuousZoomButton(
                                          icon: Icons.add_rounded,
                                          isDark: isDark,
                                          onZoomStep: () {
                                            final z = mapProvider.controller
                                                    ?.cameraPosition?.zoom ??
                                                14.0;
                                            mapProvider.controller?.moveCamera(
                                                CameraUpdate.zoomTo(z + 0.06));
                                          },
                                        ),
                                        Container(
                                            height: 1,
                                            width: 30,
                                            color: isDark
                                                ? Colors.white
                                                    .withValues(alpha: 0.10)
                                                : Colors.black
                                                    .withValues(alpha: 0.10)),
                                        _ContinuousZoomButton(
                                          icon: Icons.remove_rounded,
                                          isDark: isDark,
                                          onZoomStep: () {
                                            final z = mapProvider.controller
                                                    ?.cameraPosition?.zoom ??
                                                14.0;
                                            mapProvider.controller?.moveCamera(
                                                CameraUpdate.zoomTo(z - 0.06));
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),

              if (isDesktop)
                DesktopDraggableSearchWrapper(
                  child: MapSearchSheet(
                    key: _searchSheetKey,
                    isMapTabActive: widget.isMapTabActive,
                    onSearchModeChanged: (isSearching) {},
                    onSearchSubmitted: (query) {
                      final mapProvider =
                          Provider.of<MapProvider>(context, listen: false);
                      if (query == "CLEAR_PIN_COMMAND") {
                        mapProvider.engine.layers?.removeSearchPin();
                        return;
                      }
                      mapProvider.searchAndNavigate(query);
                    },
                    onBackToPreviousTab: () {},
                  ),
                )
              else
                NotificationListener<DraggableScrollableNotification>(
                  onNotification: (notification) {
                    setState(() {
                      _sheetExtent = notification.extent;
                    });
                    return false;
                  },
                  child: MapSearchSheet(
                    key: _searchSheetKey,
                    isMapTabActive: widget.isMapTabActive,
                    onSearchModeChanged: (isSearching) {},
                    onSearchSubmitted: (query) {
                      final mapProvider =
                          Provider.of<MapProvider>(context, listen: false);
                      if (query == "CLEAR_PIN_COMMAND") {
                        mapProvider.engine.layers?.removeSearchPin();
                        return;
                      }
                      mapProvider.searchAndNavigate(query);
                    },
                    onBackToPreviousTab: () {},
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: _hasMapBooted,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 400),
                    opacity: _hasMapBooted ? 0.0 : 1.0,
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
  }

  Future<void> _handleLocateMeTapped(MapProvider mapProvider) async {
    if (mapProvider.isFlying) return; // Prevent 45 queued taps from choking the thread
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ToastService.showError(context, "Please enable Location Services.");
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ToastService.showError(context, "Location permission denied.");
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ToastService.showError(
            context,
            "Location permissions are permanently denied. Please enable in App Settings.",
          );
        }
        return;
      }

      if (mounted) {
        final locService = Provider.of<GlobalLocationService>(context, listen: false);
        await locService.forceRefreshLocation();
        
        final userLocation = locService.currentPosition;
        if (userLocation != null) {
          await mapProvider.controller?.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(userLocation.latitude, userLocation.longitude), 
              16.0
            ),
            duration: const Duration(milliseconds: 800),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ToastService.showError(context, "Failed to get location.");
      }
    }
  }

  Widget _buildDynamicIcon(BuildContext context, MapProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color iconColor = isDark ? Colors.white70 : Colors.black87;
    const double defaultSize = 20.0;

    if (provider.isActiveNavigation && !provider.isAutoTracking) {
      // STATE 4: RE-CENTER
      return Icon(
        Icons.navigation_rounded,
        key: const ValueKey('icon_recenter'),
        color: const Color(0xFF0A84FF).withValues(alpha: 0.9),
        size: defaultSize,
      );
    } else if (provider.isRouteCalculated && !provider.isActiveNavigation) {
      // STATE 3: START (Keep this slightly prominent but not glowing)
      return Icon(
        Icons.navigation_rounded, // Upward arrow
        key: const ValueKey('icon_start'),
        color: const Color(0xFF0A84FF)
            .withValues(alpha: 0.9), // Apple Blue but slightly soft
        size: defaultSize,
      );
    } else if (provider.targetDestination != null) {
      // STATE 2: DIRECTIONS (Faded and elegant)
      return Icon(
        Icons.directions_rounded,
        key: const ValueKey('icon_directions'),
        color: iconColor,
        size: defaultSize,
      );
    } else {
      // STATE 1: LOCATE ME (Smart Bounds Sync)
      IconData locateIcon = Icons.my_location_rounded;

      Color locateColor = provider.isUserVisibleOnScreen
          ? iconColor
          : const Color(0xFF0A84FF).withValues(alpha: 0.9);

      return Icon(
        locateIcon,
        key: ValueKey('icon_locate_${provider.isUserVisibleOnScreen}'),
        color: locateColor,
        size: defaultSize,
      );
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
  double _bearing = 0.0;

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
    if ((_bearing - newBearing).abs() > 0.5) {
      setState(() {
        _bearing = newBearing;
      });
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onCameraMove);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isVisible = _bearing.abs() > 2.0;

    Widget compassBody = IgnorePointer(
      ignoring: !isVisible,
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        // 🚀 PERFORMANCE FIX: GPU will only repaint the compass layer during map rotation, saving massive resources!
        child: RepaintBoundary(
          child: GestureDetector(
            onTap: () {
              AppHaptics.mediumImpact();
              widget.controller?.animateCamera(CameraUpdate.bearingTo(0.0));
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF1C1C1E).withValues(alpha: 0.85)
                    : const Color(0xFFF2F2F7).withValues(alpha: 0.90),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
                border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.1),
                    width: 1),
              ),
              child: Transform.rotate(
                angle: -_bearing * (pi / 180.0),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 4,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.redAccent.shade400,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(2)),
                        ),
                      ),
                      Container(
                        width: 4,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white : Colors.grey.shade400,
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(2)),
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
    );

    return kIsWeb ? PointerInterceptor(child: compassBody) : compassBody;
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
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
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
            child: _isMoveMode
                ? (kIsWeb
                    ? PointerInterceptor(child: dragOverlay)
                    : dragOverlay)
                : const SizedBox.shrink(),
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

class _ContinuousZoomButton extends StatefulWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onZoomStep;

  const _ContinuousZoomButton({
    required this.icon,
    required this.isDark,
    required this.onZoomStep,
  });

  @override
  State<_ContinuousZoomButton> createState() => _ContinuousZoomButtonState();
}

class _ContinuousZoomButtonState extends State<_ContinuousZoomButton> {
  Timer? _timer;
  Timer? _delayTimer;

  void _startZooming() {
    _stopZooming();
    AppHaptics.lightImpact();
    widget.onZoomStep();
    _delayTimer = Timer(const Duration(milliseconds: 300), () {
      _timer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
        widget.onZoomStep();
      });
    });
  }

  void _stopZooming() {
    _delayTimer?.cancel();
    _delayTimer = null;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopZooming();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _startZooming(),
      onTapUp: (_) => _stopZooming(),
      onTapCancel: _stopZooming,
      child: SizedBox(
        height: 48,
        width: 48,
        child: Center(
            child: Icon(widget.icon,
                color: widget.isDark ? Colors.white70 : Colors.black87,
                size: 22)),
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
