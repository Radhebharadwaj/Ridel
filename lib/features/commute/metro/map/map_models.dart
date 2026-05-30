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
    double parseDouble(dynamic val) {
      if (val == null) return 0.0;
      if (val is int) return val.toDouble();
      if (val is double) return val;
      return double.tryParse(val.toString()) ?? 0.0;
    }

    List<Offset> parsedDots = [];
    
    // 🔥 JSON Parsing Logic (Agar JSON hai to list banao, warna normal x,y use karo)
    if (map['all_dots'] != null && map['all_dots'].toString().isNotEmpty) {
      try {
        var decoded = jsonDecode(map['all_dots']);
        for (var d in decoded) {
          parsedDots.add(Offset(parseDouble(d['x']), parseDouble(d['y'])));
        }
      } catch (e) {
        parsedDots.add(Offset(parseDouble(map['x']), parseDouble(map['y'])));
      }
    } else {
      parsedDots.add(Offset(parseDouble(map['x']), parseDouble(map['y'])));
    }

    return MapStation(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unknown',
      x: parseDouble(map['x']),
      y: parseDouble(map['y']),
      textX: map['text_x'] != null ? parseDouble(map['text_x']) : parseDouble(map['x']), 
      textY: map['text_y'] != null ? parseDouble(map['text_y']) : parseDouble(map['y']), 
      lat: parseDouble(map['lat']), 
      lng: parseDouble(map['lon']), 
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