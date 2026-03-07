import 'dart:ui';
import 'dart:convert'; // 🔥 JSON decode karne ke liye zaroori hai

class MapStation {
  final String id;
  final String name;
  final double x;     
  final double y;     
  final double textX; 
  final double textY; 
  final double lat;   
  final double lng;   
  final List<Offset> allDots; // 🔥 NAYA: Har station ke saare dots isme aayenge

  MapStation({
    required this.id, 
    required this.name, 
    required this.x, 
    required this.y,
    required this.textX,
    required this.textY,
    required this.lat, 
    required this.lng,
    required this.allDots,
  });

  factory MapStation.fromMap(Map<String, dynamic> map) {
    List<Offset> parsedDots = [];
    
    // 🔥 JSON Parsing Logic (Agar JSON hai to list banao, warna normal x,y use karo)
    if (map['all_dots'] != null && map['all_dots'].toString().isNotEmpty) {
      try {
        var decoded = jsonDecode(map['all_dots']);
        for (var d in decoded) {
          parsedDots.add(Offset(d['x'].toDouble(), d['y'].toDouble()));
        }
      } catch (e) {
        parsedDots.add(Offset((map['x'] as num?)?.toDouble() ?? 0.0, (map['y'] as num?)?.toDouble() ?? 0.0));
      }
    } else {
      parsedDots.add(Offset((map['x'] as num?)?.toDouble() ?? 0.0, (map['y'] as num?)?.toDouble() ?? 0.0));
    }

    return MapStation(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unknown',
      x: (map['x'] as num?)?.toDouble() ?? 0.0,
      y: (map['y'] as num?)?.toDouble() ?? 0.0,
      textX: (map['text_x'] as num?)?.toDouble() ?? (map['x'] as num?)?.toDouble() ?? 0.0, 
      textY: (map['text_y'] as num?)?.toDouble() ?? (map['y'] as num?)?.toDouble() ?? 0.0, 
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0, 
      lng: (map['lon'] as num?)?.toDouble() ?? 0.0, 
      allDots: parsedDots, // Assign parsed list
    );
  }
}

class MapLine {
  final String lineId; 
  final String pathD;
  final Color color;

  MapLine({required this.lineId, required this.pathD, required this.color});

  factory MapLine.fromMap(Map<String, dynamic> map) {
    final hexString = map['color_hex']?.toString().replaceAll('#', '') ?? 'FFFFFF';
    return MapLine(
      lineId: map['route_id']?.toString() ?? map['line_id']?.toString() ?? '',
      pathD: map['path_d']?.toString() ?? '',
      color: Color(int.parse('FF$hexString', radix: 16)),
    );
  }
}

class MetroMapData {
  final List<MapStation> stations;
  final List<MapLine> lines; 
  MetroMapData({required this.stations, required this.lines});
}