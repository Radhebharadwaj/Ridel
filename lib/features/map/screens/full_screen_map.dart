import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/map/map_style_helper.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';
import 'package:ridel/features/map/widgets/search_sheet/map_search_sheet.dart';
import 'package:ridel/core/providers/app_navigation_provider.dart';
import 'package:ridel/features/map/widgets/map_theme_selector.dart';
import 'package:ridel/features/map/widgets/weather_floating_widget.dart';
import 'package:ridel/features/map/widgets/turn_by_turn_banner.dart';
import 'package:ridel/core/utils/location_guard.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ridel/core/utils/toast_service.dart';
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
  final GlobalKey _mapKey = GlobalKey();
  late AnimationController _fadeScaleController;
  late Animation<double> _fadeScaleAnimation;

  String? _resolvedStyleJson;
  bool _isLoadingStyle = true;
  Brightness? _lastBrightness;
  MapLibreMapController? _tempController;

  MapThemeType? _currentTheme;
  bool _userOverrodeMapTheme = false;

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

        final themeToSet =
            _currentTheme ?? (isDark ? MapThemeType.dark : MapThemeType.light);
        Provider.of<MapProvider>(context, listen: false).setTheme(themeToSet);
      }
    } catch (e) {
      debugPrint("❌ Error fixing Ola Style: $e");
      // 🚀 CRITICAL FIX: Unlock the UI even if the style fetch fails
      if (mounted) {
        setState(() {
          _isLoadingStyle = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 600;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final double topMargin =
        isDesktop ? 32.0 : MediaQuery.of(context).padding.top + 24.0;
    final double sideMargin = isDesktop ? 32.0 : 20.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerMove: (event) {
                final mapProvider =
                    Provider.of<MapProvider>(context, listen: false);
                if (mapProvider.isActiveNavigation) {
                  mapProvider.setUserPanning(true);
                }
              },
              child: MapLibreMap(
                key: _mapKey,
                styleString: _resolvedStyleJson ??
                    '{"version": 8, "sources": {}, "layers": []}',
                onMapCreated: (controller) {
                  if (_tempController != null) return;
                  _tempController = controller;

                  // 🚀 CRITICAL FIX 1: Engine ko controller pass karna zaroori hai!
                  final mapProvider =
                      Provider.of<MapProvider>(context, listen: false);
                  mapProvider.engine.mapController = controller;
                },
                onStyleLoadedCallback: () async {
                  final controller = _tempController;
                  if (controller == null) return;

                  try {
                    final Uint8List bytes = await MapProvider.loadAndResizeImage('assets/images/custom_pin.png', 36);
                    await controller.addImage('custom_pin', bytes);
                    debugPrint("Custom Pin Successfully Injected");
                  } catch (e) {
                    debugPrint("Failed to load custom_pin: $e");
                  }

                  try {
                    final Uint8List yellowPinBytes = await MapProvider.loadAndResizeImage('assets/images/add_places.png', 32);
                    await controller.addImage('intermediate_pin', yellowPinBytes);
                    debugPrint("Intermediate Pin Successfully Injected");
                  } catch (e) {
                    debugPrint("Failed to load intermediate_pin: $e");
                    final Uint8List transparentPixel = Uint8List.fromList([
                      137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68,
                      82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196,
                      137, 0, 0, 0, 11, 73, 68, 65, 84, 8, 215, 99, 96, 0, 2, 0,
                      0, 5, 0, 1, 226, 38, 5, 155, 0, 0, 0, 0, 73, 69, 78, 68,
                      174, 66, 96, 130
                    ]);
                    await controller.addImage('intermediate_pin', transparentPixel);
                  }

                  try {
                    // Failsafe for missing required images that crash WebGL
                    final Uint8List transparentPixel = Uint8List.fromList([
                      137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68,
                      82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196,
                      137, 0, 0, 0, 11, 73, 68, 65, 84, 8, 215, 99, 96, 0, 2, 0,
                      0, 5, 0, 1, 226, 38, 5, 155, 0, 0, 0, 0, 73, 69, 78, 68,
                      174, 66, 96, 130
                    ]);
                    await controller.addImage('Arrow', transparentPixel);
                    await controller.addImage('arrow', transparentPixel);
                    await controller.addImage('custom-marker', transparentPixel);
                  } catch (e) {
                    debugPrint("Asset Load Error: $e");
                  }

                  if (!context.mounted) return;
                  final mapProvider = Provider.of<MapProvider>(context, listen: false);
                  mapProvider
                      .engine
                      .onMapCreated(
                          controller,
                          isDark,
                          Provider.of<GlobalLocationService>(context,
                              listen: false),
                          this);
                },
                onMapClick: (point, latLng) async {
                  FocusScope.of(context).unfocus();
                  final mapProvider =
                      Provider.of<MapProvider>(context, listen: false);

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

                  bool handled =
                      await mapProvider.handleRouteClick(point, latLng);
                  if (!handled) {
                    mapProvider.clearTargetLocation();
                  }
                },
                onMapLongClick: (Point<double> point, LatLng coordinates) {
                  final mapProvider =
                      Provider.of<MapProvider>(context, listen: false);

                  // 🚀 Free the camera from blue dot
                  mapProvider.setAutoTracking(false);
                  mapProvider.setUserPanning(true);

                  mapProvider.handleMapLongPress(coordinates);
                },
                initialCameraPosition: const CameraPosition(
                    target: LatLng(28.6139, 77.2090),
                    zoom: 14.5, // 🚀 Fixed zoom to match custom_map_screen
                    tilt: 0.0,
                    bearing: 0),
                minMaxZoomPreference: const MinMaxZoomPreference(4.5, 20.0),
                compassEnabled: false,
                doubleClickZoomEnabled: true,
                scrollGesturesEnabled: true,
                zoomGesturesEnabled: true,
                tiltGesturesEnabled: true,

                // 🚀 CRITICAL FIX 2: Restore native blue dot logic exactly like custom_map_screen
                myLocationEnabled: true,
                myLocationTrackingMode: Provider.of<MapProvider>(context, listen: false).isAutoTracking
                    ? (kIsWeb ? MyLocationTrackingMode.tracking : MyLocationTrackingMode.trackingCompass)
                    : MyLocationTrackingMode.none,
                myLocationRenderMode: MyLocationRenderMode.normal,
                trackCameraPosition: true,

                logoViewMargins: const Point(-5000, -5000),
                attributionButtonMargins: const Point(-5000, -5000),
                onCameraTrackingDismissed: () {
                  final mapProvider =
                      Provider.of<MapProvider>(context, listen: false);
                  if (mapProvider.isActiveNavigation) {
                    mapProvider.setAutoTracking(false);
                    mapProvider.setUserPanning(true);
                  }
                  mapProvider.engine.onUserPannedMap();
                },
                onUserLocationUpdated: (location) {
                  final mapProvider =
                      Provider.of<MapProvider>(context, listen: false);
                  final pos = location.position;
                  mapProvider.updateCurrentLocation(pos);
                },
                onCameraIdle: () async {
                  final mapProvider =
                      Provider.of<MapProvider>(context, listen: false);
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
                      final cam = ctrl.cameraPosition;
                      if (cam != null) {
                        mapProvider.updateMapCenter(cam.target, cam.zoom);
                      }
                    } catch (_) {}
                  }
                },
              ),
            ),
          ),

          // 🚀 DROP PIN MODE CENTER OVERLAY
          Positioned.fill(
            child: Selector<MapProvider, bool>(
              selector: (context, provider) => provider.isDropPinMode || provider.isAddingStopMode,
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

          // 🚀 0.5: SKELETON MAP OVERLAY
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_isLoadingStyle,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _isLoadingStyle ? 1.0 : 0.0,
                child: PremiumMapSkeleton(isDark: isDark),
              ),
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
                                color: Colors.cyan.withValues(alpha: 0.15),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                              BoxShadow(
                                color:
                                    Colors.purpleAccent.withValues(alpha: 0.15),
                                blurRadius: 40,
                                spreadRadius: -10,
                              ),
                            ],
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.8),
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

          Positioned.fill(
            child: MapSearchSheet(
              key: const ValueKey('map_search_sheet'),
              isMapTabActive: widget.isMapTabActive,
              onSearchModeChanged: (isActive) {},
              onSearchSubmitted: (query) {},
              onProgressChanged: (progress) {
                widget.searchSheetProgressNotifier.value = progress;
              },
              onBackToPreviousTab: () {
                Provider.of<AppNavigationProvider>(context, listen: false)
                    .goBack();
              },
            ),
          ),

          // 🚀 1. SMOOTH WEATHER WIDGET (Mobile = Left, Desktop = Right)
          Positioned(
            top: topMargin,
            left: isDesktop ? null : sideMargin,
            right: isDesktop ? sideMargin : null,
            child: Selector<MapProvider, bool>(
              selector: (context, provider) => !provider.isActiveNavigation,
              builder: (context, showWeather, child) {
                return IgnorePointer(
                  ignoring: !showWeather,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: showWeather ? 1.0 : 0.0,
                    child: child,
                  ),
                );
              },
              // 🚀 FIX: Removed AnimatedAlign and _buildPointerSafeWrapper to destroy the full-screen invisible shield
              child: WeatherFloatingWidget(onMapThemeChanged: (isDark) {}),
            ),
          ),


          // 🚀 3. TURN-BY-TURN BANNER
          Positioned(
            top: topMargin,
            left: sideMargin,
            right: sideMargin,
            child: TurnByTurnBanner(isDark: isDark),
          ),

          Positioned(
            bottom:
                isDesktop ? 32.0 : (MediaQuery.paddingOf(context).bottom + 124),
            left: sideMargin,
            child: Selector<MapProvider, bool>(
              selector: (context, provider) => provider.isActiveNavigation,
              builder: (context, isActiveNavigation, child) {
                if (!isActiveNavigation) return const SizedBox.shrink();

                final camera = Provider.of<MapProvider>(context, listen: false)
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
                              sigmaX: kIsWeb ? 4.0 : 24.0,
                              sigmaY: kIsWeb ? 4.0 : 24.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B0E17)
                                  .withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(36),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
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
                return kIsWeb ? PointerInterceptor(child: content) : content;
              }),
            ),
          ),

          Positioned(
            bottom: isDesktop ? 32.0 : 0.0,
            right: sideMargin,
            child: ValueListenableBuilder<double>(
              valueListenable: widget.searchSheetProgressNotifier,
              builder: (context, progress, pillChild) {
                if (isDesktop) {
                  return pillChild!;
                }
                final screenSize = MediaQuery.sizeOf(context);
                final safeBottom = MediaQuery.paddingOf(context).bottom;
                final minS =
                    ((86.0 + safeBottom) / screenSize.height).clamp(0.05, 0.40);
                const maxS = 0.55;

                final sheetSize = minS + progress * (maxS - minS);
                final sheetHeight = sheetSize * screenSize.height;
                final bottomOffset = sheetHeight + 20.0;

                return AnimatedBuilder(
                  animation: _fadeScaleAnimation,
                  builder: (context, animChild) {
                    final animValue =
                        (1.0 - _fadeScaleAnimation.value).clamp(0.0, 1.0);
                    return Transform.translate(
                      offset: Offset(0, -bottomOffset),
                      child: Transform.scale(
                        scale: animValue,
                        alignment: Alignment.bottomCenter,
                        child: Opacity(
                          opacity: animValue,
                          child: animChild,
                        ),
                      ),
                    );
                  },
                  child: pillChild,
                );
              },
              child: Listener(
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
                        selector: (context, provider) => provider.controller,
                        builder: (context, controller, _) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: AppleStyleCompass(controller: controller),
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
                              duration: const Duration(milliseconds: 300),
                              opacity: isVisible ? 1.0 : 0.0,
                              child: child,
                            ),
                          );
                        },
                        child: Builder(builder: (context) {
                          final content = Container(
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
                              child: RepaintBoundary(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                      sigmaX: kIsWeb ? 4.0 : 20.0,
                                      sigmaY: kIsWeb ? 4.0 : 20.0),
                                  child: Container(
                                    width: 48,
                                    decoration: BoxDecoration(
                                        color: !isDark
                                            ? Colors.white
                                                .withValues(alpha: 0.75)
                                            : const Color(0xFF0B0E17)
                                                .withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(50),
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
                                        Builder(builder: (buttonContext) {
                                          return GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              AppHaptics.heavyImpact();
                                              MapThemeSelector.show(
                                                  buttonContext, // 🚀 CRITICAL: Use the localized context
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
                                          );
                                        }),
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
                                            AppHaptics.selectionClick(); // Instant feedback

                                            // Fire and forget - do not block the UI!
                                            Future.microtask(() async {
                                              if (!context.mounted) return;

                                              final mapProvider =
                                                  Provider.of<MapProvider>(
                                                      context,
                                                      listen: false);

                                              if (mapProvider.isActiveNavigation &&
                                                  !mapProvider.isAutoTracking) {
                                                // STATE 4: RE-CENTER
                                                debugPrint(
                                                    "📍 Re-Center Tapped!");
                                                await mapProvider
                                                    .recenter3DNavigation();
                                              } else if (mapProvider.isRouteCalculated &&
                                                  !mapProvider.isActiveNavigation) {
                                                // STATE 3: START NAVIGATION
                                                debugPrint(
                                                    "🚀 Start Navigation Tapped! Entering 3D Mode...");
                                                await mapProvider
                                                    .start3DNavigation();
                                              } else if (mapProvider.targetDestination != null) {
                                                // STATE 2: GET DIRECTIONS
                                                debugPrint(
                                                    "🛣️ Fetching Route...");
                                                // Only fetch location asynchronously
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
                                              child: Selector<
                                                  MapProvider,
                                                  (
                                                    bool,
                                                    bool,
                                                    bool,
                                                    bool,
                                                    bool
                                                  )>(
                                                selector: (context, provider) =>
                                                    (
                                                  provider.isActiveNavigation,
                                                  provider.isAutoTracking,
                                                  provider.isRouteCalculated,
                                                  provider.targetDestination !=
                                                      null,
                                                  provider
                                                      .isUserVisibleOnScreen,
                                                ),
                                                builder: (context, _, __) {
                                                  final mapProvider =
                                                      Provider.of<MapProvider>(
                                                          context,
                                                          listen: false);
                                                  return AnimatedSwitcher(
                                                    duration: const Duration(
                                                        milliseconds: 300),
                                                    transitionBuilder:
                                                        (child, animation) {
                                                      return ScaleTransition(
                                                          scale: animation,
                                                          child: child);
                                                    },
                                                    child: _buildDynamicIcon(
                                                        context, mapProvider),
                                                  );
                                                },
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
                          );
                          return kIsWeb
                              ? PointerInterceptor(child: content)
                              : content;
                        }),
                      ),
                      // 🚀 3. ZOOM PILL: Sirf Desktop par dikhega, mobile par clean layout!
                      if (isDesktop) ...[
                        const SizedBox(height: 16),
                        Builder(builder: (context) {
                          final content = Container(
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
                              child: RepaintBoundary(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                      sigmaX: kIsWeb ? 4.0 : 25.0,
                                      sigmaY: kIsWeb ? 4.0 : 25.0),
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
                                            final mapProvider =
                                                Provider.of<MapProvider>(
                                                    context,
                                                    listen: false);
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
                                            final mapProvider =
                                                Provider.of<MapProvider>(
                                                    context,
                                                    listen: false);
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
                          );
                          return kIsWeb
                              ? PointerInterceptor(child: content)
                              : content;
                        }), // Close Builder
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLocateMeTapped(MapProvider mapProvider) async {
    debugPrint("🎯 [DEBUG] Locate Me button clicked!");
    final localContext = ToastService.navigatorKey.currentContext ?? context;

    try {
      // 🚨 CRITICAL: Append .timeout to prevent infinite browser deadlock
      LocationPermission permission = await Geolocator.checkPermission().timeout(const Duration(seconds: 2));

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission().timeout(const Duration(seconds: 2));
        if (permission == LocationPermission.denied) {
          throw Exception("Permission denied by user.");
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception("Permission permanently denied.");
      }

      // If granted, proceed:
      debugPrint("✅ [DEBUG] Permission granted. Fetching location...");
      final locService = Provider.of<GlobalLocationService>(context, listen: false);
      await locService.forceRefreshLocation(); // Will use IP fallback if GPS times out

      final pos = locService.currentPosition;
      if (pos != null && mapProvider.controller != null) {
        await mapProvider.controller!.updateMyLocationTrackingMode(MyLocationTrackingMode.none);

        await mapProvider.controller!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 16.5, tilt: 0.0, bearing: 0.0),
          ),
          duration: const Duration(milliseconds: 1000),
        );
        mapProvider.setAutoTracking(true);
      }
    } on TimeoutException catch (_) {
      // Catches the infinite hang caused by strict browser shields
      debugPrint("⏳ [DEBUG] Geolocator timed out (Browser silently blocked it).");
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
              final safeContext = ToastService.navigatorKey.currentContext ?? context;
              
              Future.delayed(const Duration(milliseconds: 400), () {
                debugPrint("🟢 [DEBUG] 400ms delay finished, firing Warning Toast...");
                try {
                  // 🚨 Changed to showWarning to bypass the isMapScreen invisibility filter
                  ToastService.showWarning(
                    safeContext, 
                    "Click the lock icon (🔒) in your browser URL bar to allow location.", 
                    title: "Browser Settings"
                  );
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
              final safeContext = ToastService.navigatorKey.currentContext ?? context;
              
              Future.delayed(const Duration(milliseconds: 400), () {
                debugPrint("🟢 [DEBUG] 400ms delay finished, firing Warning Toast...");
                try {
                  // 🚨 Changed to showWarning to bypass the isMapScreen invisibility filter
                  ToastService.showWarning(
                    safeContext, 
                    "Click the lock icon (🔒) in your browser URL bar to allow location.", 
                    title: "Browser Settings"
                  );
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
      _bearingNotifier.value = newBearing;
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
                      filter: ImageFilter.blur(sigmaX: kIsWeb ? 4.0 : 20.0, sigmaY: kIsWeb ? 4.0 : 20.0),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: !isDark
                              ? Colors.white.withValues(alpha: 0.75)
                              : const Color(0xFF0B0E17).withValues(alpha: 0.75),
                          shape: BoxShape.circle,
                          border: !isDark
                              ? Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.0)
                              : Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
                          boxShadow: !isDark
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))]
                              : [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 12)),
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4)),
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
                                painter: AppleCompassDialPainter(isDark: isDark),
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
    if (_timer != null || _delayTimer != null) return;
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

class PremiumMapSkeleton extends StatelessWidget {
  final bool isDark;

  const PremiumMapSkeleton({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? const Color(0xFF0B0E17) : const Color(0xFFF1F2F4),
      child: Center(
        child: SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              isDark ? Colors.white24 : Colors.black26,
            ),
            strokeWidth: 3,
          ),
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
