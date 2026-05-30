import 'dart:async';
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

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('🚇 MetroService: Initializing & Loading Data...');

    final results = await Future.wait([
      _dbHelper.getAllStopsDetailed(),
      _dbHelper.getAllLines(),
      _dbHelper.getAllGraphEdges(),
      _dbHelper.getFareConfig(0),
    ]);

    final hasLetterRegex = RegExp(r'[a-zA-Z]');

    // 1. Stops
    _stops = {};
    _nameToIdMap = {};
    for (var row in results[0]) {
      final stop = Stop.fromMap(row);
      final cleanId = stop.stopId.trim();

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

    // 3. Graph Build (Smart Bidirectional Fix)
    _graph = {};

    // PASS 1: Add original edges from Database
    for (var row in results[2]) {
      final edge = GraphEdge.fromMap(row);
      final fromId = edge.fromNodeId.trim();
      final toId = edge.toNodeId.trim();

      if (!hasLetterRegex.hasMatch(fromId) || !hasLetterRegex.hasMatch(toId)) {
        continue;
      }
      if (!_stops.containsKey(fromId) || !_stops.containsKey(toId)) {
        continue;
      }

      _addEdge(fromId, edge);
    }

    // PASS 2: Find & Add Missing Reverse Edges (Safely handling Interchanges/Walks)
    final List<GraphEdge> missingReverseEdges = [];

    for (final fromId in _graph.keys) {
      for (final edge in _graph[fromId]!) {
        final toId = edge.toNodeId;

        bool reverseExists = false;
        if (_graph.containsKey(toId)) {
          for (final revEdge in _graph[toId]!) {
            if (revEdge.toNodeId == fromId && revEdge.routeId == edge.routeId) {
              reverseExists = true;
              break;
            }
          }
        }

        // Agar reverse edge DB me nahi hai (e.g. WALK path), toh manual connect karo WITHOUT platform
        if (!reverseExists) {
          missingReverseEdges.add(GraphEdge(
            fromNodeId: toId,
            toNodeId: fromId,
            routeId: edge.routeId,
            timeSeconds: edge.timeSeconds,
            distanceKm: edge.distanceKm,
            platformName: null, // 🔥 SAFETY: Fake routes par no platform info!
          ));
        }
      }
    }

    // Inject the missing reverse edges back into the graph
    for (final safeEdge in missingReverseEdges) {
      _addEdge(safeEdge.fromNodeId, safeEdge);
    }

    // 🚀 FARE RULES LOAD KIYE GAYE
    _fareRules = results[3].map((r) => FareConfig.fromMap(r)).toList();

    // 🔥 YE PRINT CLEAR KAR DEGA KI BACKEND SE DATA AAYA YA NAHI
    debugPrint("🔥🔥 METRO FARE RULES LOADED: ${_fareRules.length}");

    _isInitialized = true;
    debugPrint(
        "✅ Metro Logic Ready. Verified Metro Stations: ${_stops.length}");
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

        // SMART PENALTY
        if (currentLine != null &&
            currentLine != edge.routeId &&
            edge.routeId != 'WALK' &&
            currentLine != 'WALK') {
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
      return RouteResult.fromSeconds(
          path: [],
          totalFare: 0,
          totalTimeSeconds: 0,
          totalStops: 0,
          totalDistance: 0,
          pathLineIds: []);
    }

    final path = <RouteStation>[];
    double totalDist = 0.0;
    int displayTimeSeconds = 0;

    final startStop = _stops[sourceId]!;
    final firstEdge = edges.first;
    final firstRoute = _routes[firstEdge.routeId] ??
        MetroRoute(
            routeId: firstEdge.routeId,
            routeName: 'Walking Interchange',
            routeColor: Colors.grey);

    // 🔥 THE START FIX: Agar pehli edge by chance WALK hui toh aage wali train ka platform lo
    String? sourcePlatform;
    for (var e in edges) {
      if (e.routeId != 'WALK') {
        sourcePlatform = e.platformName;
        break;
      }
    }

    path.add(RouteStation(
      id: startStop.stopId,
      name: startStop.stopName,
      lineName: firstRoute.routeName,
      lineCode: firstRoute.routeId,
      lineColor: firstRoute.routeColor,
      time: _formatTime(0),
      type: StationType.source,
      instruction: sourcePlatform,
      lat: startStop.stopLat, // 🚀 ADDED LATITUDE
      lon: startStop.stopLon, // 🚀 ADDED LONGITUDE
    ));

    for (int i = 0; i < edges.length; i++) {
      final edge = edges[i];
      final toStop = _stops[edge.toNodeId]!;

      MetroRoute effectiveRoute = _routes[edge.routeId] ??
          MetroRoute(
              routeId: edge.routeId,
              routeName:
                  edge.routeId == 'WALK' ? 'Walking Interchange' : 'Line',
              routeColor: Colors.grey);

      totalDist += edge.distanceKm;
      displayTimeSeconds += edge.timeSeconds;

      StationType type = StationType.normal;
      String? instruction;

      if (i < edges.length - 1) {
        final nextEdge = edges[i + 1];

        if (nextEdge.routeId != edge.routeId) {
          type = StationType.interchange;

          String targetLineId = nextEdge.routeId;
          if (targetLineId == 'WALK' && i + 2 < edges.length) {
            targetLineId = edges[i + 2].routeId;
          }

          final targetRoute = _routes[targetLineId];
          if (targetRoute != null) effectiveRoute = targetRoute;

          if (nextEdge.routeId == 'WALK') {
            final walkTargetStop = _stops[nextEdge.toNodeId]!;
            instruction =
                '🚶 Exit & Walk to ${walkTargetStop.stopName} for ${targetRoute?.routeName ?? "Next Line"}';
          } else {
            instruction =
                '🔄 Change for ${targetRoute?.routeName ?? "Next Line"}';
          }

          // 🔥 THE WALK FIX: Agar nextEdge WALK hai, toh uske aage wali asli train ka platform dhoondho!
          String? plat;
          if (nextEdge.routeId == 'WALK' && i + 2 < edges.length) {
            plat = edges[i + 2].platformName;
          } else {
            plat = nextEdge.platformName;
          }

          if (plat != null && plat.trim().isNotEmpty && plat != "null") {
            instruction = "$instruction • $plat";
          }
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
        lat: toStop.stopLat, // 🚀 ADDED LATITUDE
        lon: toStop.stopLon, // 🚀 ADDED LONGITUDE
      ));
    }

    int fare = 10;

    if (_fareRules.isNotEmpty && edges.isNotEmpty) {
      // Step 1: Detect Agency (Agar route me Aqua line hai, toh NMRC rules, warna DMRC)
      bool isNmrc = edges.any((e) => e.routeId.toUpperCase().contains('AQUA'));
      String targetAgency = isNmrc ? 'NMRC' : 'DMRC';

      // Step 2: Match Distance AND Agency
      final rule = _fareRules.firstWhere(
        (r) =>
            totalDist >= r.minKm &&
            totalDist <= r.maxKm &&
            r.agencyId.toUpperCase() == targetAgency, // 🔥 STRICT AGENCY MATCH
        orElse: () {
          // Fallback: Agar distance match na ho, toh kam se kam us agency ka default fare le
          return _fareRules.firstWhere(
              (r) => r.agencyId.toUpperCase() == targetAgency,
              orElse: () => _fareRules.first // Absolute fallback
              );
        },
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

  // ==================== HELPER METHODS ====================

  String _formatTime(int seconds) {
    final now = DateTime.now().add(Duration(seconds: seconds));
    final hour =
        now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${now.hour >= 12 ? 'PM' : 'AM'}';
  }
}
