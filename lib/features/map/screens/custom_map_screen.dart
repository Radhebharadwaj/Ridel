import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/map/map_style_helper.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'dart:typed_data'; 
import 'dart:ui';
import 'dart:async';
import 'dart:convert'; 
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:ridel/core/services/global_location_service.dart';

import '../map_engine/map_engine.dart';
import '../map_engine/controllers/map_mode_controller.dart';
import '../map_engine/controllers/map_camera_controller.dart';
import 'package:ridel/core/providers/app_navigation_provider.dart';

class CustomMapScreen extends StatefulWidget {
  final bool isDark;
  final ValueChanged<double>? onCardProgress;
  final ValueChanged<bool>? onThemeChanged;
  final ValueChanged<bool>? onWeatherVisibilityChanged;
  final ValueChanged<bool>? onMapInteraction;

  const CustomMapScreen({
    super.key,
    required this.isDark,
    this.onCardProgress,
    this.onThemeChanged,
    this.onWeatherVisibilityChanged,
    this.onMapInteraction,
  });

  @override
  State<CustomMapScreen> createState() => _CustomMapScreenState();
}

class _CustomMapScreenState extends State<CustomMapScreen> with TickerProviderStateMixin {
  late MapEngine _engine;
  late Future<String> _mapStyleFuture;
  GlobalLocationService? _locationService;

  late AnimationController _cardAnimController;
  late Animation<double> _fluidAnimation;
  late AnimationController _extrusionAnimController;

  final ValueNotifier<double> _zoomNotifier = ValueNotifier(14.5);
  final ValueNotifier<double> _tiltNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> _bearingNotifier = ValueNotifier(0.0);
  final ValueNotifier<bool> _zoomScaleVisible = ValueNotifier(false);

  bool _isWeatherVisible = true;
  String _interactionState = "none";
  Timer? _interactionDebounceTimer;
  Timer? _zoomScaleDebounceTimer;

  double _panStartTilt = 0.0;
  double _panStartY = 0.0;

  @override
  void initState() {
    super.initState();
    _loadCleanMapStyle(widget.isDark);

    _engine = MapEngine();
    _engine.addListener(() {
      if (mounted) setState(() {});
    });

    _cardAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fluidAnimation = CurvedAnimation(parent: _cardAnimController, curve: Curves.easeOutCubic);
    _cardAnimController.addListener(() {
      if (widget.onCardProgress != null) widget.onCardProgress!(_fluidAnimation.value);
    });

    _extrusionAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _extrusionAnimController.addListener(() {
      _engine.updateExtrusionProgress(_extrusionAnimController.value);
    });
    Provider.of<MapProvider>(context, listen: false).addListener(_onMapSearchTriggered);

    // 🚀 THE MAGIC: Location ko continuously track karne ka listener
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _locationService = Provider.of<GlobalLocationService>(context, listen: false);
      _locationService?.addListener(_onLocationUpdated);
    });
  }

  void _onMapSearchTriggered() {
    final provider = Provider.of<MapProvider>(context, listen: false);

    if (provider.targetLocation != null) {
      final target = provider.targetLocation!;
      _engine.camera?.animateSearchFlight(target);
      _engine.layers?.showSearchPin(target); 
      provider.clearTargetLocation(); 
    }
  }

  void _onLocationUpdated() {
    if (!mounted || _locationService?.currentPosition == null) return;
    
    final provider = Provider.of<MapProvider>(context, listen: false);
    
    if (provider.isNavigatingToStation) {
      provider.checkIfArrived(
        _locationService!.currentPosition!.latitude,
        _locationService!.currentPosition!.longitude,
        () {
          // 🎉 SUCCESS! User Station pahuch gaya!
          AppHaptics.heavyImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("You have arrived at the station! Switching to Metro Map...", style: TextStyle(color: Colors.white)), 
              backgroundColor: Colors.green
            )
          );

          Provider.of<AppNavigationProvider>(context, listen: false).setTab(1); 
        }
      );
    }
  }

  void _loadCleanMapStyle(bool isDark) {
    _mapStyleFuture = Future.delayed(const Duration(milliseconds: 800), () async {
      try {
        String styleString = await MapStyleHelper.getOlaStyle(isDark);
        Map<String, dynamic> styleJson = jsonDecode(styleString);

        styleJson['glyphs'] = "https://orangemug.github.io/font-glyphs/glyphs/{fontstack}/{range}.pbf";

        if (styleJson['layers'] != null) {
          List<dynamic> validLayers = [];
          
          for (var layer in styleJson['layers']) {

            String layerId = layer['id'] ?? '';
            if (layerId.contains('transit_rail_hatching') || 
                layerId.contains('tunnel_transit_rail') ||
                layerId.contains('bridge_transit_rail')) {
              continue; 
            }
            
            if (layer['layout'] != null && layer['layout']['text-font'] != null) {
              layer['layout']['text-font'] = ["Roboto Regular"];
            }
            validLayers.add(layer);
          }
 
          styleJson['layers'] = validLayers;
        }
        return jsonEncode(styleJson);
      } catch (e) {
        throw Exception("Failed to load map style"); 
      }
    });
  }

  @override
  void dispose() {
    _locationService?.removeListener(_onLocationUpdated); 
    
    Provider.of<MapProvider>(context, listen: false).removeListener(_onMapSearchTriggered);
    _interactionDebounceTimer?.cancel();
    _zoomScaleDebounceTimer?.cancel();
    _cardAnimController.dispose();
    _extrusionAnimController.dispose();
    _zoomNotifier.dispose();
    _tiltNotifier.dispose();
    _bearingNotifier.dispose();
    _zoomScaleVisible.dispose();
    _engine.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CustomMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark) {
      setState(() => _loadCleanMapStyle(widget.isDark));
      Future.delayed(const Duration(milliseconds: 800), () {
        _engine.isDarkTheme = widget.isDark;
        _engine.syncEngineState();
        if (_engine.mode.currentStyle == MapStyle.mode3D) {
          _engine.layers?.updateBuildingExtrusion(1.0, widget.isDark);
        }
      });
    }
  }

  void _onCameraMove() {
    if (_engine.mapController == null || _engine.mapController!.cameraPosition == null) return;
    final cam = _engine.mapController!.cameraPosition!;

    bool isZoomChanged = (cam.zoom - _zoomNotifier.value).abs() > 0.001;

    if (isZoomChanged && _interactionState != "tilt") {
      _zoomScaleVisible.value = true;
      _zoomScaleDebounceTimer?.cancel();
      _zoomScaleDebounceTimer = Timer(const Duration(milliseconds: 800), () {
        _zoomScaleVisible.value = false;
      });
    }

    if (!isZoomChanged && _interactionState != "tilt") _setMapInteractionState("pan");

    _zoomNotifier.value = cam.zoom;
    _tiltNotifier.value = cam.tilt;
    _bearingNotifier.value = cam.bearing;

    _checkWeatherVisibility(cam.zoom, cam.target);
  }

  String _getRealTimeScaleText(double currentZoom) {
    if (_engine.mapController == null || _engine.mapController!.cameraPosition == null) return "0 m";
    final cam = _engine.mapController!.cameraPosition!;
    double resolution = 156543.03 * math.cos(cam.target.latitude * math.pi / 180) / math.pow(2, currentZoom);
    double distanceInMeters = 80.0 * resolution;
    if (distanceInMeters >= 1000) return "${(distanceInMeters / 1000).toStringAsFixed(1)} km";
    return "${distanceInMeters.round()} m";
  }

  void _checkWeatherVisibility(double zoom, LatLng target) {
    var r = 6371; var dLat = (target.latitude - 28.6139) * (math.pi/180); var dLon = (target.longitude - 77.2090) * (math.pi/180);
    var a = math.sin(dLat/2) * math.sin(dLat/2) + math.cos(28.6139 * (math.pi/180)) * math.cos(target.latitude * (math.pi/180)) * math.sin(dLon/2) * math.sin(dLon/2);
    double distFromCenter = r * (2 * math.atan2(math.sqrt(a), math.sqrt(1-a)));

    bool shouldShow = zoom >= 12.0 && distFromCenter <= 6.0 && _engine.mode.currentMode == MapMode.explore;

    if (_isWeatherVisible != shouldShow) {
      _isWeatherVisible = shouldShow;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.onWeatherVisibilityChanged != null) widget.onWeatherVisibilityChanged!(_isWeatherVisible);
      });
    }
  }

  void _toggle3DCity() {
    AppHaptics.mediumImpact();
    _engine.toggle3D();
    if (_engine.mode.currentStyle == MapStyle.mode3D) {
      _extrusionAnimController.forward();
    } else {
      _extrusionAnimController.reverse();
    }
  }

  void _setMapInteractionState(String newState) {
    if (_interactionState != newState) {
      setState(() => _interactionState = newState);
      if (widget.onMapInteraction != null) widget.onMapInteraction!(newState == "tilt");
    }
    _interactionDebounceTimer?.cancel();
    if (newState == "pan") {
      _interactionDebounceTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted && _interactionState != "tilt") {
          setState(() => _interactionState = "none");
          if (widget.onMapInteraction != null) widget.onMapInteraction!(false);
        }
      });
    }
  }

  // 🔥 NETWORK RETRY LOGIC
  void _retryLoadingMap() {
    AppHaptics.mediumImpact();
    setState(() {
      _loadCleanMapStyle(widget.isDark);
    });
  }

  // 🔥 LOADING STATE UI
  Widget _buildLoadingState() {
    return Container(
      color: widget.isDark ? const Color(0xFF0B0E17) : const Color(0xFFF2F4F8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 🚀 THE FIX: Purane emoji ki jagah naya premium Icon call kiya
            const _PulsingGlobeIcon(), 
            const SizedBox(height: 24),
            Text(
              "Loading Map...", 
              style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.w600)
            ),
            const SizedBox(height: 8),
            Text(
              "Fetching your world...", 
              style: TextStyle(color: (widget.isDark ? Colors.white : Colors.black).withOpacity(0.5), fontSize: 14)
            ),
          ],
        ),
      ),
    );
  }

  // 🔥 ERROR / SLOW NETWORK STATE UI
  Widget _buildErrorState() {
    return Container(
      color: widget.isDark ? const Color(0xFF0B0E17) : const Color(0xFFF2F4F8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 🚀 THE FIX: Purane emoji ki jagah premium Error Icon lagaya
            const _PulsingErrorIcon(), 
            const SizedBox(height: 24),
            Text("Network Connection Slow", style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text("We're having trouble loading the map.\nPlease check your internet connection.", textAlign: TextAlign.center, style: TextStyle(color: (widget.isDark ? Colors.white : Colors.black).withOpacity(0.5), fontSize: 14, height: 1.4)),
            const SizedBox(height: 28),
            CupertinoButton(
              color: const Color(0xFF00E5FF).withOpacity(0.15),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              borderRadius: BorderRadius.circular(20),
              onPressed: _retryLoadingMap,
              child: const Text("Retry Connection", style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.w600)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildLocateIcon() {
    if (_engine.camera?.state == MapCameraState.free || _engine.camera == null) {
      return const Icon(CupertinoIcons.location, color: Colors.white70, size: 22);
    } else if (_engine.camera?.state == MapCameraState.follow) {

      return const Icon(CupertinoIcons.location_fill, color: Color(0xFF00E5FF), size: 22);
    } else {

      return const Icon(CupertinoIcons.location_north_fill, color: Color(0xFF00E5FF), size: 22);
    }
  }

  void _toggleCard() {
    if (_cardAnimController.isCompleted) _cardAnimController.reverse(); else _cardAnimController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardMaxWidth = screenWidth - 32;

    final Color appGlassBaseColor = const Color(0xFF1E1E1E).withOpacity(0.70);
    final Border appGlassBorder = Border.all(color: Colors.white.withOpacity(0.18), width: 1.0);
    const double glassBlur = 25.0;

    final bool isTiltingActive = _interactionState == "tilt";

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<String>(
        future: _mapStyleFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return _buildLoadingState();
          } else if (snapshot.hasError || (snapshot.hasData && snapshot.data!.isEmpty)) {
            return _buildErrorState();
          }

          return Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onLongPressStart: (details) {
                  AppHaptics.heavyImpact();
                  _setMapInteractionState("tilt");
                  _panStartTilt = _tiltNotifier.value;
                  _panStartY = details.globalPosition.dy;
                },
                onLongPressMoveUpdate: (details) {
                  double dy = details.globalPosition.dy - _panStartY;
                  double newTilt = (_panStartTilt - (dy / 3)).clamp(0.0, 60.0);
                  _tiltNotifier.value = newTilt;
                  _engine.mapController?.moveCamera(CameraUpdate.tiltTo(newTilt));
                },
                onLongPressEnd: (_) {
                  _interactionDebounceTimer = Timer(const Duration(milliseconds: 600), () {
                     if (mounted) _setMapInteractionState("none");
                  });
                },
                child: MapLibreMap(
                  styleString: snapshot.data ?? "",
                  initialCameraPosition: const CameraPosition(target: LatLng(28.6139, 77.2090), zoom: 14.5, tilt: 0.0, bearing: 0),
                  minMaxZoomPreference: const MinMaxZoomPreference(4.5, 20.0),
                  cameraTargetBounds: CameraTargetBounds(LatLngBounds(southwest: const LatLng(6.75, 68.0), northeast: const LatLng(35.5, 97.5))),
                  
                  // 🔥 ZERO-ERROR FIX: In 3 lines ko update kiya gaya hai
                  compassEnabled: false,
                  logoViewMargins: const math.Point(-5000, -5000), // Logo ko 5000px bahar phek diya
                  attributionButtonMargins: const math.Point(-5000, -5000), // Blue button ko 5000px bahar phek diya
                  
                  myLocationEnabled: true,
                  myLocationRenderMode: kIsWeb ? MyLocationRenderMode.normal : MyLocationRenderMode.compass,
                  
                  trackCameraPosition: true,
                  onCameraTrackingDismissed: _engine.onUserPannedMap,
                  onMapCreated: (controller) {
                    Provider.of<MapProvider>(context, listen: false).setController(controller);
                    controller.addListener(_onCameraMove);
                    final locService = Provider.of<GlobalLocationService>(context, listen: false);
                    _engine.onMapCreated(controller, widget.isDark, locService);
                  },
                ),
              ),

              ValueListenableBuilder<bool>(
                valueListenable: _zoomScaleVisible,
                builder: (context, isVisible, child) {
                  return AnimatedPositioned(
                    duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic,
                    bottom: MediaQuery.of(context).padding.bottom + 120, left: (isVisible && !isTiltingActive) ? 20 : -100,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200), opacity: (isVisible && !isTiltingActive) ? 1.0 : 0.0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ValueListenableBuilder<double>(
                            valueListenable: _zoomNotifier,
                            builder: (context, zoom, child) => Text(_getRealTimeScaleText(zoom), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5, shadows: [BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))])),
                          ),
                          const SizedBox(height: 4),
                          Container(width: 80, height: 6, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white, width: 2), left: BorderSide(color: Colors.white, width: 2), right: BorderSide(color: Colors.white, width: 2)), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))]))
                        ],
                      ),
                    ),
                  );
                }
              ),

              AnimatedPositioned(
                duration: const Duration(milliseconds: 300), curve: Curves.easeOutBack,
                bottom: MediaQuery.of(context).padding.bottom + 120, left: isTiltingActive ? 20 : -100,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200), opacity: isTiltingActive ? 1.0 : 0.0,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _tiltNotifier,
                    builder: (context, tilt, child) => Text("${tilt.toInt()}°", style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, shadows: [BoxShadow(color: Colors.black54, blurRadius: 15, offset: Offset(0, 4))])),
                  ),
                ),
              ),

              if (_engine.mode.currentMode == MapMode.driving)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16, right: 16,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: (_fluidAnimation.value > 0.1 || isTiltingActive) ? 0.0 : 1.0,
                    child: PointerInterceptor(
                      child: Container(
                        width: 70, height: 70,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: appGlassBaseColor, border: appGlassBorder, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))]),
                        child: ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: _engine.realTimeSpeedKmph),
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.easeOutCubic,
                              builder: (context, speed, child) {
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 60, height: 60,
                                      child: CircularProgressIndicator(
                                        value: speed / 140.0,
                                        strokeWidth: 3.5, backgroundColor: Colors.white.withOpacity(0.1),
                                        valueColor: AlwaysStoppedAnimation<Color>(speed > 80 ? Colors.redAccent : const Color(0xFF00E5FF)),
                                      ),
                                    ),
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(speed.toInt().toString(), style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, height: 1.1, shadows: [BoxShadow(color: speed > 80 ? Colors.redAccent : const Color(0xFF00E5FF), blurRadius: 8)])),
                                        const Text("km/h", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ],
                                );
                              }
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              AnimatedBuilder(
                animation: _fluidAnimation,
                builder: (context, child) {
                  double progress = _fluidAnimation.value;
                  return ValueListenableBuilder<double>(
                    valueListenable: _bearingNotifier,
                    builder: (context, bearing, child) {
                      bool isNorth = (bearing % 360).abs() < 1.0 || (bearing % 360).abs() > 359.0;
                      bool shouldHide = (isNorth || progress > 0.1 || isTiltingActive);

                      return Positioned(
                        right: 16, bottom: MediaQuery.of(context).padding.bottom + 230,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 300), opacity: shouldHide ? 0.0 : 1.0,
                          child: IgnorePointer(
                            ignoring: shouldHide,
                            child: GestureDetector(
                              onTap: _engine.onCompassTapped,
                              child: Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 15, offset: const Offset(0, 6))]),
                                child: ClipOval(
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
                                    child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: appGlassBaseColor, border: appGlassBorder), child: CustomPaint(size: const Size(48, 48), painter: SmartCompassPainter(bearing: bearing))),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                  );
                },
              ),

              AnimatedBuilder(
                animation: _fluidAnimation,
                builder: (context, child) {
                  double progress = _fluidAnimation.value;
                  double currentWidth = lerpDouble(48, cardMaxWidth, progress)!;
                  double currentHeight = lerpDouble(104, 260, progress)!;
                  double currentRadius = lerpDouble(24, 34, progress)!;

                  return Positioned(
                    right: 16, bottom: MediaQuery.of(context).padding.bottom + 100,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300), opacity: isTiltingActive ? 0.0 : 1.0,
                      child: PointerInterceptor(
                        child: TapRegion(
                          onTapOutside: (_) { if (progress > 0) _cardAnimController.reverse(); },
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (details) {
                              double delta = (-details.delta.dx - details.delta.dy) / 250.0;
                              _cardAnimController.value += delta;
                            },
                            onPanEnd: (details) {
                              if (_cardAnimController.value > 0.4 || details.velocity.pixelsPerSecond.dx < -800 || details.velocity.pixelsPerSecond.dy < -800) { _cardAnimController.forward(); } else { _cardAnimController.reverse(); }
                            },
                            child: Container(
                              width: currentWidth, height: currentHeight,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(currentRadius), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 25, offset: const Offset(0, 10))]),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(currentRadius),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
                                  child: Container(
                                    decoration: BoxDecoration(color: appGlassBaseColor, border: appGlassBorder, borderRadius: BorderRadius.circular(currentRadius)),
                                    child: Stack(
                                      children: [
                                        Opacity(
                                          opacity: (1 - (progress * 2)).clamp(0.0, 1.0),
                                          child: IgnorePointer(
                                            ignoring: progress > 0.1 || isTiltingActive,
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: SizedBox(
                                                width: 48,
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    GestureDetector(behavior: HitTestBehavior.opaque, onTap: _toggleCard, child: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Icon(CupertinoIcons.square_stack_3d_up, color: Colors.white, size: 22))),
                                                    Container(height: 1, width: 32, color: Colors.white24),
                                                    GestureDetector(behavior: HitTestBehavior.opaque, onTap: _engine.onLocateMeTapped, child: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: _buildLocateIcon())),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),

                                        Opacity(
                                          opacity: ((progress - 0.5) * 2).clamp(0.0, 1.0),
                                          child: IgnorePointer(
                                            ignoring: progress < 0.9 || isTiltingActive,
                                            child: OverflowBox(
                                              minWidth: cardMaxWidth, maxWidth: cardMaxWidth, alignment: Alignment.topCenter,
                                              child: ScrollConfiguration(
                                                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                                                child: SingleChildScrollView(
                                                  physics: const NeverScrollableScrollPhysics(),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.center,
                                                      children: [
                                                        const Text("Map Modes", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                                        const SizedBox(height: 18),
                                                        // REPLACE YOUR FITTED BOX ROW AT LINE 458 WITH THIS:
                                                        SingleChildScrollView(
                                                          scrollDirection: Axis.horizontal,
                                                          physics: const BouncingScrollPhysics(),
                                                          child: Row(
                                                            mainAxisAlignment: MainAxisAlignment.start,
                                                            children: [
                                                              _buildVectorModeButton("Explore", "EXPLORE", _engine.mode.currentMode == MapMode.explore, () => _engine.setMode(MapMode.explore)),
                                                              const SizedBox(width: 12),
                                                              _buildVectorModeButton("Driving", "DRIVE", _engine.mode.currentMode == MapMode.driving, () => _engine.setMode(MapMode.driving)),
                                                              const SizedBox(width: 12),
                                                              _buildVectorModeButton("Transit", "TRANSIT", _engine.mode.currentMode == MapMode.transit, () => _engine.setMode(MapMode.transit)),
                                                              const SizedBox(width: 12),
                                                              _buildVectorModeButton("3D City", "3D", _engine.mode.currentStyle == MapStyle.mode3D, _toggle3DCity),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(height: 24),
                                                        _buildThemeSlider(),
                                                      ],
                                                    ),
                                                  ),
                                                ),
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
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildThemeSlider() {
    
    // 🔥 Premium Custom Icon (Moon + 2 Stars)
    Widget buildPremiumDarkIcon() {
      final color = widget.isDark ? const Color(0xFF00E5FF) : Colors.white54;
      return SizedBox(
        width: 18, height: 18,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(bottom: 0, left: 0, child: Icon(Icons.nightlight_round, size: 14, color: color)),
            Positioned(top: 0, right: 3, child: Icon(Icons.star, size: 6, color: color)),
            Positioned(top: 5, right: -2, child: Icon(Icons.star, size: 4, color: color.withOpacity(0.7))),
          ],
        ),
      );
    }

    return Container(
      height: 58, padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withOpacity(0.08)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)]),
      child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth;
        return Stack(
          children: [
            AnimatedPositioned(duration: const Duration(milliseconds: 250), curve: Curves.easeOutBack, left: widget.isDark ? 0 : w / 2, top: 0, bottom: 0, width: w / 2, child: Container(decoration: BoxDecoration(color: const Color(0xFF00E5FF).withOpacity(0.18), borderRadius: BorderRadius.circular(25), border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.8), width: 1.5)))),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque, onTap: () { if(widget.onThemeChanged!=null && !widget.isDark) widget.onThemeChanged!(true); }, 
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center, 
                        children: [
                          buildPremiumDarkIcon(), // 🔥 Yahan cloud ki jagah premium icon aa gaya
                          const SizedBox(width: 6), 
                          Text("Dark", style: TextStyle(color: widget.isDark ? const Color(0xFF00E5FF) : Colors.white54, fontWeight: FontWeight.bold, fontSize: 15))
                        ]
                      )
                    )
                  )
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque, onTap: () { if(widget.onThemeChanged!=null && widget.isDark) widget.onThemeChanged!(false); }, 
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center, 
                        children: [
                          Icon(Icons.wb_sunny_rounded, size: 16, color: !widget.isDark ? const Color(0xFF00E5FF) : Colors.white54), 
                          const SizedBox(width: 6), 
                          Text("Light", style: TextStyle(color: !widget.isDark ? const Color(0xFF00E5FF) : Colors.white54, fontWeight: FontWeight.bold, fontSize: 15))
                        ]
                      )
                    )
                  )
                ),
              ],
            )
          ],
        );
      }),
    );
  }

  Widget _buildVectorModeButton(String title, String type, bool isSelected, VoidCallback onTap) {
    return ElasticButton(
      isSelected: isSelected, onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70, height: 70, 
            decoration: BoxDecoration(
              color: const Color(0xFF161A25), 
              borderRadius: BorderRadius.circular(16), 
              // 🔥 Sirf sharp border, no outer glow
              border: Border.all(color: isSelected ? const Color(0xFF00E5FF) : Colors.transparent, width: 2.5), 
            ), 
            child: ClipRRect(borderRadius: BorderRadius.circular(13), child: CustomMapVectorIcon(type: type, isSelected: isSelected))
          ),
          const SizedBox(height: 8), 
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class SmartCompassPainter extends CustomPainter {
  final double bearing;
  SmartCompassPainter({required this.bearing});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2); final radius = size.width / 2;
    canvas.save();
    canvas.translate(center.dx, center.dy); canvas.rotate(-bearing * math.pi / 180); canvas.translate(-center.dx, -center.dy);
    final tickPaint = Paint()..color = Colors.white.withOpacity(0.4)..strokeWidth = 1.5..strokeCap = StrokeCap.round;
    for (int i = 0; i < 12; i++) {
      if (i == 9) continue;
      final angle = (i * 30 - 90) * math.pi / 180; final isCardinal = i % 3 == 0; final tickLength = isCardinal ? 5.0 : 3.0;
      final start = Offset(center.dx + (radius - tickLength - 3) * math.cos(angle), center.dy + (radius - tickLength - 3) * math.sin(angle));
      final end = Offset(center.dx + (radius - 3) * math.cos(angle), center.dy + (radius - 3) * math.sin(angle));
      canvas.drawLine(start, end, tickPaint);
    }
    final northAngle = -90 * math.pi / 180;
    final path = Path();
    path.moveTo(center.dx + (radius - 2) * math.cos(northAngle), center.dy + (radius - 2) * math.sin(northAngle));
    path.lineTo(center.dx + (radius - 8) * math.cos(northAngle - 0.25), center.dy + (radius - 8) * math.sin(northAngle - 0.25));
    path.lineTo(center.dx + (radius - 8) * math.cos(northAngle + 0.25), center.dy + (radius - 8) * math.sin(northAngle + 0.25));
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFF3B30));
    canvas.restore();
    String currentHeading = _getHeadingString(bearing);
    final textPainter = TextPainter(text: TextSpan(text: currentHeading, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0)), textDirection: TextDirection.ltr);
    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - (textPainter.width / 2), center.dy - (textPainter.height / 2)));
  }

  String _getHeadingString(double b) {
    double normalized = (b % 360 + 360) % 360;
    if (normalized >= 337.5 || normalized < 22.5) return 'N'; if (normalized >= 22.5 && normalized < 67.5) return 'NE';
    if (normalized >= 67.5 && normalized < 112.5) return 'E'; if (normalized >= 112.5 && normalized < 157.5) return 'SE';
    if (normalized >= 157.5 && normalized < 202.5) return 'S'; if (normalized >= 202.5 && normalized < 247.5) return 'SW';
    if (normalized >= 247.5 && normalized < 292.5) return 'W'; if (normalized >= 292.5 && normalized < 337.5) return 'NW';
    return 'N';
  }
  @override bool shouldRepaint(SmartCompassPainter oldDelegate) => oldDelegate.bearing != bearing;
}

class CustomMapVectorIcon extends StatelessWidget {
  final String type; final bool isSelected;
  const CustomMapVectorIcon({super.key, required this.type, required this.isSelected});
  @override Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(top: 20, left: -10, child: Container(width: 100, height: 4, color: Colors.white10, transform: Matrix4.rotationZ(0.2))),
        Positioned(top: 50, left: -10, child: Container(width: 100, height: 4, color: Colors.white10, transform: Matrix4.rotationZ(-0.2))),
        if (type == "EXPLORE") ...[Positioned(top: 15, left: 10, child: Container(width: 25, height: 25, decoration: BoxDecoration(color: Colors.green.withOpacity(0.3), borderRadius: BorderRadius.circular(4)))), Positioned(bottom: 10, right: 10, child: Container(width: 15, height: 20, decoration: BoxDecoration(color: Colors.green.withOpacity(0.3), borderRadius: BorderRadius.circular(4)))), Positioned(top: 10, right: 15, child: const Icon(Icons.location_on, color: Colors.amber, size: 14)), Positioned(bottom: 20, left: 15, child: const Icon(Icons.circle, color: Colors.redAccent, size: 6))] else if (type == "DRIVE") ...[Positioned(top: -10, left: 30, child: Container(width: 12, height: 100, color: Colors.black45, transform: Matrix4.rotationZ(0.4))), Positioned(top: 20, left: 45, child: Container(width: 4, height: 35, color: Colors.redAccent, transform: Matrix4.rotationZ(0.4))), Positioned(top: 40, left: 25, child: const Icon(Icons.navigation, color: Colors.white, size: 16, shadows: [BoxShadow(blurRadius: 4, color: Colors.black)])), ] else if (type == "TRANSIT") ...[Positioned(top: -10, left: 20, child: Container(width: 4, height: 100, color: Colors.blueAccent, transform: Matrix4.rotationZ(0.6))), Positioned(top: -10, left: 40, child: Container(width: 4, height: 100, color: Colors.redAccent, transform: Matrix4.rotationZ(-0.3))), Positioned(top: 35, left: -10, child: Container(width: 100, height: 4, color: Colors.greenAccent, transform: Matrix4.rotationZ(0.1))), ] else if (type == "3D") ...[Positioned(bottom: 15, left: 10, child: _buildCube()), Positioned(bottom: 25, left: 35, child: _buildCube(height: 30)), Positioned(bottom: 10, left: 45, child: _buildCube(height: 15))],
        if (!isSelected) Container(color: Colors.black.withOpacity(0.4)),
      ],
    );
  }
  Widget _buildCube({double height = 20}) { return Container(width: 12, height: height, decoration: const BoxDecoration(color: Color(0xFF9E9E9E), borderRadius: BorderRadius.only(topLeft: Radius.circular(2), topRight: Radius.circular(2)), boxShadow: [BoxShadow(color: Colors.black54, offset: Offset(2, 2), blurRadius: 2)], border: Border(left: BorderSide(color: Colors.white70, width: 2), top: BorderSide(color: Colors.white70, width: 2)))); }
}

class ElasticButton extends StatefulWidget {
  final Widget child; final VoidCallback onTap; final bool isSelected;
  const ElasticButton({super.key, required this.child, required this.onTap, required this.isSelected});
  @override _ElasticButtonState createState() => _ElasticButtonState();
}
class _ElasticButtonState extends State<ElasticButton> {
  double _scale = 1.0;
  @override Widget build(BuildContext context) { return GestureDetector(behavior: HitTestBehavior.opaque, onTapDown: (_) => setState(() => _scale = 0.90), onTapUp: (_) { setState(() => _scale = 1.0); widget.onTap(); }, onTapCancel: () => setState(() => _scale = 1.0), child: AnimatedScale(scale: _scale, duration: const Duration(milliseconds: 150), curve: Curves.easeOutBack, child: widget.child)); }
}


// ============================================================================
// 🔥 PREMIUM PULSING ICONS (Paste at the VERY BOTTOM of the file)
// ============================================================================

// 1. Globe Icon (For Loading State)
class _PulsingGlobeIcon extends StatefulWidget {
  const _PulsingGlobeIcon();

  @override
  State<_PulsingGlobeIcon> createState() => _PulsingGlobeIconState();
}

class _PulsingGlobeIconState extends State<_PulsingGlobeIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.97, end: 1.03).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Transform.scale(scale: _animation.value, child: child),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF00E5FF).withOpacity(0.08),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.15), blurRadius: 40, spreadRadius: 5)],
        ),
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFF00E5FF)],
          ).createShader(bounds),
          child: const Icon(Icons.public_rounded, size: 54, color: Colors.white),
        ),
      ),
    );
  }
}

// 2. Error/Satellite Icon (For Network Issue State)
class _PulsingErrorIcon extends StatefulWidget {
  const _PulsingErrorIcon();

  @override
  State<_PulsingErrorIcon> createState() => _PulsingErrorIconState();
}

class _PulsingErrorIconState extends State<_PulsingErrorIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.97, end: 1.03).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Transform.scale(scale: _animation.value, child: child),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withOpacity(0.08),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.orangeAccent.withOpacity(0.15), blurRadius: 40, spreadRadius: 5)],
        ),
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Colors.white, Colors.deepOrangeAccent],
          ).createShader(bounds),
          child: const Icon(Icons.satellite_alt_rounded, size: 54, color: Colors.white),
        ),
      ),
    );
  }
}