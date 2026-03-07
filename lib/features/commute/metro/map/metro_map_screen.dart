import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:path_drawing/path_drawing.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import 'package:ridel/features/commute/shared/services/database_helper.dart'; 
import 'package:ridel/features/commute/metro/map/metro_data_provider.dart';
import 'package:ridel/features/commute/metro/map/map_models.dart';

const double MAP_BASE_SIZE = 11000.0; 
const double TWEAK_X = 0.0; 
const double TWEAK_Y = 0.0; 

// =========================================================================
// 🛡️ THE BULLETPROOF TILE PROVIDER
// =========================================================================
class DatabaseTileProvider extends TileProvider {
  final Uint8List _transparentPixel = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _DatabaseImageProvider(coordinates, options, _transparentPixel);
  }
}

class _DatabaseImageProvider extends ImageProvider<_DatabaseImageProvider> {
  final TileCoordinates coordinates;
  final TileLayer options;
  final Uint8List fallbackPixel;

  _DatabaseImageProvider(this.coordinates, this.options, this.fallbackPixel);

  @override
  Future<_DatabaseImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture<_DatabaseImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(_DatabaseImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode), scale: 1.0, informationCollector: () => [DiagnosticsProperty('TileCoordinates', coordinates)],
    );
  }

  Future<ui.Codec> _loadAsync(_DatabaseImageProvider key, ImageDecoderCallback decode) async {
    final int z = coordinates.z; final int x = coordinates.x; final int y = coordinates.y;

    if (z < 0) return decode(await ui.ImmutableBuffer.fromUint8List(fallbackPixel));
    final int maxTile = (1 << z) - 1; 
    if (x < 0 || x > maxTile || y < 0 || y > maxTile) return decode(await ui.ImmutableBuffer.fromUint8List(fallbackPixel));

    try {
      final cachedBytes = await DatabaseHelper().getCachedTile(z, x, y);
      if (cachedBytes != null && cachedBytes.isNotEmpty) return decode(await ui.ImmutableBuffer.fromUint8List(cachedBytes));

      final url = options.urlTemplate!.replaceAll('{z}', z.toString()).replaceAll('{x}', x.toString()).replaceAll('{y}', y.toString());
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        await DatabaseHelper().saveTileToCache(z, x, y, bytes);
        return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      }
    } catch (e) {}

    return decode(await ui.ImmutableBuffer.fromUint8List(fallbackPixel));
  }
}

// =========================================================================
// 🗺️ MAIN METRO MAP SCREEN
// =========================================================================
class MetroMapScreen extends StatefulWidget {
  final List<String> highlightedLineIds;
  const MetroMapScreen({super.key, this.highlightedLineIds = const []});

  @override
  State<MetroMapScreen> createState() => _MetroMapScreenState();
}

class _MetroMapScreenState extends State<MetroMapScreen> {
  final MapController _mapController = MapController();
  MapStation? fromStation;
  MapStation? toStation;
  List<MapStation> currentRoute = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MetroDataProvider>(context, listen: false).fetchMapData();
    });
  }

  void _onMapTapped(TapPosition tapPosition, LatLng latlng, List<MapStation> stations) {
    final camera = _mapController.camera;
    final topLeftScreen = camera.getOffsetFromOrigin(const LatLng(0, 0));
    final tapPixel = camera.getOffsetFromOrigin(latlng);
    
    final double mapSize = 256.0 * math.pow(2, camera.zoom);
    final double scale = MAP_BASE_SIZE / mapSize; 
    
    final double tapX = ((tapPixel.dx - topLeftScreen.dx) * scale) - TWEAK_X;
    final double tapY = ((tapPixel.dy - topLeftScreen.dy) * scale) - TWEAK_Y;
    final tapPos = Offset(tapX, tapY);

    MapStation? clickedStation;
    double minDistance = 120.0; 
    double closestDist = 9999.0;

    for (var station in stations) {
      // 🔥 MULTI-DOT TAP MAGIC: Ek station ke har dot ki distance check karo!
      for (var dot in station.allDots) {
        final distToDot = (dot - tapPos).distance;
        if (distToDot < minDistance && distToDot < closestDist) {
          closestDist = distToDot;
          clickedStation = station; // Koi bhi dot pakdo, station wahi select hoga
        }
      }
    }

    if (clickedStation != null) _showRoutingBottomSheet(clickedStation);
  }

  void _calculateRoute() {
    if (fromStation != null && toStation != null) {
      setState(() { currentRoute = [fromStation!, toStation!]; });
    }
  }

  void _showRoutingBottomSheet(MapStation station) {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(station.name.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent), onPressed: () { setState(() => fromStation = station); Navigator.pop(context); _calculateRoute(); }, icon: const Icon(Icons.trip_origin, color: Colors.white), label: const Text("FROM", style: TextStyle(color: Colors.white))),
                  ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () { setState(() => toStation = station); Navigator.pop(context); _calculateRoute(); }, icon: const Icon(Icons.location_on, color: Colors.white), label: const Text("TO", style: TextStyle(color: Colors.white))),
                ],
              ),
              if (fromStation != null || toStation != null) ...[
                const SizedBox(height: 15),
                TextButton(onPressed: () { setState(() { fromStation = null; toStation = null; currentRoute = []; }); Navigator.pop(context); }, child: const Text("Clear Route", style: TextStyle(color: Colors.red)))
              ]
            ],
          ),
        );
      },
    );
  }

  void _centerMap() => _mapController.move(const LatLng(-0.5, 0.5), 1.5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E17), 
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, centerTitle: true, iconTheme: const IconThemeData(color: Colors.white), title: const Text("11K Network Map", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      floatingActionButton: FloatingActionButton(onPressed: _centerMap, backgroundColor: const Color(0xFF00E5FF), child: const Icon(Icons.my_location, color: Colors.black)),
      
      body: SizedBox.expand(
        child: Consumer<MetroDataProvider>(
          builder: (context, provider, child) {
            if (provider.mapData == null) return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));

            return Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      backgroundColor: const Color(0xFF0B0E17), crs: const CrsSimple(), 
                      initialCenter: const LatLng(-0.5, 0.5), initialZoom: 1.5, minZoom: 0.0, maxZoom: 6.0,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                      onTap: (tapPosition, latlng) => _onMapTapped(tapPosition, latlng, provider.mapData!.stations),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://oysalcuewxfxbgeiqcpr.supabase.co/storage/v1/object/public/city_packages/map_tiles_hd/{z}/{x}/{y}.jpg',
                        userAgentPackageName: 'com.ridel', tileProvider: DatabaseTileProvider(), 
                      ),
                      Builder(
                        builder: (BuildContext mapContext) {
                          final camera = MapCamera.of(mapContext);
                          return IgnorePointer(
                            child: SizedBox.expand(
                              child: CustomPaint(
                                painter: MultiDotIllusionPainter(
                                  allLines: provider.mapData!.lines,
                                  allStations: provider.mapData!.stations,
                                  activeLineIds: widget.highlightedLineIds,
                                  routeStations: currentRoute, camera: camera, 
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                
                if (fromStation != null || toStation != null)
                  Positioned(
                    top: 10, left: 15, right: 15,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withOpacity(0.95), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("FROM", style: TextStyle(color: Colors.white54, fontSize: 10)), Text(fromStation?.name ?? "...", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1)])),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.arrow_forward_rounded, color: Colors.white54, size: 24)),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [const Text("TO", style: TextStyle(color: Colors.white54, fontSize: 10)), Text(toStation?.name ?? "...", textAlign: TextAlign.right, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1)])),
                        ],
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

// =========================================================================
// 🎨 MULTI-DOT ILLUSION PAINTER (100% Native Coordinates)
// =========================================================================
class MultiDotIllusionPainter extends CustomPainter {
  final List<MapLine> allLines;
  final List<MapStation> allStations; 
  final List<String> activeLineIds; 
  final List<MapStation> routeStations; 
  final MapCamera? camera; 

  MultiDotIllusionPainter({
    required this.allLines, required this.allStations, this.activeLineIds = const [], this.routeStations = const [], this.camera, 
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (camera == null) return;
    canvas.save(); 

    final pos = camera!.getOffsetFromOrigin(const LatLng(0, 0));
    final double mapSize = 256.0 * math.pow(2, camera!.zoom);
    final double scale = mapSize / MAP_BASE_SIZE; 
    
    canvas.translate(pos.dx + (TWEAK_X * scale), pos.dy + (TWEAK_Y * scale));
    canvas.scale(scale, scale);

    // 1️⃣ DRAW LINES
    for (var line in allLines) {
      bool isActive = activeLineIds.isEmpty || activeLineIds.contains(line.lineId);
      if (isActive) {
        try {
          final ui.Path path = parseSvgPathData(line.pathD);
          final corePaint = Paint()..color = line.color..style = PaintingStyle.stroke..strokeWidth = 15.0..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
          canvas.drawPath(path, corePaint);
        } catch (e) { }
      }
    }

    // 2️⃣ DRAW ALL DOTS FOR EVERY STATION (For testing alignment)
    final stationDotPaint = Paint()..color = Colors.yellowAccent..style = PaintingStyle.fill; 

    for (var station in allStations) {
      // 🔥 Ek station ke paas jitne dots hain, sabko render karo!
      for (var dot in station.allDots) {
        canvas.drawCircle(dot, 15.0, stationDotPaint);
      }
    }

    // 3️⃣ HIGHLIGHT SELECTED ROUTE PINS (If any dot of the station is part of the route, highlight it)
    if (routeStations.isNotEmpty) {
      final double radius = 30.0; 
      final centerPaint = Paint()..color = Colors.white;
      final shadowPaint = Paint()..color = Colors.black.withOpacity(0.8)..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8.0);

      for (var station in routeStations) {
        for (var dot in station.allDots) {
          canvas.drawCircle(dot, radius * 1.5, shadowPaint);
          canvas.drawCircle(dot, radius, centerPaint);
        }
      }
    }
    
    canvas.restore(); 
  }

  @override
  bool shouldRepaint(covariant MultiDotIllusionPainter oldDelegate) => true;
}