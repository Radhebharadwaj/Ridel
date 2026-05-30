import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ridel/features/commute/metro/map/map_models.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';

class MetroDataProvider extends ChangeNotifier {
  MetroMapData? mapData; 
  bool _isLoading = false; 

  Future<void> fetchMapData() async {
    if (mapData != null || _isLoading) return; 

    try {
      _isLoading = true;
      // UI ko batao ki loading shuru ho gayi hai
      notifyListeners(); 
      
      // 🚀 THE GOD-LEVEL FIX: Use the Hybrid Function
      final data = await DatabaseHelper.instance.getMetroMapDrawingData();

      // Stations pehle se lowercase/normalized hain DatabaseHelper se
      final stations = (data['stations'] as List).map((s) => MapStation.fromMap(s)).toList();
      
      // Cloudflare D1 keys uppercase mein bhejta hai, isliye smart conversion:
      final lines = (data['lines'] as List).map((l) => MapLine.fromMap({
        'line_id': l['line_id'] ?? l['LINE_ID'],
        'path_d': l['path_d'] ?? l['PATH_D'],
        'color_hex': l['color_hex'] ?? l['COLOR_HEX'],
        'route_id': l['route_id'] ?? l['ROUTE_ID'],
      })).toList();

      mapData = MetroMapData(stations: stations, lines: lines);
      _isLoading = false;
      notifyListeners(); // Success par UI update
      
      debugPrint("🎯 Hybrid Map Data successfully parsed and ready for UI! 🚀");
    } catch (e) {
      _isLoading = false;
      notifyListeners(); // 🚀 FIX: Error aane par bhi UI ko batao taaki loading spinner ruk jaye
      debugPrint("❌ Data Fetch Error: $e");
    }
  }
}