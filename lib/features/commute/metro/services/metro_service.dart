import 'dart:async';
import 'dart:collection';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import 'package:ridel/features/commute/metro/models/metro_models.dart'; 
import 'package:ridel/features/commute/shared/models/route_models.dart'; 
import 'package:ridel/features/commute/shared/services/database_helper.dart'; 

class MetroService {
  static final MetroService _instance = MetroService._internal();
  factory MetroService() => _instance;
  MetroService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  // In-memory Data
  Map<String, List<GraphEdge>> _graph = {};
  Map<String, Stop> _stops = {};
  Map<String, MetroRoute> _routes = {};
  Map<String, String> _nameToIdMap = {};
  List<FareConfig> _fareRules = [];
  Map<String, List<PlatformInfo>> _platformCache = {};

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('🚇 MetroService: Initializing & Loading Data...');
    
    final results = await Future.wait([
      _dbHelper.getAllStopsDetailed(),
      _dbHelper.getAllLines(), 
      _dbHelper.getAllGraphEdges(),
      _dbHelper.getFareConfig(),
      _dbHelper.getAllPlatforms(),
    ]);

    // 🔥 THE REGEX RULE: ID must contain at least one alphabet character (A-Z)
    final hasLetterRegex = RegExp(r'[a-zA-Z]');

    // 1. Stops (Filtering out pure numeric Bus Stops)
    _stops = {};
    _nameToIdMap = {};
    for (var row in results[0]) {
      final stop = Stop.fromMap(row);
      final cleanId = stop.stopId.trim(); 
      
      // Agar ID me alphabet hai, tabhi allow karo
      if (hasLetterRegex.hasMatch(cleanId)) {
        _stops[cleanId] = stop;
        _nameToIdMap[stop.stopName.toLowerCase().trim()] = cleanId;
      }
    }

    // 2. Routes
    _routes = {
      for (var row in results[1])
        row['route_id'].toString(): MetroRoute.fromMap(row)
    };

    // 3. Graph Build (Strict Filtering)
    _graph = {};

    for (var row in results[2]) {
      final edge = GraphEdge.fromMap(row);
      final fromId = edge.fromNodeId.trim();
      final toId = edge.toNodeId.trim();

      // Check: Dono IDs me alphabet hona chahiye (Bus edges blocked)
      if (!hasLetterRegex.hasMatch(fromId) || !hasLetterRegex.hasMatch(toId)) {
        continue; 
      }

      // Check: Kya ye stops humari verified Metro list me hain?
      if (!_stops.containsKey(fromId) || !_stops.containsKey(toId)) {
        continue;
      }

      _addEdge(fromId, edge);
      
      final reverseEdge = GraphEdge(
        fromNodeId: toId,
        toNodeId: fromId,
        routeId: edge.routeId,
        timeSeconds: edge.timeSeconds,
        distanceKm: edge.distanceKm,
      );
      _addEdge(toId, reverseEdge);
    }

    _fareRules = results[3].map((r) => FareConfig.fromMap(r)).toList();
    _platformCache = groupBy(
      results[4].map((r) => PlatformInfo.fromMap(r)),
      (p) => p.stopId.trim(),
    );

    _isInitialized = true;
    debugPrint("✅ Metro Logic Ready. Verified Metro Stations: ${_stops.length}");
  }

  void _addEdge(String from, GraphEdge edge) {
      _graph.putIfAbsent(from, () => []).add(edge);
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) await initialize();
  }

  // ==================== STATION DETAILS FETCHER ====================

  Future<Map<String, dynamic>> getStationFullDetails(String stopId) async {
    await _ensureInitialized();
    final results = await Future.wait([
      _dbHelper.getGatesForStation(stopId),
      _dbHelper.getParkingForStation(stopId),
      _dbHelper.getFacilitiesForStation(stopId),
      _dbHelper.getPlatformsForStation(stopId),
    ]);
    return {
      'gates': results[0],
      'parking': results[1],
      'facilities': results[2], 
      'platforms': results[3],
    };
  }

  // ==================== PATH FINDING ====================

  Future<RouteResult?> findBestRoute(String sourceName, String destName) async {
    await _ensureInitialized();
    String? sourceId = _nameToIdMap[sourceName.toLowerCase().trim()];
    String? destId = _nameToIdMap[destName.toLowerCase().trim()];

    if (sourceId == null || destId == null) {
      debugPrint("❌ Stop not found in verified Metro list!");
      return null;
    }
    return _dijkstra(sourceId, destId);
  }

  RouteResult? _dijkstra(String sourceId, String destId) {
    final costs = <String, double>{};
    final previous = <String, GraphEdge?>{};
    final arrivedOnRoute = <String, String?>{};
    
    final pq = PriorityQueue<(String, double)>((a, b) => a.$2.compareTo(b.$2));

    costs[sourceId] = 0.0;
    arrivedOnRoute[sourceId] = null;
    pq.add((sourceId, 0.0));

    while (pq.isNotEmpty) {
      final (currentId, currentCost) = pq.removeFirst();
      
      if (currentCost > (costs[currentId] ?? double.infinity)) continue;
      if (currentId == destId) break;

      final edges = _graph[currentId] ?? [];
      String? currentLine = arrivedOnRoute[currentId];

      for (final edge in edges) {
        double addedCost = edge.timeSeconds.toDouble();
        
        // 🔥 SMART PENALTY: Agar train badal rahe ho (aur wo paidal rasta nahi hai)
        if (currentLine != null && currentLine != edge.routeId && edge.routeId != 'WALK' && currentLine != 'WALK') {
           addedCost += 900; 
        }

        final newCost = currentCost + addedCost;
        
        if (newCost < (costs[edge.toNodeId] ?? double.infinity)) {
          costs[edge.toNodeId] = newCost;
          previous[edge.toNodeId] = edge;
          arrivedOnRoute[edge.toNodeId] = edge.routeId;
          pq.add((edge.toNodeId, newCost));
        }
      }
    }

    if (!previous.containsKey(destId)) return null;

    final pathEdges = <GraphEdge>[];
    String? current = destId;
    while (current != null && current != sourceId) {
      final edge = previous[current];
      if (edge == null) break;
      pathEdges.insert(0, edge);
      current = edge.fromNodeId;
    }

    return _buildRouteResult(pathEdges, sourceId);
  }

  // ==================== RESULT BUILDER ====================

  RouteResult _buildRouteResult(List<GraphEdge> edges, String sourceId) {
    if (edges.isEmpty) {
       return RouteResult.fromSeconds(path: [], totalFare: 0, totalTimeSeconds: 0, totalStops: 0, totalDistance: 0, pathLineIds: []);
    }

    final path = <RouteStation>[];
    double totalDist = 0.0;
    int displayTimeSeconds = 0;

    final startStop = _stops[sourceId]!;
    final firstEdge = edges.first;
    final firstRoute = _routes[firstEdge.routeId] ?? MetroRoute(routeId: firstEdge.routeId, routeName: 'Walking Interchange', routeColor: Colors.grey);
    
    String? sourcePlatform = _findCorrectPlatform(
        stationId: sourceId, 
        nextStationId: firstEdge.toNodeId, 
        lineId: firstEdge.routeId
    );

    path.add(RouteStation(
      id: startStop.stopId,
      name: startStop.stopName,
      lineName: firstRoute.routeName,
      lineCode: firstRoute.routeId,
      lineColor: firstRoute.routeColor,
      time: _formatTime(0),
      type: StationType.source,
      instruction: sourcePlatform, 
    ));

    for (int i = 0; i < edges.length; i++) {
      final edge = edges[i];
      final toStop = _stops[edge.toNodeId]!;
      
      MetroRoute effectiveRoute = _routes[edge.routeId] ?? 
          MetroRoute(routeId: edge.routeId, routeName: edge.routeId == 'WALK' ? 'Walking Interchange' : 'Line', routeColor: Colors.grey);
      
      totalDist += edge.distanceKm;
      displayTimeSeconds += edge.timeSeconds;

      StationType type = StationType.normal;
      String? instruction;
      
      if (i < edges.length - 1) {
        final nextEdge = edges[i + 1];
        
        // _buildRouteResult ke andar interchange logic me:
        if (nextEdge.routeId != edge.routeId) {
            type = StationType.interchange;
            
            String targetLineId = nextEdge.routeId;
            if (targetLineId == 'WALK' && i + 2 < edges.length) {
                targetLineId = edges[i + 2].routeId;
            }

            final targetRoute = _routes[targetLineId];
            if (targetRoute != null) effectiveRoute = targetRoute;
            
            // 🔥 SMART WALK UI FIX: Agar next edge WALK hai, to aage wale station ka naam dikhao!
            if (nextEdge.routeId == 'WALK') {
               final walkTargetStop = _stops[nextEdge.toNodeId]!; // Sector 51 nikal ke aayega
               instruction = '🚶 Exit & Walk to ${walkTargetStop.stopName} for ${targetRoute?.routeName ?? "Next Line"}';
            } else {
               instruction = '🔄 Change for ${targetRoute?.routeName ?? "Next Line"}';
            }
            
            String? plat = _findCorrectPlatform(
              stationId: edge.toNodeId, nextStationId: nextEdge.toNodeId, lineId: nextEdge.routeId
            );
            
            if (plat != null) instruction = "$instruction • $plat";
        }
      } else {
        type = StationType.destination;
      }

      path.add(RouteStation(
        id: toStop.stopId,
        name: toStop.stopName,
        lineName: effectiveRoute.routeName,
        lineCode: effectiveRoute.routeId,
        lineColor: effectiveRoute.routeColor,
        time: _formatTime(displayTimeSeconds),
        type: type,
        instruction: instruction,
      ));
    }

    int fare = 10;
    if (_fareRules.isNotEmpty) {
       final rule = _fareRules.firstWhere(
        (r) => totalDist >= r.minKm && totalDist < r.maxKm,
        orElse: () => _fareRules.last,
      );
      fare = rule.priceNormal;
    }

    return RouteResult.fromSeconds(
      path: path,
      totalFare: fare,
      totalTimeSeconds: displayTimeSeconds,
      totalStops: edges.length,
      totalDistance: double.parse(totalDist.toStringAsFixed(1)),
      pathLineIds: edges.map((e) => e.routeId).toSet().toList(),
    );
  }

  // ==================== PLATFORM LOGIC ====================

  String? _findCorrectPlatform({
    required String stationId, 
    required String nextStationId, 
    required String lineId
  }) {
    if (lineId == 'WALK') return null; 

    final platforms = _platformCache[stationId];
    if (platforms == null || platforms.isEmpty) return null;

    for (final plat in platforms) {
      String towards = plat.towardsStationCode.trim();
      if (towards.isEmpty) continue;

      if (towards == nextStationId) return _formatPlat(plat.platformName);

      List<String>? path = _findPathOnLine(
        start: stationId, 
        target: towards, 
        lineId: lineId
      );

      if (path != null && path.length > 1) {
        if (path[1] == nextStationId) return _formatPlat(plat.platformName);
      }
    }
    return null; 
  }

  List<String>? _findPathOnLine({
    required String start, 
    required String target, 
    required String lineId
  }) {
    final queue = Queue<(String, List<String>)>();
    queue.add((start, [start]));
    final visited = <String>{start};
    int limit = 100;

    while (queue.isNotEmpty) {
      if (limit-- <= 0) break;

      final (current, path) = queue.removeFirst();
      if (current == target) return path;

      final edges = _graph[current];
      if (edges == null) continue;

      for (var edge in edges) {
        if (edge.routeId != lineId) continue;
        if (!visited.contains(edge.toNodeId)) {
          visited.add(edge.toNodeId);
          queue.add((edge.toNodeId, List<String>.from(path)..add(edge.toNodeId)));
        }
      }
    }
    return null; 
  }

  String _formatPlat(String rawName) {
     final match = RegExp(r'(\d+)').firstMatch(rawName);
     return match != null ? "Platform ${match.group(0)}" : rawName;
  }

  String _formatTime(int seconds) {
    final now = DateTime.now().add(Duration(seconds: seconds));
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${now.hour >= 12 ? 'PM' : 'AM'}';
  }
}