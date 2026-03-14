import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:path_drawing/path_drawing.dart';
import 'package:provider/provider.dart';

import 'package:ridel/features/commute/shared/services/database_helper.dart'; 
import 'package:ridel/features/commute/metro/map/metro_data_provider.dart';
import 'package:ridel/features/commute/metro/map/map_models.dart';
import 'package:ridel/core/services/global_location_service.dart';

const double TILE_CANVAS_SIZE = 16384.0; 
const double TWEAK_X = 0.0; 
const double TWEAK_Y = 0.0; 

class SmartWebTileProvider extends TileProvider {
  final bool isTMS = false;       
  final bool isXYSwapped = true;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final int z = coordinates.z.toInt();
    int x = coordinates.x.toInt();
    int y = coordinates.y.toInt();

    if (z < 0 || x < 0 || y < 0 || z > 6) {
      return const NetworkImage('https://oysalcuewxfxbgeiqcpr.supabase.co/storage/v1/object/public/city_packages/delhi/map_tiles/blank.png');
    }
    
    final int maxTile = (1 << z) - 1; 
    if (x > maxTile || y > maxTile) {
      return const NetworkImage('https://oysalcuewxfxbgeiqcpr.supabase.co/storage/v1/object/public/city_packages/delhi/map_tiles/blank.png');
    }

    int finalX = x;
    int finalY = y;

    if (isTMS) finalY = maxTile - y; 
    if (isXYSwapped) {
      int temp = finalX;
      finalX = finalY;
      finalY = temp;
    }

    final url = options.urlTemplate!
        .replaceAll('{z}', z.toString())
        .replaceAll('{x}', finalX.toString())
        .replaceAll('{y}', finalY.toString());

    return NetworkImage(url);
  }
}

class MetroMapScreen extends StatefulWidget {
  final List<String> highlightedLineIds;
  const MetroMapScreen({super.key, this.highlightedLineIds = const []});

  @override
  State<MetroMapScreen> createState() => _MetroMapScreenState();
}

class _MetroMapScreenState extends State<MetroMapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  MapStation? fromStation;
  MapStation? toStation;
  List<MapStation> currentRoute = [];
  bool _isMapCentered = false;
  bool _isMapReady = false;
  bool _isZoomedToLocation = false;
  
  // 🚀 NAYA: Animation ko control karne ke liye
  AnimationController? _animController; 

  LatLng getLatLngFromSvg(double x, double y) {
    return LatLng(-(y / TILE_CANVAS_SIZE), (x / TILE_CANVAS_SIZE));
  }

  @override
  void dispose() {
    _animController?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _centerOnNewDelhi() {
    if (!_isMapReady || _isMapCentered) return;
    try {
      // 🚀 INITIAL ZOOM LEVEL: Set to 1.2 so it doesn't look too tiny
      _mapController.move(getLatLngFromSvg(7700, 7000), 1.2); 
      _isMapCentered = true;
    } catch (e) {
      debugPrint("Map Center Initialization Blocked: $e");
    }
  }

  void _zoomToFit() {
    _animatedMapMove(getLatLngFromSvg(7700, 7000), 1.2); 
    setState(() {
      _isZoomedToLocation = false; 
    });
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    // 🚀 Purani ruki hui animation ko pehle clear karo
    _animController?.stop();
    _animController?.dispose();

    // Nayi fresh animation start karo
    _animController = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    final Animation<double> animation = CurvedAnimation(parent: _animController!, curve: Curves.fastOutSlowIn);

    final latTween = Tween<double>(begin: _mapController.camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(begin: _mapController.camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: _mapController.camera.zoom, end: destZoom);

    _animController!.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation)
      );
    });

    _animController!.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        _animController!.dispose();
        _animController = null;
      }
    });

    _animController!.forward();
  }

  void _locateNearestStation() async {
    final locationService = Provider.of<GlobalLocationService>(context, listen: false);
    final position = locationService.currentPosition;

    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fetching GPS... Please try again.")));
      return;
    }

    final provider = Provider.of<MetroDataProvider>(context, listen: false);
    final stations = provider.mapData?.stations ?? [];

    if (stations.isEmpty) return;

    MapStation? closestStation;
    double minDistance = double.infinity;
    const distanceCalc = Distance(); // 🚀 Latlong2 package se distance calculator

    // 🚀 DART-NATIVE GPS LOGIC: Zero errors, guaranteed exact match!
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
      setState(() {
        fromStation = closestStation;
        toStation = null;
        currentRoute = [closestStation!];
        _isZoomedToLocation = true; 
      });

      _animatedMapMove(getLatLngFromSvg(closestStation.x, closestStation.y), 3.5); 
    } else {
      debugPrint("Nearest station geometry not found in memory!");
    }
  }

  void _onMapTapped(TapPosition tapPosition, LatLng latlng, List<MapStation> stations) {
    final double tapX = (latlng.longitude * TILE_CANVAS_SIZE) - TWEAK_X;
    final double tapY = (-latlng.latitude * TILE_CANVAS_SIZE) - TWEAK_Y;
    final tapPos = Offset(tapX, tapY);

    MapStation? clickedStation;
    double closestDist = 9999.0;
    
    final double dotHitRadius = 100.0;

    for (var station in stations) {
      for (var dot in station.allDots) {
        final distToDot = (dot - tapPos).distance;
        if (distToDot < dotHitRadius && distToDot < closestDist) {
          closestDist = distToDot;
          clickedStation = station;
        }
      }

      final textPainter = TextPainter(
        text: TextSpan(text: station.name, style: const TextStyle(fontSize: 45.0, fontWeight: FontWeight.bold)),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      final Rect textHitBox = Rect.fromLTWH(
        station.textX, 
        station.textY - (textPainter.height * 0.8), 
        textPainter.width, 
        textPainter.height * 2.5 
      );

      if (textHitBox.contains(tapPos)) {
        final distToTextCenter = (Offset(textHitBox.center.dx, textHitBox.center.dy) - tapPos).distance;
        if (distToTextCenter < closestDist) {
          closestDist = distToTextCenter;
          clickedStation = station;
        }
      }
    }

    if (clickedStation != null) {
      setState(() {
        if (fromStation == null) {
          fromStation = clickedStation;
          currentRoute = [clickedStation!];
        } else if (toStation == null && clickedStation!.id != fromStation!.id) {
          toStation = clickedStation;
          currentRoute = [fromStation!, toStation!];
        } else {
          fromStation = clickedStation;
          toStation = null;
          currentRoute = [clickedStation!];
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine overlay opacity based on route selection
    double overlayOpacity = 0.0;
    if (widget.highlightedLineIds.isNotEmpty) {
      overlayOpacity = 0.8; // Deep dark blur for active route
    } else if (fromStation != null) {
      overlayOpacity = 0.4; // Mild dim focus on single tap
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E17), 
      extendBodyBehindAppBar: true, 

      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0,
        centerTitle: true,
        
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withOpacity(0.8), shape: BoxShape.circle),
            child: IconButton(
              icon: const Padding(padding: EdgeInsets.only(right: 2.0), child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18)),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),

        title: const Text("Network Map", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withOpacity(0.8), shape: BoxShape.circle),
              child: IconButton(
                icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 22),
                tooltip: "Zoom to Fit",
                onPressed: _zoomToFit,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],

        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0), 
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [const Color(0xFF0B0E17).withOpacity(0.9), const Color(0xFF0B0E17).withOpacity(0.5), const Color(0xFF0B0E17).withOpacity(0.0)],
                ),
              ),
            ),
          ),
        ),
      ),
      body: SizedBox.expand(
        child: Consumer<MetroDataProvider>(
          builder: (context, provider, child) {
            if (provider.mapData == null) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
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
                      
                      initialZoom: 1.2, 
                      minZoom: 1.0,
                      maxZoom: 6.0, 
                      // 🚀 BOUNDS KO THODA BADA KIYA TAAKI ZOOM BLOCK NA HO
                      cameraConstraint: CameraConstraint.contain(
                        bounds: LatLngBounds(
                          const LatLng(-1.5, -0.5), // Extra South-West padding
                          const LatLng(0.5, 1.5),   // Extra North-East padding
                        ),
                      ),
                      
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                      onTap: (tapPosition, latlng) => _onMapTapped(tapPosition, latlng, provider.mapData!.stations),
                      onMapReady: () {
                        setState(() { _isMapReady = true; });
                        _centerOnNewDelhi(); 
                      },
                    ),
                    children: [
                      // VISUAL LAYER: Map Tiles 
                      TileLayer(
                        urlTemplate: 'https://oysalcuewxfxbgeiqcpr.supabase.co/storage/v1/object/public/city_packages/delhi/map_tiles/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.ridel',
                        tileProvider: SmartWebTileProvider(),
                      ),
                      
                      // 🚀 CINEMATIC MAP DIM OVERLAY (Active hone par dark ho jayega)
                      IgnorePointer(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          color: Colors.black.withOpacity(overlayOpacity),
                        ),
                      ),

                      // INVISIBLE LOGIC & NEON HIGHLIGHT LAYER
                      Builder(
                        builder: (BuildContext mapContext) {
                          return IgnorePointer(
                            child: SizedBox.expand(
                              child: CustomPaint(
                                painter: MultiDotIllusionPainter(
                                  allLines: provider.mapData!.lines,
                                  allStations: provider.mapData!.stations,
                                  activeLineIds: widget.highlightedLineIds,
                                  routeStations: currentRoute, 
                                  camera: MapCamera.of(mapContext), 
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                Positioned(
                  bottom: (fromStation != null) ? 140 : 40,
                  right: 20,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                      child: InkWell(
                        onTap: _isZoomedToLocation ? _zoomToFit : _locateNearestStation,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.15))),
                          child: Center(
                            child: Icon(_isZoomedToLocation ? Icons.zoom_out_map_rounded : Icons.my_location, color: const Color(0xFF00E5FF), size: 26),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                if (fromStation != null)
                  Positioned(
                    bottom: 30, left: 15, right: 15,
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 500),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withOpacity(0.95), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)]),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("FROM", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)), Text(fromStation!.name, style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis)])),
                                const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.arrow_forward_rounded, color: Colors.white54, size: 24)),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [const Text("TO", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)), Text(toStation?.name ?? "Tap map to select...", textAlign: TextAlign.right, style: TextStyle(color: toStation == null ? Colors.white38 : const Color(0xFFFF3B30), fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)])),
                                IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => setState(() { fromStation = null; toStation = null; currentRoute = []; })),
                              ],
                            ),
                            if (fromStation != null && toStation != null) ...[
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                                  onPressed: () {
                                    debugPrint("Navigating to Route: ${fromStation!.name} -> ${toStation!.name}");
                                  }, 
                                  child: const Text("GO", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2))
                                ),
                              )
                            ]
                          ],
                        ),
                      ),
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

class MultiDotIllusionPainter extends CustomPainter {
  final List<MapLine> allLines;
  final List<MapStation> allStations; 
  final List<String> activeLineIds; 
  final List<MapStation> routeStations; 
  final MapCamera? camera; 

  static final Paint _routeCenterPaint = Paint()..color = Colors.white;
  static final Paint _routeShadowPaint = Paint()..color = Colors.black.withOpacity(0.8)..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8.0);

  MultiDotIllusionPainter({
    required this.allLines, required this.allStations, this.activeLineIds = const [], this.routeStations = const [], this.camera, 
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (camera == null) return;
    canvas.save(); 

    final pos = camera!.getOffsetFromOrigin(const LatLng(0, 0));
    final double mapSize = 256.0 * math.pow(2, camera!.zoom);
    final double scale = mapSize / TILE_CANVAS_SIZE; 
    
    canvas.translate(pos.dx + (TWEAK_X * scale), pos.dy + (TWEAK_Y * scale));
    canvas.scale(scale, scale);

    // 🚀 NEON HIGHLIGHT DRAWING ENGINE
    if (activeLineIds.isNotEmpty) {
      for (var line in allLines) {
        if (activeLineIds.contains(line.lineId)) {
          try {
            final ui.Path path = parseSvgPathData(line.pathD);
            
            // Glowing Aura
            final glowPaint = Paint()
              ..color = line.color.withOpacity(0.8)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 25.0
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 12.0);

            // Bright Core
            final corePaint = Paint()
              ..color = line.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 8.0
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round;

            canvas.drawPath(path, glowPaint);
            canvas.drawPath(path, corePaint);
          } catch (e) { }
        }
      }
    }

    if (routeStations.isNotEmpty) {
      const double radius = 30.0; 
      for (var station in routeStations) {
        for (var dot in station.allDots) {
          canvas.drawCircle(dot, radius * 1.5, _routeShadowPaint);
          canvas.drawCircle(dot, radius, _routeCenterPaint);
        }
      }
    }
    
    canvas.restore(); 
  }

  @override
  bool shouldRepaint(covariant MultiDotIllusionPainter oldDelegate) => true; 
}