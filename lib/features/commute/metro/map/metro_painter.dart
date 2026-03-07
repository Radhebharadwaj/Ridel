import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math' as math; 
import 'package:path_drawing/path_drawing.dart';
import 'package:latlong2/latlong.dart' hide Path; 
import 'package:flutter_map/flutter_map.dart'; 
import 'package:ridel/features/commute/metro/map/map_models.dart';

class MetroMapPainter extends CustomPainter {
  final List<MapLine> allLines;
  final List<String> activeLineIds; 
  final List<MapStation> routeStations; 
  final MapCamera? camera; 

  MetroMapPainter({
    required this.allLines,
    this.activeLineIds = const [],
    this.routeStations = const [],
    this.camera, 
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save(); 

    if (camera != null) {
      final double mapSize = 256.0 * math.pow(2, camera!.zoom);
      final double scale = mapSize / 11000.0;
      final pos = camera!.getOffsetFromOrigin(const LatLng(0, 0));
      
      canvas.translate(pos.dx, pos.dy);
      canvas.scale(scale, scale);
    }

    for (var line in allLines) {
      // 🔥 ZERO-ERROR FIX: Agar koi route select nahi hai, to SAARI lines dikhao!
      bool isActive = activeLineIds.isEmpty || activeLineIds.contains(line.lineId);
      
      if (line.lineId == 'LN3' && activeLineIds.contains('LN4')) isActive = true;
      if (line.lineId == 'LN5' && activeLineIds.contains('LN14')) isActive = true;

      if (isActive) {
        final ui.Path path = parseSvgPathData(line.pathD);

        final glowPaint = Paint()
          ..color = line.color.withOpacity(0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 30.0 
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 15.0);
        
        final corePaint = Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 15.0 
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        canvas.drawPath(path, glowPaint);
        canvas.drawPath(path, corePaint);
      }
    }

    if (routeStations.isNotEmpty) {
      final double radius = 15.0; 
      final centerPaint = Paint()..color = Colors.white;

      for (var station in routeStations) {
        final center = Offset(station.x, station.y); 

        final shadowPaint = Paint()
          ..color = Colors.black.withOpacity(0.8)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8.0);
        
        canvas.drawCircle(center, radius * 1.5, shadowPaint);
        canvas.drawCircle(center, radius, centerPaint);
      }
    }
    
    canvas.restore(); 
  }

  @override
  bool shouldRepaint(covariant MetroMapPainter oldDelegate) {
    return oldDelegate.activeLineIds != activeLineIds ||
           oldDelegate.routeStations != routeStations ||
           oldDelegate.camera?.zoom != camera?.zoom ||
           oldDelegate.camera?.center != camera?.center;
  }
}