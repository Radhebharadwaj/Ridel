import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ridel/features/commute/metro/map/map_models.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';

class MetroDataProvider extends ChangeNotifier {
  MetroMapData? mapData; 

  Future<void> fetchMapData() async {
    try {
      final db = await DatabaseHelper().database;

      // 🔥 BADA BADLAV: 'svg.all_dots' ko select kiya!
      final stationMaps = await db.rawQuery('''
        SELECT svg.id, svg.name, svg.x, svg.y, svg.text_x, svg.text_y, svg.all_dots, st.lat, st.lon 
        FROM svg_stations svg
        JOIN stops st ON svg.id = st.stop_id
      ''');
      
      final lineMaps = await db.rawQuery('SELECT * FROM svg_lines');

      final stations = stationMaps.map((s) => MapStation.fromMap(s)).toList();
      final lines = lineMaps.map((l) => MapLine.fromMap(l)).toList();

      mapData = MetroMapData(stations: stations, lines: lines);
      notifyListeners();
      
      debugPrint("🎯 Data successfully parsed and ready for UI!");
    } catch (e) {
      debugPrint("❌ Data Fetch Error: $e");
    }
  }
}