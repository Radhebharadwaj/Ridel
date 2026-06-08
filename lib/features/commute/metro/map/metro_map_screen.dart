import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:path_drawing/path_drawing.dart';
import 'package:provider/provider.dart';

import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/features/commute/shared/screens/route_result_screen.dart';
import 'package:ridel/features/commute/metro/services/metro_service.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';
import 'package:ridel/features/commute/shared/widgets/commute_search_card.dart';
import 'package:ridel/features/commute/metro/map/metro_data_provider.dart';
import 'package:ridel/features/commute/metro/map/map_models.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/features/commute/shared/models/route_models.dart';

const double tileCanvasSize = 16384.0;
const double tweakX = 0.0;
const double tweakY = 0.0;

class MetroMapScreen extends StatefulWidget {
  final List<String> highlightedLineIds;
  final RouteResult? activeRoute;
  final int? activeStationIndex;
  final bool isPanelOpen;
  final bool showAppBar;

  const MetroMapScreen({
    super.key,
    this.highlightedLineIds = const [],
    this.activeRoute,
    this.activeStationIndex,
    this.isPanelOpen = true,
    this.showAppBar = true,
  });

  @override
  State<MetroMapScreen> createState() => _MetroMapScreenState();
}

class _MetroMapScreenState extends State<MetroMapScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  MapStation? fromStation;
  MapStation? toStation;

  bool _isMapCentered = false;
  bool _isMapReady = false;
  bool _isZoomedToLocation = false;

  bool _isFullScreenUI = false;
  AnimationController? _animController;
  Timer? _zoomTimer;

  final TextEditingController fromCtrl = TextEditingController();
  final TextEditingController toCtrl = TextEditingController();
  final FocusNode fromFocus = FocusNode();
  final FocusNode toFocus = FocusNode();

  void _updateControllers() {
    fromCtrl.text = fromStation?.name ?? "";
    toCtrl.text = toStation?.name ?? "";
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MetroDataProvider>(context, listen: false).fetchMapData();
    });
  }

  @override
  void didUpdateWidget(MetroMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isMapReady &&
        widget.isPanelOpen != oldWidget.isPanelOpen &&
        widget.activeRoute == null) {
      final currentCenter = _mapController.camera.center;
      final currentZoom = _mapController.camera.zoom;

      if (widget.isPanelOpen) {
        final newLng = currentCenter.longitude - 0.06;
        _animatedMapMove(LatLng(currentCenter.latitude, newLng),
            (currentZoom - 0.4).clamp(1.0, 6.0));
      } else {
        final newLng = currentCenter.longitude + 0.06;
        _animatedMapMove(LatLng(currentCenter.latitude, newLng),
            (currentZoom + 0.4).clamp(1.0, 6.0));
      }
    }
  }

  LatLng getLatLngFromSvg(double x, double y) {
    return LatLng(-(y / tileCanvasSize), (x / tileCanvasSize));
  }

  @override
  void dispose() {
    _zoomTimer?.cancel();
    _animController?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _centerOnNewDelhi() {
    if (!_isMapReady || _isMapCentered) return;
    try {
      _mapController.move(getLatLngFromSvg(7700, 7000), 2.0);
      _isMapCentered = true;
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _zoomToFit() {
    _animatedMapMove(getLatLngFromSvg(7700, 7000), 2.0);
    setState(() => _isZoomedToLocation = false);
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    _animController?.stop();
    _animController?.dispose();

    _animController = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    final Animation<double> animation =
        CurvedAnimation(parent: _animController!, curve: Curves.easeOutCubic);

    final latTween = Tween<double>(
        begin: _mapController.camera.center.latitude,
        end: destLocation.latitude);
    final lngTween = Tween<double>(
        begin: _mapController.camera.center.longitude,
        end: destLocation.longitude);
    final zoomTween =
        Tween<double>(begin: _mapController.camera.zoom, end: destZoom);

    _animController!.addListener(() {
      if (!mounted) return;
      _mapController.move(
          LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
          zoomTween.evaluate(animation));
    });

    _animController!.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _animController?.dispose();
        _animController = null;
      }
    });

    _animController!.forward();
  }

  void _startZoom(double delta) {
    AppHaptics.lightImpact();
    _changeZoom(delta);
    _zoomTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _changeZoom(delta * 0.15);
    });
  }

  void _stopZoom() {
    _zoomTimer?.cancel();
  }

  void _changeZoom(double delta) {
    if (!mounted || !_isMapReady) return;
    final newZoom = (_mapController.camera.zoom + delta).clamp(1.0, 6.0);
    _mapController.move(_mapController.camera.center, newZoom);
  }

  void _locateNearestStation() async {
    final locationService =
        Provider.of<GlobalLocationService>(context, listen: false);
    await locationService.forceRefreshLocation();

    if (!mounted) return;

    final position = locationService.currentPosition;

    if (position == null) {
      ToastService.showError(
          context, "Turn on GPS to find your nearest station.");
      return;
    }

    final provider = Provider.of<MetroDataProvider>(context, listen: false);
    final stations = provider.mapData?.stations ?? [];
    if (stations.isEmpty) return;

    MapStation? closestStation;
    double minDistance = double.infinity;
    const distanceCalc = Distance();

    for (var station in stations) {
      if (station.lat != 0.0 && station.lng != 0.0) {
        double d = distanceCalc.distance(
          LatLng(position.latitude, position.longitude),
          LatLng(station.lat, station.lng),
        );
        if (d < minDistance) {
          minDistance = d;
          closestStation = station;
        }
      }
    }

    if (closestStation != null) {
      if (minDistance <= 200.0) {
        AppHaptics.heavyImpact();

        ToastService.showSuccess(
          context,
          closestStation.name,
          title: "Nearest Station", // Ab title change ho jayega
        );

        if (!mounted) return;
        setState(() {
          if (fromStation == null) {
            fromStation = closestStation;
          } else if (toStation == null &&
              closestStation!.id != fromStation!.id) {
            toStation = closestStation;
          }
          _updateControllers();
          _isZoomedToLocation = true;
          _isFullScreenUI = false;
        });
        _animatedMapMove(
            getLatLngFromSvg(closestStation.x, closestStation.y), 3.5);
      } else {
        AppHaptics.lightImpact();
        String distStr = minDistance < 1000
            ? "${minDistance.toInt()}m"
            : "${(minDistance / 1000).toStringAsFixed(1)}km";
        ToastService.showInfo(context,
            "Not near any station (Closest: ${closestStation.name} is $distStr away)");
        _animatedMapMove(
            getLatLngFromSvg(closestStation.x, closestStation.y), 3.5);
        if (!mounted) return;
        setState(() => _isZoomedToLocation = true);
      }
    }
  }

  List<Polyline> _buildRoutePolylines(
      RouteResult route, List<MapStation> mapStations) {
    List<Polyline> glowLines = [];
    List<Polyline> glassOuter = [];
    List<Polyline> glassCore = [];
    List<LatLng> currentPoints = [];
    Color? currentColor;

    int startIndex = widget.activeStationIndex ?? 0;
    startIndex = startIndex.clamp(0, route.path.length - 1);

    for (int i = startIndex; i < route.path.length; i++) {
      final rs = route.path[i];
      MapStation? ms;
      try {
        ms = mapStations
            .firstWhere((s) => s.name.toLowerCase() == rs.name.toLowerCase());
      } catch (e) {
        debugPrint('Error: $e');
      }
      if (ms == null) continue;

      final pt = getLatLngFromSvg(ms.x, ms.y);

      if (currentColor == null) {
        currentColor = rs.lineColor;
        currentPoints.add(pt);
      } else if (currentColor == rs.lineColor) {
        currentPoints.add(pt);
      } else {
        currentPoints.add(pt);
        if (currentPoints.length > 1) {
          glowLines.add(Polyline(
              points: List.from(currentPoints),
              color: currentColor.withValues(alpha: 0.4),
              strokeWidth: 16.0,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round));
          glassOuter.add(Polyline(
              points: List.from(currentPoints),
              color: currentColor.withValues(alpha: 0.95),
              strokeWidth: 7.0,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round));
          glassCore.add(Polyline(
              points: List.from(currentPoints),
              color: Colors.white.withValues(alpha: 0.8),
              strokeWidth: 2.0,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round));
        }
        currentColor = rs.lineColor;
        currentPoints = [pt];
      }

      if (i == route.path.length - 1 && currentPoints.length > 1) {
        glowLines.add(Polyline(
            points: List.from(currentPoints),
            color: currentColor.withValues(alpha: 0.4),
            strokeWidth: 16.0,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round));
        glassOuter.add(Polyline(
            points: List.from(currentPoints),
            color: currentColor.withValues(alpha: 0.95),
            strokeWidth: 7.0,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round));
        glassCore.add(Polyline(
            points: List.from(currentPoints),
            color: Colors.white.withValues(alpha: 0.8),
            strokeWidth: 2.0,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round));
      }
    }
    return [...glowLines, ...glassOuter, ...glassCore];
  }

  void _onMapTapped(
      TapPosition tapPosition, LatLng latlng, List<MapStation> stations) {
    if (widget.activeRoute != null) return;

    final double tapX = (latlng.longitude * tileCanvasSize) - tweakX;
    final double tapY = (-latlng.latitude * tileCanvasSize) - tweakY;
    final tapPos = Offset(tapX, tapY);

    MapStation? clickedStation;
    double closestDist = 9999.0;
    const double dotHitRadius = 100.0;

    for (var station in stations) {
      for (var dot in station.allDots) {
        final distToDot = (dot - tapPos).distance;
        if (distToDot < dotHitRadius && distToDot < closestDist) {
          closestDist = distToDot;
          clickedStation = station;
        }
      }

      final textPainter = TextPainter(
        text: TextSpan(
            text: station.name,
            style:
                const TextStyle(fontSize: 45.0, fontWeight: FontWeight.bold)),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      final Rect textHitBox = Rect.fromLTWH(
          station.textX,
          station.textY - (textPainter.height * 0.8),
          textPainter.width,
          textPainter.height * 2.5);

      if (textHitBox.contains(tapPos)) {
        final distToTextCenter =
            (Offset(textHitBox.center.dx, textHitBox.center.dy) - tapPos)
                .distance;
        if (distToTextCenter < closestDist) {
          closestDist = distToTextCenter;
          clickedStation = station;
        }
      }
    }

    if (clickedStation != null) {
      AppHaptics.selectionClick();
      setState(() {
        _isFullScreenUI = false;
        if (fromStation == null) {
          fromStation = clickedStation;
        } else if (toStation == null && clickedStation!.id != fromStation?.id) {
          toStation = clickedStation;
        } else {
          fromStation = clickedStation;
          toStation = null;
        }
        _updateControllers();
      });
    }
  }

  void _swapStations() {
    if (fromStation != null || toStation != null) {
      AppHaptics.lightImpact();
      setState(() {
        final temp = fromStation;
        fromStation = toStation;
        toStation = temp;
        _updateControllers();
      });
    }
  }

  void _handleFindRoute() async {
    if (fromStation != null && toStation != null) {
      AppHaptics.heavyImpact();
      ToastService.showSuccess(context, "Finding best route...");
      try {
        final result = await MetroService()
            .findBestRoute(fromStation!.name, toStation!.name);

        if (!mounted) return;

        if (result != null && result.path.isNotEmpty) {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => RouteResultScreen(
                      fromStation: fromStation!.name,
                      toStation: toStation!.name,
                      routeData: result)));
        } else {
          ToastService.showError(context, "No route found.");
        }
      } catch (e) {
        if (!mounted) return;
        ToastService.showError(context, "Error finding route.");
      }
    }
  }


  // 🚀 UPDATED: Premium Diagonal Shine Map Button
  Widget _buildGlassMapButton({
    required IconData icon,
    required VoidCallback onTapDown,
    VoidCallback? onTapUp,
  }) {
    return GestureDetector(
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapUp?.call(),
      onTapCancel: () => onTapUp?.call(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              spreadRadius: -2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          clipBehavior: Clip.antiAlias,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: CustomPaint(
              // 🌟 THE MAGIC: Diagonal Border Shine (Circular)
              painter: _DiagonalBorderPainter(
                radius: 100,
                strokeGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.45),
                    Colors.white.withValues(alpha: 0.05),
                    Colors.white.withValues(alpha: 0.20),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.16), // Top Shine
                      Colors.white.withValues(alpha: 0.08), // Base
                      Colors.white.withValues(alpha: 0.04), // Bottom Depth
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(icon, color: const Color(0xFF00E5FF), size: 24),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    double overlayOpacity = widget.activeRoute != null
        ? 0.0
        : (widget.highlightedLineIds.isNotEmpty ? 0.8 : 0.0);

    double fabBottomPadding = 40.0;
    if (isDesktop) {
      fabBottomPadding = 40.0;
    } else if (_isFullScreenUI || widget.activeRoute != null) {
      fabBottomPadding = 40.0;
    } else if (fromStation != null || toStation != null) {
      fabBottomPadding =
          (fromStation != null && toStation != null) ? 260.0 : 190.0;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E17),
      extendBodyBehindAppBar: true,
      appBar: (widget.activeRoute != null || isDesktop || !widget.showAppBar)
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              leading: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E).withValues(alpha: 0.8),
                      shape: BoxShape.circle),
                  child: IconButton(
                      icon: const Padding(
                          padding: EdgeInsets.only(right: 2.0),
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white, size: 18)),
                      onPressed: () => Navigator.pop(context)),
                ),
              ),
              title: AnimatedOpacity(
                  opacity: _isFullScreenUI ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: const Text("Network Map",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold))),
              actions: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Container(
                    decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E).withValues(alpha: 0.8),
                        shape: BoxShape.circle),
                    child: IconButton(
                        icon: Icon(
                            _isFullScreenUI
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            color: Colors.white,
                            size: 22),
                        onPressed: () {
                          AppHaptics.selectionClick();
                          setState(() => _isFullScreenUI = !_isFullScreenUI);
                        }),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
      body: SizedBox.expand(
        child: Consumer<MetroDataProvider>(
          builder: (context, provider, child) {
            if (provider.mapData == null) {
              return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
            }

            Marker? activeLocMarker;
            Marker? activeDestMarker;

            if (widget.activeRoute != null &&
                widget.activeRoute!.path.isNotEmpty) {
              final stations = provider.mapData!.stations;
              int sIdx = widget.activeStationIndex ?? 0;
              sIdx = sIdx.clamp(0, widget.activeRoute!.path.length - 1);
              var startRs = widget.activeRoute!.path[sIdx];
              MapStation? startMs;
              try {
                startMs = stations.firstWhere(
                    (s) => s.name.toLowerCase() == startRs.name.toLowerCase());
              } catch (e) {
                debugPrint('Error: $e');
              }

              if (startMs != null) {
                activeLocMarker = Marker(
                    point: getLatLngFromSvg(startMs.x, startMs.y),
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    child: const PulsingMarker(color: Color(0xFF00E5FF)));
              }

              var endRs = widget.activeRoute!.path.last;
              MapStation? endMs;
              try {
                endMs = stations.firstWhere(
                    (s) => s.name.toLowerCase() == endRs.name.toLowerCase());
              } catch (e) {
                debugPrint('Error: $e');
              }

              if (endMs != null) {
                activeDestMarker = Marker(
                    point: getLatLngFromSvg(endMs.x, endMs.y),
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    child: const PulsingMarker(color: Color(0xFFFF3B30)));
              }
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      backgroundColor: const Color(0xFF0B0E17),
                      crs: const CrsSimple(),
                      initialCenter: getLatLngFromSvg(7700, 7000),
                      initialZoom: 3.0,
                      minZoom: 2.0,
                      maxZoom: 6.0,
                      // Fine-tuned boundaries to simulate tighter boundaryMargin (top: 120, bottom: 150, left/right: 60)
                      // Prevents massive black voids while sitting perfectly under AppBar and above FAB.
                      cameraConstraint: CameraConstraint.contain(
                          bounds: LatLngBounds(
                              const LatLng(-1.15, -0.08), // Bottom-Left (snug south/west padding)
                              const LatLng(0.12, 1.08))), // Top-Right (snug north/east padding)
                      interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                      onTap: (tapPosition, latlng) => _onMapTapped(
                          tapPosition, latlng, provider.mapData!.stations),
                      onMapReady: () {
                        setState(() {
                          _isMapReady = true;
                        });
                        if (widget.activeRoute != null) {
                          final stations = provider.mapData!.stations;
                          List<LatLng> boundsPoints = [];
                          for (var rs in widget.activeRoute!.path) {
                            try {
                              var ms = stations.firstWhere((s) =>
                                  s.name.toLowerCase() ==
                                  rs.name.toLowerCase());
                              boundsPoints.add(getLatLngFromSvg(ms.x, ms.y));
                            } catch (e) {
                              debugPrint('Error: $e');
                            }
                          }
                          if (boundsPoints.isNotEmpty) {
                            final bounds =
                                LatLngBounds.fromPoints(boundsPoints);
                            Future.delayed(const Duration(milliseconds: 200),
                                () {
                              _mapController.fitCamera(CameraFit.bounds(
                                  bounds: bounds,
                                  padding: const EdgeInsets.all(80)));
                            });
                          }
                        } else {
                          _centerOnNewDelhi();
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                          tileProvider: LocalDbTileProvider(),
                          maxNativeZoom: 6),
                      IgnorePointer(
                          child: AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              color: Colors.black
                                  .withValues(alpha: overlayOpacity))),
                      if (widget.activeRoute == null)
                        Builder(
                          builder: (BuildContext mapContext) {
                            return IgnorePointer(
                              child: SizedBox.expand(
                                child: CustomPaint(
                                  painter: MultiDotIllusionPainter(
                                    allLines: provider.mapData!.lines,
                                    allStations: provider.mapData!.stations,
                                    activeLineIds: widget.highlightedLineIds,
                                    camera: MapCamera.of(mapContext),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      if (widget.activeRoute != null)
                        PolylineLayer(
                            polylines: _buildRoutePolylines(widget.activeRoute!,
                                provider.mapData!.stations)),
                      MarkerLayer(markers: [
                        if (widget.activeRoute == null && fromStation != null)
                          Marker(
                              point: getLatLngFromSvg(
                                  fromStation!.x, fromStation!.y),
                              width: 60,
                              height: 60,
                              alignment: Alignment.center,
                              child: const PulsingMarker(
                                  color: Color(0xFF00E5FF))),
                        if (widget.activeRoute == null && toStation != null)
                          Marker(
                              point:
                                  getLatLngFromSvg(toStation!.x, toStation!.y),
                              width: 60,
                              height: 60,
                              alignment: Alignment.center,
                              child: const PulsingMarker(
                                  color: Color(0xFFFF3B30))),
                        if (activeLocMarker != null) activeLocMarker,
                        if (activeDestMarker != null) activeDestMarker,
                      ])
                    ],
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  bottom: fabBottomPadding,
                  right: 20,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isDesktop) ...[
                        _buildGlassMapButton(
                            icon: Icons.add_rounded,
                            onTapDown: () => _startZoom(0.6),
                            onTapUp: _stopZoom),
                        const SizedBox(height: 12),
                        _buildGlassMapButton(
                            icon: Icons.remove_rounded,
                            onTapDown: () => _startZoom(-0.6),
                            onTapUp: _stopZoom),
                        const SizedBox(height: 12),
                      ],
                      _buildGlassMapButton(
                          icon: _isZoomedToLocation
                              ? Icons.zoom_out_map_rounded
                              : Icons.my_location,
                          onTapDown: () {
                            AppHaptics.selectionClick();
                            if (_isZoomedToLocation) {
                              _zoomToFit();
                            } else {
                              _locateNearestStation();
                            }
                          }),
                    ],
                  ),
                ),
                if (widget.activeRoute == null && !isDesktop)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOutBack,
                    bottom: _isFullScreenUI ? -300 : 30,
                    left: 20,
                    right: 20,
                    child: (fromStation == null && toStation == null)
                        ? const SizedBox()
                        : CommuteSearchCard(
                            isDark: true,
                            selectedMode: 0,
                            fromController: fromCtrl,
                            toController: toCtrl,
                            fromFocus: fromFocus,
                            toFocus: toFocus,
                            onSwapTap: _swapStations,
                            onSubmit: _handleFindRoute,
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class PulsingMarker extends StatefulWidget {
  final Color color;
  const PulsingMarker({super.key, required this.color});

  @override
  State<PulsingMarker> createState() => _PulsingMarkerState();
}

class _PulsingMarkerState extends State<PulsingMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                  width: 60 * _controller.value,
                  height: 60 * _controller.value,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color
                          .withValues(alpha: (1 - _controller.value) * 0.4),
                      border: Border.all(
                          color: widget.color
                              .withValues(alpha: (1 - _controller.value) * 0.8),
                          width: 1.5))),
              Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: widget.color, width: 3.5),
                      boxShadow: [
                        BoxShadow(
                            color: widget.color.withValues(alpha: 0.6),
                            blurRadius: 10)
                      ])),
            ],
          );
        });
  }
}

class MultiDotIllusionPainter extends CustomPainter {
  final List<MapLine> allLines;
  final List<MapStation> allStations;
  final List<String> activeLineIds;
  final MapCamera? camera;

  MultiDotIllusionPainter({
    required this.allLines,
    required this.allStations,
    this.activeLineIds = const [],
    this.camera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (camera == null) return;
    canvas.save();

    final pos = camera!.getOffsetFromOrigin(const LatLng(0, 0));
    final double mapSize = 256.0 * math.pow(2, camera!.zoom);
    final double scale = mapSize / tileCanvasSize;

    canvas.translate(pos.dx + (tweakX * scale), pos.dy + (tweakY * scale));
    canvas.scale(scale, scale);

    final linesToDraw = activeLineIds.isEmpty
        ? allLines
        : allLines.where((l) => activeLineIds.contains(l.lineId)).toList();

    for (var line in linesToDraw) {
      try {
        final ui.Path path = parseSvgPathData(line.pathD);
        final glowPaint = Paint()
          ..color = line.color.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 25.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 12.0);
        final corePaint = Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(path, glowPaint);
        canvas.drawPath(path, corePaint);
      } catch (e) {
        debugPrint('Error: $e');
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MultiDotIllusionPainter oldDelegate) => true;
}

class LocalDbTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return DbTileImageProvider(
        coordinates.z.toInt(), coordinates.y.toInt(), coordinates.x.toInt());
  }
}

class DbTileImageProvider extends ImageProvider<DbTileImageProvider> {
  final int z, folder, file;
  DbTileImageProvider(this.z, this.folder, this.file);

  @override
  Future<DbTileImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<DbTileImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
      DbTileImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
        codec: _loadAsync(key, decode), scale: 1.0);
  }

  Future<ui.Codec> _loadAsync(
      DbTileImageProvider key, ImageDecoderCallback decode) async {
    try {
      Uint8List? bytes =
          await DatabaseHelper.instance.getMapTile(key.z, key.folder, key.file);

      if (bytes == null || bytes.isEmpty) {
        bytes = await DatabaseHelper.instance.getMapTile(-1, -1, -1);
      }
      if (bytes != null && bytes.isNotEmpty) {
        return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      }
    } catch (e) {
      debugPrint('Tile Load Error: $e');
    }

    final empty = Uint8List.fromList([
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
    return decode(await ui.ImmutableBuffer.fromUint8List(empty));
  }
}

// 🌟 Custom Painter for the sexy diagonal circular shine in Map Buttons
class _DiagonalBorderPainter extends CustomPainter {
  final double radius;
  final Gradient strokeGradient;
  _DiagonalBorderPainter({required this.radius, required this.strokeGradient});

  @override
  void paint(Canvas canvas, ui.Size size) {
    final ui.Rect rect = ui.Offset.zero & size;
    final ui.Paint paint = ui.Paint()
      ..strokeWidth = 1.2
      ..style = ui.PaintingStyle.stroke
      ..shader = strokeGradient.createShader(rect);
    final ui.RRect rrect =
        ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(radius));
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _DiagonalBorderPainter oldDelegate) => false;
}
