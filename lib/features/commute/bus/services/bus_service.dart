import 'dart:async';
import 'dart:math' show cos, sqrt, asin; // For Distance Calculation
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';
import 'package:ridel/features/commute/shared/models/route_models.dart';
import 'package:ridel/features/commute/bus/models/bus_models.dart';
import 'package:ridel/features/commute/metro/models/metro_models.dart'; // Reusing GraphEdge

// 🔥 ADDED ENUM (Top of file, outside class)
enum BusRoutePreference { fastest, lessInterchange }

class BusService {
  static final BusService _instance = BusService._internal();
  factory BusService() => _instance;
  BusService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  // In-Memory Data
  Map<String, List<GraphEdge>> _graph = {};
  Map<String, String> _stopNames = {}; 
  Map<String, LatLng> _stopLocations = {}; // 🔥 New: To calculate distance
  Map<String, BusRouteInfo> _routeInfoMap = {};
  List<BusFareRule> _fareRules = [];
  bool _isInitialized = false;

  // --- INITIALIZATION ---
  Future<void> initialize() async {
    if (_isInitialized) return;
    debugPrint("🚌 BusService: Loading Data...");

    final results = await Future.wait([
      _dbHelper.getAllBusStops(),
      _dbHelper.getBusGraphEdges(),
      _dbHelper.getAllBusRoutesInfo(),
      _dbHelper.getBusFareConfig(),
    ]);

    // 1. Load Stops & Locations
    for (var row in results[0]) {
      String id = row['stop_id'].toString();
      _stopNames[id] = row['stop_name'].toString();
      _stopLocations[id] = LatLng(
        (row['lat'] as num).toDouble(), 
        (row['lon'] as num).toDouble()
      );
    }

    // 2. Load Routes Info
    for (var row in results[2]) {
      final info = BusRouteInfo.fromMap(row);
      _routeInfoMap[info.routeId] = info;
    }

    // 3. Build Graph (Bidirectional)
    _graph = {};
    for (var row in results[1]) {
      final edge = GraphEdge.fromMap(row);
      
      // Forward
      _graph.putIfAbsent(edge.fromNodeId, () => []).add(edge);

      // Reverse (Essential for better connectivity)
      final reverseEdge = GraphEdge(
        fromNodeId: edge.toNodeId,
        toNodeId: edge.fromNodeId,
        routeId: edge.routeId,
        timeSeconds: edge.timeSeconds,
        distanceKm: edge.distanceKm,
      );
      _graph.putIfAbsent(edge.toNodeId, () => []).add(reverseEdge);
    }

    _fareRules = results[3].map((r) => BusFareRule.fromMap(r)).toList();
    _isInitialized = true;
    debugPrint("✅ Bus Service Ready!");
  }

  // --- 🔥 SMART SEARCH FUNCTION (UPDATED) ---
  Future<RouteResult?> findBusRoute(
    String sourceName, 
    String destName, {
    BusRoutePreference preference = BusRoutePreference.fastest, // 🔥 New parameter
  }) async {
    if (!_isInitialized) await initialize();

    String? sourceId = _findStopIdByName(sourceName);
    String? destId = _findStopIdByName(destName);

    if (sourceId == null || destId == null) return null;

    // 🟢 Attempt 1: Direct/Strict Search (with preference)
    var strictRoute = _findPathWithPenalty(sourceId, destId, preference);
    if (strictRoute != null) return strictRoute;

    // 🔴 Attempt 2: Smart Walk Search (Walking Connections)
    // Agar direct connection nahi mila, to Source aur Dest ke aas paas ke stops check karo
    debugPrint("⚠️ Direct route failed. Attempting Smart Walk Search...");
    return _findPathWithWalking(sourceId, destId, preference); // 🔥 Pass preference
  }

  String? _findStopIdByName(String name) {
    return _stopNames.entries
        .firstWhereOrNull((e) => e.value.toLowerCase() == name.toLowerCase())
        ?.key;
  }

  // --- LOGIC 2: NEARBY WALK SEARCH (UPDATED) ---
  RouteResult? _findPathWithWalking(
      String startId, 
      String endId, 
      BusRoutePreference preference, // 🔥 New parameter
  ) {
    // 1. Find stops within 800m of Source
    final startNeighbors = _getNearbyStops(startId, 0.8);
    // 2. Find stops within 800m of Destination
    final endNeighbors = _getNearbyStops(endId, 0.8);

    RouteResult? bestRoute;
    double minTotalTime = double.infinity;

    // Sabse best combination dhoondo
    // (Optimization: Limit loop to top 5 closest stops to avoid lag)
    for (var startNode in startNeighbors.take(5)) {
      for (var endNode in endNeighbors.take(5)) {
        
        // Is combination ke liye route dhoondo (pass preference)
        var route = _findPathWithPenalty(startNode.id, endNode.id, preference);
        
        if (route != null) {
          // Walk Time add karo (Source -> StartNode) + (EndNode -> Dest)
          // Average speed: 1.2 m/s (~12 min for 1km)
          double walkTimeSec = (startNode.distance + endNode.distance) * 1000 / 1.2;
          
          double totalTripTime = route.totalTimeMin * 60 + walkTimeSec;

          if (totalTripTime < minTotalTime) {
            minTotalTime = totalTripTime;
            
            // Route mein "Walk" instructions inject karo
            bestRoute = _injectWalkingSteps(route, startId, startNode, endId, endNode);
          }
        }
      }
    }
    return bestRoute;
  }

  List<_NearbyNode> _getNearbyStops(String centerId, double radiusKm) {
    final center = _stopLocations[centerId];
    if (center == null) return [];

    List<_NearbyNode> nearby = [];
    _stopLocations.forEach((id, loc) {
      if (id == centerId) {
        nearby.add(_NearbyNode(id, 0.0)); // Self
        return;
      }
      double dist = _calculateDistance(center.lat, center.lon, loc.lat, loc.lon);
      if (dist <= radiusKm) {
        nearby.add(_NearbyNode(id, dist));
      }
    });

    nearby.sort((a, b) => a.distance.compareTo(b.distance));
    return nearby;
  }

  // Haversine Formula for Distance
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  RouteResult _injectWalkingSteps(RouteResult original, String actualStartId, _NearbyNode startNode, String actualEndId, _NearbyNode endNode) {
    List<RouteStation> newPath = [];

    // Add Start Walk if distance > 50m
    if (startNode.distance > 0.05) {
      newPath.add(RouteStation(
        id: actualStartId,
        name: _stopNames[actualStartId] ?? "Start",
        lineName: "Walk",
        lineCode: "WALK",
        lineColor: Colors.grey,
        time: "Start",
        type: StationType.source,
        instruction: "Walk ${(startNode.distance * 1000).toInt()}m to ${_stopNames[startNode.id]}"
      ));
    }

    // Add Original Path (Modify first/last to normal/interchange)
    for (var step in original.path) {
      // Logic to merge steps can be added here
      newPath.add(step);
    }

    // Add End Walk if distance > 50m
    if (endNode.distance > 0.05) {
      var last = newPath.last;
      newPath.add(RouteStation(
        id: actualEndId,
        name: _stopNames[actualEndId] ?? "Destination",
        lineName: "Walk",
        lineCode: "WALK",
        lineColor: Colors.grey,
        time: "End",
        type: StationType.destination,
        instruction: "Walk ${(endNode.distance * 1000).toInt()}m to Destination"
      ));
    }

    return RouteResult(
      path: newPath,
      totalFare: original.totalFare,
      totalTimeMin: (original.totalTimeMin + ((startNode.distance + endNode.distance) * 15)).toInt(), // Approx walk time add
      totalStops: original.totalStops,
      totalDistance: original.totalDistance + startNode.distance + endNode.distance,
      pathLineIds: original.pathLineIds
    );
  }

  // --- CORE DIJKSTRA (UPDATED WITH PREFERENCE) ---
  RouteResult? _findPathWithPenalty(
      String startId, 
      String endId, 
      BusRoutePreference preference, // 🔥 New parameter
  ) {
    final pq = PriorityQueue<_State>((a, b) => a.cost.compareTo(b.cost));
    final minCost = <String, double>{};
    final previous = <String, GraphEdge>{};

    pq.add(_State(startId, 0.0, null));
    minCost[startId] = 0.0;

    // 🔥 LOGIC CHANGE: Dynamic Penalty
    // Agar 'Less Interchange' hai to penalty itni badha do ki algo dar jaye bus change karne se
    final double transferPenalty = preference == BusRoutePreference.fastest ? 600.0 : 5000.0;

    while (pq.isNotEmpty) {
      final current = pq.removeFirst();

      if (current.cost > (minCost[current.nodeId] ?? double.infinity)) continue;
      if (current.nodeId == endId) break;

      final edges = _graph[current.nodeId] ?? [];

      for (final edge in edges) {
        double newCost = current.cost + edge.timeSeconds;
        if (current.lastRouteId != null && current.lastRouteId != edge.routeId) {
          newCost += transferPenalty; // 🔥 Apply dynamic penalty
        }

        if (newCost < (minCost[edge.toNodeId] ?? double.infinity)) {
          minCost[edge.toNodeId] = newCost;
          previous[edge.toNodeId] = edge;
          pq.add(_State(edge.toNodeId, newCost, edge.routeId));
        }
      }
    }

    if (!previous.containsKey(endId)) return null;
    return _constructResult(previous, startId, endId);
  }

  RouteResult _constructResult(Map<String, GraphEdge> previous, String startId, String endId) {
    final edgesTrace = <GraphEdge>[];
    String curr = endId;
    while (curr != startId) {
      final edge = previous[curr];
      if (edge == null) break;
      edgesTrace.insert(0, edge);
      curr = edge.fromNodeId;
    }

    if (edgesTrace.isEmpty) return RouteResult.fromSeconds(path: [], totalFare: 0, totalTimeSeconds: 0, totalStops: 0, totalDistance: 0, pathLineIds: []);

    final path = <RouteStation>[];
    double totalDist = 0;
    int totalTime = 0;

    // Initial Source
    path.add(RouteStation(
      id: startId,
      name: _stopNames[startId] ?? "Start",
      lineName: "Start",
      lineCode: edgesTrace.first.routeId,
      lineColor: Colors.orange,
      time: "Now",
      type: StationType.source,
    ));

    for (int i = 0; i < edgesTrace.length; i++) {
      final edge = edgesTrace[i];
      totalDist += edge.distanceKm;
      totalTime += edge.timeSeconds;

      final busInfo = _routeInfoMap[edge.routeId];
      final stopName = _stopNames[edge.toNodeId] ?? "Unknown Stop";

      bool isInterchange = false;
      String? instruction;
      
      if (i < edgesTrace.length - 1) {
        if (edgesTrace[i+1].routeId != edge.routeId) {
          isInterchange = true;
          final nextBus = _routeInfoMap[edgesTrace[i+1].routeId];
          String busNo = nextBus?.busNumber ?? "Bus";
          instruction = "Switch to Bus $busNo";
          totalTime += 300; 
        }
      }

      path.add(RouteStation(
        id: edge.toNodeId,
        name: stopName,
        lineName: busInfo?.busNumber ?? "Bus",
        lineCode: edge.routeId,
        lineColor: isInterchange ? Colors.redAccent : Colors.orange,
        time: "${(totalTime / 60).ceil()} min",
        type: i == edgesTrace.length - 1 ? StationType.destination : (isInterchange ? StationType.interchange : StationType.normal),
        instruction: instruction
      ));
    }

    return RouteResult.fromSeconds(
      path: path,
      totalFare: _calculateFare(totalDist),
      totalTimeSeconds: totalTime,
      totalStops: edgesTrace.length,
      totalDistance: double.parse(totalDist.toStringAsFixed(1)),
      pathLineIds: edgesTrace.map((e) => e.routeId).toSet().toList(),
    );
  }

  int _calculateFare(double distance) {
    if (_fareRules.isEmpty) return 10;
    for (var rule in _fareRules) {
      if (distance >= rule.minKm && distance < rule.maxKm) return rule.price;
    }
    return _fareRules.last.price;
  }
}

class _State {
  final String nodeId;
  final double cost;
  final String? lastRouteId;
  _State(this.nodeId, this.cost, this.lastRouteId);
}

class _NearbyNode {
  final String id;
  final double distance;
  _NearbyNode(this.id, this.distance);
}

class LatLng {
  final double lat;
  final double lon;
  LatLng(this.lat, this.lon);
}