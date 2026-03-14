import 'dart:io';
import 'dart:async';
import 'dart:typed_data'; // 🔥 Ye add kiya hai tile data (Uint8List) ke liye
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:http/http.dart' as http;

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  static Future<Database>? _dbFuture;

  // ✅ Yeh 100% Sahi URL hai
static const String _supabaseDbUrl = "https://oysalcuewxfxbgeiqcpr.supabase.co/storage/v1/object/public/city_packages/delhi/delhi_v1.db";

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _dbFuture ??= _initDatabase(); 
    _database = await _dbFuture;
    return _database!;
  }

  Future<Database> _initDatabase() async {
    const String dbName = 'delhi_v1.db'; 

    if (kIsWeb) {
      final factory = databaseFactoryFfiWeb;
      bool dbExists = await factory.databaseExists(dbName);

      if (!dbExists) {
        debugPrint("⏳ Web: Supabase se Database download ho raha hai...");
        try {
          final response = await http.get(Uri.parse(_supabaseDbUrl));
          if (response.statusCode == 200) {
            await factory.writeDatabaseBytes(dbName, response.bodyBytes);
            debugPrint("✅ Web: Database Download & Cache SUCCESSFUL!");
          } else {
            throw Exception("❌ Web DB Download Failed! Status: ${response.statusCode}");
          }
        } catch (e) {
          debugPrint("❌ Web DB Fetch Error: $e");
          rethrow;
        }
      } else {
        debugPrint("⚡ Web: Database pehle se Cache me hai! Fast loading...");
      }
      return await factory.openDatabase(dbName);
    } 
    
    // 📱 2. MOBILE (ANDROID/IOS) CLOUD CACHING
    else {
      Directory documentsDirectory = await getApplicationDocumentsDirectory();
      String path = join(documentsDirectory.path, dbName);
      final file = File(path);

      if (!await file.exists()) {
        debugPrint("⏳ Mobile: Supabase se Database download ho raha hai...");
        try {
          final response = await http.get(Uri.parse(_supabaseDbUrl));
          if (response.statusCode == 200) {
            await file.writeAsBytes(response.bodyBytes, flush: true);
            debugPrint("✅ Mobile: Database Download & Cache SUCCESSFUL!");
          } else {
            throw Exception("❌ Mobile DB Download Failed! Status: ${response.statusCode}");
          }
        } catch (e) {
          debugPrint("❌ Mobile DB Fetch Error: $e");
          rethrow;
        }
      } else {
        debugPrint("⚡ Mobile: Database pehle se Cache me hai! Fast loading...");
      }
      return await openDatabase(path);
    }
  }

  // --- QUERIES ---

  Future<List<Map<String, dynamic>>> getAllLines() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT route_id, route_long_name, route_short_name, route_color 
      FROM routes 
      WHERE transport_type = 0 
      ORDER BY route_id ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> getStationsByLineIds(
      List<String> lineIds) async {
    final db = await database;
    if (lineIds.isEmpty) return [];
    String idsString = lineIds.map((id) => "'$id'").join(',');
    try {
      return await db.rawQuery('''
        SELECT DISTINCT s.stop_id, s.stop_name
        FROM stops s
        INNER JOIN graph_edges g ON s.stop_id = g.from_node_id
        WHERE g.route_id IN ($idsString)
        ORDER BY s.stop_name ASC
      ''');
    } catch (e) {
      print("Error fetching stations: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAllStations() async {
    final db = await database;
    return await db.rawQuery(
        "SELECT stop_id, stop_name, lat, lon FROM stops");
  }

  Future<List<Map<String, dynamic>>> getStationsByMode(int mode) async {
    final db = await database;
    print("🔍 Fetching Data for Mode: $mode (0=Metro, 1=Bus)");
    try {
      final results = await db.rawQuery('''
        SELECT stop_id, stop_name, lat, lon
        FROM stops 
        WHERE transport_mode = ? 
        ORDER BY stop_name ASC
      ''', [mode]);
      print("✅ Found ${results.length} stops for Mode $mode");
      return results;
    } catch (e) {
      print("❌ Database Error: $e");
      return [];
    }
  }

  // ========== METRO SERVICE QUERIES ==========

  Future<List<Map<String, dynamic>>> getAllStopsDetailed() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT stop_id, stop_name, lat, lon
      FROM stops
      WHERE transport_mode = 0
    ''');
  }

  Future<List<Map<String, dynamic>>> getAllGraphEdges() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT from_node_id, to_node_id, route_id, time_seconds, distance_km
      FROM graph_edges
    ''');
  }

  Future<List<Map<String, dynamic>>> getAllRoutes() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT route_id, route_short_name, route_color
      FROM routes
    ''');
  }

  Future<Map<String, dynamic>?> findNearestStation(double lat, double lon) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT stop_id, stop_name, lat, lon,
             ( (lat - ?) * (lat - ?) + (lon - ?) * (lon - ?) ) as dist_sq
      FROM stops
      ORDER BY dist_sq ASC
      LIMIT 1
    ''', [lat, lat, lon, lon]);

    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

  // ========== BUS SERVICE QUERIES ==========

  Future<List<Map<String, dynamic>>> getAllBusStops() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT stop_id, stop_name, lat, lon
      FROM stops
      WHERE transport_mode = 1
    ''');
  }

  Future<List<Map<String, dynamic>>> getBusGraphEdges() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT from_node_id, to_node_id, route_id, distance_km, time_seconds
      FROM graph_edges
      WHERE from_node_id GLOB '[0-9]*' AND to_node_id GLOB '[0-9]*'
    ''');
  }

  Future<List<Map<String, dynamic>>> getAllBusRoutesInfo() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT route_id, route_short_name, route_long_name 
      FROM routes 
      WHERE transport_type = 1
    ''');
  }

  Future<List<Map<String, dynamic>>> getBusFareConfig() async {
    final db = await database;
    return await db.query(
      'fare_config', 
      where: 'mode = ?', 
      whereArgs: [1], 
      orderBy: 'min_km ASC'
    );
  }

  // ========== FARE AND PLATFORMS ==========

  Future<List<Map<String, dynamic>>> getFareConfig() async {
    final db = await database;
    return await db.query(
      'fare_config', 
      where: 'mode = ?', 
      whereArgs: [0], 
      orderBy: 'min_km ASC'
    );
  }

  Future<List<Map<String, dynamic>>> getAllPlatforms() async {
    final db = await database;
    return await db.query('platform_info');
  }

  // ========== FACILITIES, GATES, PARKING QUERIES ==========

  Future<List<Map<String, dynamic>>> getGatesForStation(String stopId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT gate_name, location_desc, is_open
      FROM station_gates
      WHERE stop_id = ?
    ''', [stopId]);
  }

  Future<Map<String, dynamic>?> getParkingForStation(String stopId) async {
    final db = await database;
    final res = await db.rawQuery('''
      SELECT car_capacity, bike_capacity, cycle_capacity
      FROM station_parking
      WHERE stop_id = ?
    ''', [stopId]);
    return res.isNotEmpty ? res.first : null;
  }

  Future<List<Map<String, dynamic>>> getFacilitiesForStation(String stopId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT facility_code, location_desc
      FROM station_facilities
      WHERE stop_id = ?
    ''', [stopId]);
  }
  
  Future<List<Map<String, dynamic>>> getPlatformsForStation(String stopId) async {
     final db = await database;
     return await db.query(
       'platform_info', 
       where: 'stop_id = ?', 
       whereArgs: [stopId]
     );
  }

  // ==========================================================
  // 🗺️ OFFLINE MAP TILES CACHING ENGINE (The Masterstroke)
  // ==========================================================

  Future<void> _ensureCacheTableExists() async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS map_tiles_cache_hd(
        z INTEGER,
        x INTEGER,
        y INTEGER,
        tile_data BLOB,
        PRIMARY KEY (z, x, y)
      )
    ''');
  }

  Future<Uint8List?> getCachedTile(int z, int x, int y) async {
    await _ensureCacheTableExists();
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'map_tiles',
      columns: ['tile_data'],
      where: 'z = ? AND x = ? AND y = ?',
      whereArgs: [z, x, y],
    );
    if (maps.isNotEmpty) {
      return maps.first['tile_data'] as Uint8List;
    }
    return null;
  }

  Future<void> saveTileToCache(int z, int x, int y, Uint8List tileData) async {
    await _ensureCacheTableExists();
    final db = await database;
    await db.insert(
      'map_tiles',
      {'z': z, 'x': x, 'y': y, 'tile_data': tileData},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}