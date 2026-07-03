import 'package:flutter/foundation.dart';

import 'package:ridel/features/commute/metro/map/map_models.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';

// 🚀 TASK 2: BACKGROUND ISOLATE PARSER (KILL 784ms INP)
MetroMapData _parseNetworkGeoJson(Map<String, dynamic> data) {
  final stations =
      (data['stations'] as List).map((s) => MapStation.fromMap(Map<String, dynamic>.from(s))).toList();

  final lines = (data['lines'] as List)
      .map((l) {
        final map = Map<String, dynamic>.from(l);
        return MapLine.fromMap({
          'line_id': map['line_id'] ?? map['LINE_ID'],
          'path_d': map['path_d'] ?? map['PATH_D'],
          'color_hex': map['color_hex'] ?? map['COLOR_HEX'],
          'route_id': map['route_id'] ?? map['ROUTE_ID'],
        });
      })
      .toList();

  return MetroMapData(stations: stations, lines: lines);
}

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

      // 🚀 Parse in Background Isolate
      mapData = await compute(_parseNetworkGeoJson, data);

      _isLoading = false;
      notifyListeners(); // Success par UI update

      debugPrint("🎯 Hybrid Map Data successfully parsed in background! 🚀");
    } catch (e) {
      _isLoading = false;
      notifyListeners(); // 🚀 FIX: Error aane par bhi UI ko batao taaki loading spinner ruk jaye
      debugPrint("❌ Data Fetch Error: $e");
    }
  }
}
