import 'package:flutter/foundation.dart'; 
import 'package:flutter/services.dart'; 
import 'package:universal_io/io.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:collection/collection.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http; 

// ✅ Correct Model Import
import 'package:ridel/features/metro/models/metro_models.dart'; 

class MetroService {
  static final MetroService _instance = MetroService._internal();
  factory MetroService() => _instance;
  MetroService._internal();

  List<Station> _stations = [];
  final Map<String, MetroLine> _linesMap = {};
  final Map<String, List<GraphEdge>> _adjacencyList = {};
  List<FareSlab> _fareSlabs = [];

  bool _isLoaded = false;
  ValueNotifier<bool> isLoading = ValueNotifier(false);
  ValueNotifier<String> loadingStatus = ValueNotifier("");

  List<Station> get allStations => _stations;

  Future<void> loadAllData() async {
    if (_isLoaded) return;

    isLoading.value = true;
    loadingStatus.value = "Initializing Metro Data...";
    debugPrint("🚀 ENGINE: Starting Database Initialization...");

    Database? db;

    try {
      // ==============================
      // 🌐 WEB LOGIC (Simple Fallback)
      // ==============================
      if (kIsWeb) {
        // Web par abhi hum SQLite load nahi karenge (Complex setup removed)
        loadingStatus.value = "Web functionality coming soon...";
        isLoading.value = false;
        debugPrint("⚠️ Web Mode: Skipping Local DB load.");
        return; 
      }
      
      // ==============================
      // 📱 MOBILE LOGIC (Standard SQLite)
      // ==============================
      else {
        var databasesPath = await getDatabasesPath();
        var path = join(databasesPath, "delhi_metro.db");
        File file = File(path);

        // Check if DB exists, if not copy from Assets
        if (!await file.exists()) {
          try {
             debugPrint("⚠️ Extracting DB from Assets...");
             // Make sure 'assets/delhi_metro.db' exists in pubspec.yaml
             final ByteData data = await rootBundle.load('assets/delhi_metro.db');
             final List<int> bytes = data.buffer.asUint8List();
             await file.writeAsBytes(bytes, flush: true);
             debugPrint("✅ DB Extracted Successfully!");
          } catch (e) {
             loadingStatus.value = "Asset Error: $e";
             isLoading.value = false;
             return;
          }
        }
        
        // Open the Database
        db = await openDatabase(path, readOnly: true);
      }

      // --- Loading Logic (Queries) ---
      loadingStatus.value = "Processing Map Data...";

      final List<Map<String, dynamic>> stationsData = await db!.query('stations');
      _stations = stationsData.map((row) => Station.fromMap(row)).toList();
      _stations.sort((a, b) => a.name.compareTo(b.name));

      final List<Map<String, dynamic>> linesData = await db.query('lines');
      for (var row in linesData) {
        var line = MetroLine.fromMap(row);
        _linesMap[line.id] = line;
      }

      final List<Map<String, dynamic>> edgesData = await db.query('edges');
      _buildGraph(edgesData);

      final List<Map<String, dynamic>> faresData = await db.query('fare_rules');
      _fareSlabs = faresData.map((row) => FareSlab.fromMap(row)).toList();
      _fareSlabs.sort((a, b) => a.km.compareTo(b.km));

      await db.close();

      _isLoaded = true;
      isLoading.value = false;
      loadingStatus.value = "Ready";
      debugPrint("✅ ENGINE READY: ${_stations.length} Stations loaded.");
    } catch (e) {
      debugPrint("❌ CRITICAL ERROR: $e");
      loadingStatus.value = "Failed: $e";
      isLoading.value = false;
    }
  }

  void _buildGraph(List<Map<String, dynamic>> edgesData) {
    _adjacencyList.clear();
    Map<String, Set<String>> stationLinesMap = {};

    for (var row in edgesData) {
      final edge = GraphEdge.fromMap(row);

      if (!_adjacencyList.containsKey(edge.u)) _adjacencyList[edge.u] = [];
      if (!_adjacencyList.containsKey(edge.v)) _adjacencyList[edge.v] = [];

      _adjacencyList[edge.u]!.add(edge);
      _adjacencyList[edge.v]!.add(GraphEdge(
          u: edge.v,
          v: edge.u,
          lineId: edge.lineId,
          distance: edge.distance,
          time: edge.time));

      if (!stationLinesMap.containsKey(edge.u)) stationLinesMap[edge.u] = {};
      if (!stationLinesMap.containsKey(edge.v)) stationLinesMap[edge.v] = {};

      stationLinesMap[edge.u]!.add(edge.lineId);
      stationLinesMap[edge.v]!.add(edge.lineId);
    }

    for (var station in _stations) {
      if (stationLinesMap.containsKey(station.id)) {
        station.lineCodes.addAll(stationLinesMap[station.id]!);
      }
    }
  }

  Station? getStationByName(String name) =>
      _stations.firstWhereOrNull((s) => s.name.toLowerCase() == name.toLowerCase());
  Station? getStationById(String id) => _stations.firstWhereOrNull((s) => s.id == id);
  MetroLine? getLine(String id) => _linesMap[id];

  RouteResult? calculateRoute(String startName, String endName) {
    final startNode = getStationByName(startName);
    final endNode = getStationByName(endName);

    if (startNode == null || endNode == null || startNode.id == endNode.id) return null;

    Map<String, double> times = {};
    Map<String, String> previous = {};
    Map<String, String> arrivalLine = {}; 
    Set<String> visited = {};

    for (var s in _stations) {
      times[s.id] = double.infinity;
    }
    times[startNode.id] = 0;
    arrivalLine[startNode.id] = "START";

    List<String> queue = [startNode.id];

    while (queue.isNotEmpty) {
      queue.sort((a, b) => times[a]!.compareTo(times[b]!));
      String u = queue.removeAt(0);

      if (u == endNode.id) break;
      if (visited.contains(u)) continue;
      visited.add(u);

      if (_adjacencyList.containsKey(u)) {
        for (var edge in _adjacencyList[u]!) {
          double weight = edge.time.toDouble();

          String lineForThisEdge = edge.lineId;
          String lineArrivedAtU = arrivalLine[u] ?? "START";
          if (lineArrivedAtU != "START" && lineArrivedAtU != lineForThisEdge) {
            weight += 5.0; 
          }

          double newTime = times[u]! + weight;
          if (newTime < times[edge.v]!) {
            times[edge.v] = newTime;
            previous[edge.v] = u;
            arrivalLine[edge.v] = lineForThisEdge;
            if (!queue.contains(edge.v)) queue.add(edge.v);
          }
        }
      }
    }

    List<Station> path = [];
    List<String> interchangeStations = [];
    String? curr = endNode.id;
    double totalDist = 0;
    String? currentLine = arrivalLine[endNode.id];
    String? prevLine;

    if (!previous.containsKey(curr) && curr != startNode.id) return null;

    List<String> pathIds = [];
    while (curr != null) {
      pathIds.insert(0, curr);
      String? prevId = previous[curr];

      if (prevId != null) {
        final edge = _adjacencyList[prevId]!.firstWhere((e) => e.v == curr);
        totalDist += edge.distance;
      }
      curr = prevId;
    }

    for (int i = 0; i < pathIds.length; i++) {
      Station station = getStationById(pathIds[i])!;
      path.add(station);

      if (i == 0) {
        prevLine = _adjacencyList[pathIds[i]]?.firstWhereOrNull((e) => e.v == pathIds[i + 1])?.lineId ?? "START";
        currentLine = prevLine;
      } else if (i < pathIds.length - 1) {
        currentLine = _adjacencyList[pathIds[i - 1]]?.firstWhereOrNull((e) => e.v == pathIds[i])?.lineId;

        if (currentLine != null && currentLine != prevLine && prevLine != "START") {
          interchangeStations.add(station.name);
        }
        prevLine = currentLine;
      }
    }

    int finalPrice = _calculateFare(totalDist);

    return RouteResult(
      path: path,
      totalTime: times[endNode.id]!.toInt(),
      totalDistance: double.parse(totalDist.toStringAsFixed(1)),
      fare: finalPrice,
      stationsCount: path.length,
      interchangeStations: interchangeStations.toSet().toList(), 
    );
  }

  int _calculateFare(double dist) {
    if (_fareSlabs.isEmpty) return 10;
    double adjustedDist = dist > 1.0 ? dist - 0.5 : dist;
    for (var slab in _fareSlabs) {
      if (adjustedDist <= slab.km) return slab.price;
    }
    return _fareSlabs.last.price;
  }

  Map<String, String> getPlatformInfo(Station station, String lineCode, String nextStationName) {
    return {"number": "P?", "towards": nextStationName};
  }

  String getBestGate(Station station) {
    if (station.gates.isEmpty) return "Exit";
    try {
      var g = station.gates.firstWhereOrNull((gate) => gate is Map && gate['gate_no'] != null);
      if (g != null && g is Map) {
        String exitName = g['exit_to'] ?? 'City';
        return "Gate ${g['gate_no']} towards $exitName";
      }
    } catch (e) {
      /* ignore */
    }
    return "Exit";
  }
}