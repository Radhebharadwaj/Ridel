import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ridel/core/config/app_config.dart';
// 🚀 THE ENCRYPTION FIX: SQLCipher wapas Zinda kar diya Mobile ke liye!
// (Note: Jab Web par testing karni ho, tabhi ise comment karke normal sqflite lagana)
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseHelper {
  factory DatabaseHelper() => instance;
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  final _secureStorage = const FlutterSecureStorage();
  String currentCity = 'delhi';

  // ==========================================================
  // 🚀 THE BILLION DOLLAR UPGRADE: ZERO-WAIT HYBRID ENGINE
  // ==========================================================
  bool _isLocalDbReady = false;
  bool _isDbDownloading = false;

  // MASTER SWITCH: Agar Web hai, YA FIR mobile DB abhi download ho raha hai -> Use API!
  bool get useWebAPI => kIsWeb || !_isLocalDbReady;

  // 🧠 WEB IN-MEMORY CACHE
  List<Map<String, dynamic>>? _cachedMetroStops;
  List<Map<String, dynamic>>? _cachedBusStops;
  List<Map<String, dynamic>>? _cachedMetroEdges;
  List<Map<String, dynamic>>? _cachedBusEdges;

  // 🚀 NAYA FUNCTION: Background me DB load karo, UI ko API par chalne do
  Future<void> initBackgroundSync() async {
    if (_isLocalDbReady || _isDbDownloading) return;
    _isDbDownloading = true;
    try {
      debugPrint(
        '⏳ Background DB Download/Load started... (App is running on Cloud APIs meanwhile)',
      );
      _database = await _initDatabaseForCity(currentCity);
      _isLocalDbReady = true;
      debugPrint(
        '✅ LOCAL OFFLINE DB READY! App automatically switched to 100% Offline Mode! 🚀',
      );
    } catch (e) {
      debugPrint('❌ DB Load Failed: $e');
    } finally {
      _isDbDownloading = false;
    }
  }

  // 🌐 WEB API ROUTER ENGINE (100% UNIVERSAL, CASE-SAFE & TYPE-SAFE)
  Future<List<Map<String, dynamic>>> _fetchFromWebAPI(
    String tableName,
    Map<String, dynamic> body,
  ) async {
    final apiUrl = '${AppConfig.webDataApiUrl}fetch';
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final userId = user?.id ?? 'guest_user';

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          ...body,
          'table': tableName,
          'city': currentCity,
          'user_id': userId
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawResults = data['results'] as List? ?? <dynamic>[];

        return rawResults.map((row) {
          final normalizedRow = <String, dynamic>{};
          (row as Map<String, dynamic>).forEach((key, value) {
            final k = key.toLowerCase();
            if (<String>[
              'lat',
              'lon',
              'lng',
              'x',
              'y',
              'min_km',
              'max_km',
              'price_normal',
              'price_special',
              'distance_km',
              'time_seconds',
            ].contains(k)) {
              if (value == null) {
                normalizedRow[k] = 0.0;
              } else if (value is num) {
                normalizedRow[k] = value.toDouble();
              } else {
                normalizedRow[k] = double.tryParse(value.toString()) ?? 0.0;
              }
            } else if (['transport_mode', 'transport_type', 'mode']
                .contains(k)) {
              normalizedRow[k] = int.tryParse(value?.toString() ?? '0') ?? 0;
            } else {
              normalizedRow[k] = value;
            }
          });
          return normalizedRow;
        }).toList();
      } else {
        if (response.statusCode == 500) {
          debugPrint(
              '⚠️ Web API Graceful Fail: Server returned 500 for $tableName');
          return [];
        }
        throw Exception('Web API Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Web API Fail ($tableName): $e');
      return [];
    }
  }

  // 🛡️ SECURE KEY FETCHER
  Future<String> _getSecureDbPassword() async {
    if (kIsWeb) return '';
    final storedKey = await _secureStorage.read(key: 'secure_db_key');
    if (storedKey != null && storedKey.isNotEmpty) return storedKey;

    debugPrint('🔐 Fetching Database Key securely...');
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final signature = Hmac(sha256, utf8.encode(AppConfig.appSecretPasskey))
        .convert(utf8.encode(timestamp))
        .toString();

    final response = await http.get(
      Uri.parse(AppConfig.keyApiUrl),
      headers: {'x-timestamp': timestamp, 'x-signature': signature},
    );

    if (response.statusCode == 200) {
      final newKey = jsonDecode(response.body)['key'] as String;
      await _secureStorage.write(key: 'secure_db_key', value: newKey);
      return newKey;
    } else {
      throw Exception('🚨 Security Breach: API Rejected!');
    }
  }

  Future<void> switchCity(String newCity) async {
    if (currentCity == newCity && _database != null) return;
    currentCity = newCity.toLowerCase().trim();

    _cachedMetroStops = null;
    _cachedBusStops = null;
    _cachedMetroEdges = null;
    _cachedBusEdges = null;
    _isLocalDbReady = false;

    if (!kIsWeb && _database != null) {
      await _database!.close();
      _database = null;
    }
    if (!kIsWeb) initBackgroundSync();
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabaseForCity(currentCity);
    _isLocalDbReady = true;
    return _database!;
  }

  Future<Database> _initDatabaseForCity(String city) async {
    try {
      if (kIsWeb) {
        final dbFileName = '${city}_web.db';
        return await databaseFactoryFfiWeb.openDatabase(dbFileName);
      }

      final dbFileName = '${city}_locked.db';
      final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, dbFileName);
    final file = File(path);

    // 🚀 STEP 1: Smart Downloader with Size & Error Checking
    if (!await file.exists()) {
      debugPrint(
        '⏳ Downloading DB from: ${AppConfig.dbDownloadUrl}?bucket=${AppConfig.storageBucket}&key=$city/$dbFileName',
      );
      try {
        final downloadUrl =
            '${AppConfig.dbDownloadUrl}?bucket=${AppConfig.storageBucket}&key=$city/$dbFileName';
        final response = await http.get(Uri.parse(downloadUrl));

        if (response.statusCode == 200) {
          // THE PROTECTOR: File size check (Cloudflare error pages are tiny)
          if (response.bodyBytes.length > 50000) {
            // Checking if > 50KB
            await file.writeAsBytes(response.bodyBytes, flush: true);
            debugPrint('✅ DB File successfully downloaded and saved!');
          } else {
            debugPrint(
              "❌ CRITICAL: Downloaded file is too small (${response.bodyBytes.length} bytes). It's an error page!",
            );
            throw Exception('Fake DB File Downloaded');
          }
        } else {
          throw Exception('Download Failed! Status: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('❌ Download Error: $e');
        // Agar download fail ho gaya, toh return kardo taki API se chalta rahe
        rethrow;
      }
    }

    final securePassword = await _getSecureDbPassword();

    // 🚀 STEP 2: Self-Healing Open Logic (Delete corrupt file if needed)
    try {
      return await openDatabase(
        path,
        password: securePassword,
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA synchronous = NORMAL');
          await db.execute('PRAGMA temp_store = MEMORY');
        },
      );
    } catch (e) {
      debugPrint(
        '🚨 SQLCipher Open Failed! The DB file might be corrupted. Deleting it...',
      );
      // Agar corrupt file hai toh use delete kar do taaki agli baar fresh download ho!
      if (await file.exists()) {
        await file.delete();
      }
      rethrow; // API mode par fallback karne ke liye
    }
    } catch (e) {
      debugPrint('🚨 Fatal Database Initialization Error: $e');
      rethrow;
    }
  }

  Future<Uint8List?> getMapTile(int z, int folderName, int fileName) async {
    if (useWebAPI) {
      // 🚀 Har jagah kIsWeb ko hatakar `useWebAPI` laga diya hai
      final data = await _fetchFromWebAPI(
        'map_tiles',
        {'z': z, 'folder_name': folderName, 'file_name': fileName},
      );
      if (data.isNotEmpty) {
        final rawData = data.first['tile_data'] ?? data.first['TILE_DATA'];
        if (rawData is String) {
          final bytes = rawData
              .split(',')
              .map((e) => int.tryParse(e.trim()) ?? 0)
              .toList();
          return Uint8List.fromList(bytes);
        } else if (rawData is List) {
          return Uint8List.fromList(List<int>.from(rawData));
        }
      }
      return null;
    }
    final db = await database;
    final maps = await db.query(
      'map_tiles',
      columns: ['tile_data'],
      where: 'z = ? AND folder_name = ? AND file_name = ?',
      whereArgs: [z, folderName, fileName],
    );
    if (maps.isNotEmpty) return maps.first['tile_data']! as Uint8List;
    return null;
  }

  // ==========================================================
  // 🚀 SMART HYBRID QUERIES (RAM CACHING & OFFLINE)
  // ==========================================================

  Future<List<Map<String, dynamic>>> getStopsByMode(int mode) async {
    if (useWebAPI) {
      if (mode == 0 && _cachedMetroStops != null) return _cachedMetroStops!;
      if (mode == 1 && _cachedBusStops != null) return _cachedBusStops!;
      final data = await _fetchFromWebAPI('stops', {'mode': mode});
      if (mode == 0) _cachedMetroStops = data;
      if (mode == 1) _cachedBusStops = data;
      return data;
    }
    final db = await database;
    return db.rawQuery(
      'SELECT * FROM stops WHERE transport_mode = ? ORDER BY stop_name ASC',
      [mode],
    );
  }

  Future<List<Map<String, dynamic>>> searchStops(
    String query, {
    int? mode,
  }) async {
    if (useWebAPI) {
      var allStops = <Map<String, dynamic>>[];
      if (mode == null) {
        allStops = [...(await getStopsByMode(0)), ...(await getStopsByMode(1))];
      } else {
        allStops = await getStopsByMode(mode);
      }
      final q = query.toLowerCase();
      return allStops
          .where((stop) {
            final name = (stop['stop_name'] ?? stop['name'] ?? '')
                .toString()
                .toLowerCase();
            final keywords =
                (stop['search_keywords'] ?? '').toString().toLowerCase();
            return name.contains(q) || keywords.contains(q);
          })
          .take(25)
          .toList();
    }
    final db = await database;
    final param = '%${query.toUpperCase()}%';
    var sql =
        'SELECT * FROM stops WHERE (stop_name LIKE ? OR search_keywords LIKE ?)';
    final args = <dynamic>[param, param];
    if (mode != null) {
      sql += ' AND transport_mode = ?';
      args.add(mode);
    }
    return db.rawQuery('$sql ORDER BY stop_name ASC LIMIT 25', args);
  }

  Future<List<Map<String, dynamic>>> getGraphEdges({int? transportMode}) async {
    if (useWebAPI) {
      if (transportMode == 0 && _cachedMetroEdges != null) {
        return _cachedMetroEdges!;
      }
      if (transportMode == 1 && _cachedBusEdges != null) {
        return _cachedBusEdges!;
      }
      final data =
          await _fetchFromWebAPI('graph_edges', {'mode': transportMode});
      if (transportMode == 0) _cachedMetroEdges = data;
      if (transportMode == 1) _cachedBusEdges = data;
      return data;
    }
    final db = await database;
    return transportMode != null
        ? await db.rawQuery(
            'SELECT * FROM graph_edges WHERE transport_mode = ?',
            [transportMode],
          )
        : await db.rawQuery('SELECT * FROM graph_edges');
  }

  Future<List<Map<String, dynamic>>> getAllRoutesInfo(int transportType) async {
    if (useWebAPI) {
      return _fetchFromWebAPI('routes', {'mode': transportType});
    }
    final db = await database;
    return db.rawQuery(
      'SELECT * FROM routes WHERE transport_type = ?',
      [transportType],
    );
  }

  Future<List<Map<String, dynamic>>> getFareConfig(int mode) async {
    if (useWebAPI) return _fetchFromWebAPI('fare_config', {'mode': mode});
    final db = await database;
    return db.query(
      'fare_config',
      where: 'transport_mode = ?',
      whereArgs: [mode],
      orderBy: 'min_km ASC',
    );
  }

  Future<List<String>> getBusSchedules(String stopId, String routeId) async {
    if (useWebAPI) return [];
    final db = await database;
    final res = await db.query(
      'bus_schedules',
      columns: ['departure_times'],
      where: 'stop_id = ? AND route_id = ?',
      whereArgs: [stopId, routeId],
    );
    return res.isNotEmpty
        ? res.first['departure_times'].toString().split(',')
        : [];
  }

  Future<List<Map<String, dynamic>>> getRoutesForStop(String stopId) async {
    if (useWebAPI) return [];
    final db = await database;
    return db.rawQuery(
      '''SELECT DISTINCT r.* FROM routes r INNER JOIN graph_edges e ON r.route_id = e.route_id WHERE (e.from_node_id = ? OR e.to_node_id = ?) AND r.transport_type = 1''',
      [stopId, stopId],
    );
  }

  Future<List<Map<String, dynamic>>> getPlatformsForStation(
      String stopId) async {
    if (useWebAPI) {
      // 🚀 THE FIX: App ke cached graph_edges se directly platform nikal lenge!
      final edges = await getGraphEdges(transportMode: 0);
      final Map<String, String> platformsMap =
          {}; // DISTINCT ke liye map use kiya

      for (var edge in edges) {
        final fromNode =
            (edge['from_node_id'] ?? edge['FROM_NODE_ID']).toString();
        final platformName =
            (edge['platform_name'] ?? edge['PLATFORM_NAME'])?.toString();
        final towards = (edge['to_node_id'] ?? edge['TO_NODE_ID'])?.toString();

        // Agar station match karta hai aur platform name null nahi hai
        if (fromNode == stopId &&
            platformName != null &&
            platformName.trim().isNotEmpty) {
          // Map me daalne se duplicate platforms (jaise same platform se 2 line jati hon) remove ho jayenge
          if (!platformsMap.containsKey(platformName)) {
            platformsMap[platformName] = towards ?? '';
          }
        }
      }

      // Wapas usko List of Maps me convert kar diya UI ke liye
      return platformsMap.entries
          .map((e) => {'platform_name': e.key, 'towards_station_code': e.value})
          .toList();
    }

    // Offline Mobile DB ke liye purana code as it is
    final db = await database;
    return db.rawQuery(
      '''SELECT DISTINCT platform_name, to_node_id as towards_station_code FROM graph_edges WHERE from_node_id = ? AND transport_mode = 0 AND platform_name IS NOT NULL''',
      [stopId],
    );
  }

  Future<List<Map<String, dynamic>>> getGatesForStation(String stopId) async {
    if (useWebAPI) {
      // 1. Backend se poora data aane do
      final data = await _fetchFromWebAPI('station_gates', {});

      // 2. 🚀 THE BULLETPROOF FILTER: Flutter khud use filter karega
      return data.where((row) {
        final idInDb = (row['stop_id'] ?? row['station_id'] ?? '').toString();
        return idInDb == stopId;
      }).toList();
    }

    final db = await database;
    // Offline mode ke liye bhi safety
    return db.rawQuery(
        'SELECT * FROM station_gates WHERE stop_id = ? OR station_id = ?',
        [stopId, stopId]);
  }

  Future<Map<String, dynamic>?> getParkingForStation(String stopId) async {
    if (useWebAPI) {
      final res = await _fetchFromWebAPI('station_parking', {});
      // 🚀 Force Filter
      final filteredRes = res.where((row) {
        final idInDb = (row['stop_id'] ?? row['station_id'] ?? '').toString();
        return idInDb == stopId;
      }).toList();
      return filteredRes.isNotEmpty ? filteredRes.first : null;
    }
    final db = await database;
    final res = await db.rawQuery(
        'SELECT * FROM station_parking WHERE stop_id = ? OR station_id = ?',
        [stopId, stopId]);
    return res.isNotEmpty ? res.first : null;
  }

  Future<List<Map<String, dynamic>>> getFacilitiesForStation(
      String stopId) async {
    if (useWebAPI) {
      final data = await _fetchFromWebAPI('station_facilities', {});
      // 🚀 Force Filter
      return data.where((row) {
        final idInDb = (row['stop_id'] ?? row['station_id'] ?? '').toString();
        return idInDb == stopId;
      }).toList();
    }
    final db = await database;
    return db.rawQuery(
        'SELECT * FROM station_facilities WHERE stop_id = ? OR station_id = ?',
        [stopId, stopId]);
  }

  Future<List<Map<String, dynamic>>> getStationsByLineIds(
    List<String> lineIds,
  ) async {
    if (useWebAPI) {
      if (lineIds.isEmpty) return [];
      final edges = await getGraphEdges(transportMode: 0);
      final stops = await getStopsByMode(0);
      final validStopIds = <String>{};
      for (final edge in edges) {
        final routeId = (edge['route_id'] ?? edge['ROUTE_ID'] ?? '').toString();
        if (lineIds.contains(routeId)) {
          validStopIds
              .add((edge['from_node_id'] ?? edge['FROM_NODE_ID']).toString());
        }
      }
      final matchedStops = stops
          .where(
            (stop) => validStopIds
                .contains((stop['stop_id'] ?? stop['STOP_ID']).toString()),
          )
          .toList();
      matchedStops.sort(
        (a, b) => (a['stop_name'] ?? '')
            .toString()
            .compareTo((b['stop_name'] ?? '').toString()),
      );
      return matchedStops;
    }
    final db = await database;
    if (lineIds.isEmpty) return [];
    final idsString = lineIds.map((id) => "'$id'").join(',');
    return db.rawQuery(
      '''SELECT DISTINCT s.* FROM stops s INNER JOIN graph_edges g ON s.stop_id = g.from_node_id WHERE g.route_id IN ($idsString) ORDER BY s.stop_name ASC''',
    );
  }

  Future<Map<String, dynamic>> getMetroMapDrawingData() async {
    double safeDouble(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? 0.0;
    }

    if (useWebAPI) {
      final lines = await _fetchFromWebAPI('svg_lines', {});
      final svgStations = await _fetchFromWebAPI('svg_stations', {});
      final stops = await getStopsByMode(0);

      final mergedStations = <Map<String, dynamic>>[];
      for (final svg in svgStations) {
        final svgId = (svg['id'] ?? svg['ID']).toString();
        final stopMatch = stops.firstWhere(
          (s) => (s['stop_id'] ?? s['STOP_ID']).toString() == svgId,
          orElse: () => <String, dynamic>{},
        );
        mergedStations.add({
          'id': svg['id'] ?? svg['ID'],
          'name': svg['name'] ?? svg['NAME'],
          'x': safeDouble(svg['x'] ?? svg['X']),
          'y': safeDouble(svg['y'] ?? svg['Y']),
          'text_x': safeDouble(svg['text_x'] ?? svg['TEXT_X']),
          'text_y': safeDouble(svg['text_y'] ?? svg['TEXT_Y']),
          'all_dots': svg['all_dots'] ?? svg['ALL_DOTS'],
          'lat': safeDouble(stopMatch['lat'] ?? stopMatch['LAT']),
          'lon': safeDouble(
            stopMatch['lon'] ??
                stopMatch['LON'] ??
                stopMatch['lng'] ??
                stopMatch['LNG'],
          ),
        });
      }
      return {'stations': mergedStations, 'lines': lines};
    }

    final db = await database;
    final stationMaps = await db.rawQuery(
      '''SELECT svg.id, svg.name, svg.x, svg.y, svg.text_x, svg.text_y, svg.all_dots, st.lat, st.lon FROM svg_stations svg JOIN stops st ON svg.id = st.stop_id''',
    );
    final lineMaps = await db.rawQuery('SELECT * FROM svg_lines');
    return {'stations': stationMaps, 'lines': lineMaps};
  }

  // ALIAS METHODS
  Future<List<Map<String, dynamic>>> getStationsByMode(int mode) async =>
      getStopsByMode(mode);
  Future<List<Map<String, dynamic>>> getAllStopsDetailed() async =>
      getStopsByMode(0);
  Future<List<Map<String, dynamic>>> getAllLines() async => getAllRoutesInfo(0);
  Future<List<Map<String, dynamic>>> getAllGraphEdges() async =>
      getGraphEdges(transportMode: 0);
  Future<List<Map<String, dynamic>>> getAllStations() async =>
      getStopsByMode(0);
  Future<List<Map<String, dynamic>>> getMetroFareConfig() async =>
      getFareConfig(0);
  Future<List<Map<String, dynamic>>> getAllBusStops() async =>
      getStopsByMode(1);
  Future<List<Map<String, dynamic>>> getBusGraphEdges() async =>
      getGraphEdges(transportMode: 1);
  Future<List<Map<String, dynamic>>> getAllBusRoutesInfo() async =>
      getAllRoutesInfo(1);
  Future<List<Map<String, dynamic>>> getBusFareConfig() async =>
      getFareConfig(1);
}

class CityNotFoundException implements Exception {
  CityNotFoundException(this.message);
  final String message;
  @override
  String toString() => message;
}
