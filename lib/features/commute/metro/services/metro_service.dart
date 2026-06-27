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

  static const int interchangePenaltyMinutes = 6;

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

  int _levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var v0 = List<int>.generate(b.length + 1, (i) => i);
    var v1 = List<int>.filled(b.length + 1, 0);
    for (int i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        int cost = (a[i] == b[j]) ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((min, e) => min < e ? min : e);
      }
      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[b.length];
  }

  String? _findClosestStationId(String inputName) {
    final query = inputName.toLowerCase().trim();
    if (_nameToIdMap.containsKey(query)) return _nameToIdMap[query];

    String? bestMatchId;
    double bestScore = 0.0;
    for (var entry in _nameToIdMap.entries) {
      final name = entry.key;
      final dist = _levenshteinDistance(query, name);
      final maxLength = query.length > name.length ? query.length : name.length;
      final score = 1.0 - (dist / maxLength);
      if (score > bestScore) {
        bestScore = score;
        bestMatchId = entry.value;
      }
    }

    if (bestScore > 0.6) {
      debugPrint("Fuzzy match: $query -> bestScore: $bestScore");
      return bestMatchId;
    }
    return null;
  }

  // ==================== PATH FINDING ====================

  bool _isInterchange(String nodeId) {
    final edges = _graph[nodeId] ?? [];
    final uniqueNodes = <String>{};
    final uniqueRoutes = <String>{};

    for (final edge in edges) {
      uniqueNodes.add(edge.toNodeId);
      uniqueRoutes.add(edge.routeId);
    }

    return uniqueNodes.length >= 3 && uniqueRoutes.length > 1;
  }


  Future<List<RouteResult>> findBestRoute(String sourceName, String destName) async {
    await _ensureInitialized();
    String? sourceId = _findClosestStationId(sourceName);
    String? destId = _findClosestStationId(destName);

    if (sourceId == null || destId == null) {
      debugPrint("❌ Stop not found in verified Metro list!");
      return [];
    }
    
    // The user requested explicit 5-minute penalty (300 seconds)
    const int interchangePenaltySeconds = 300;

    // Run 1: Absolute Fastest Route
    RouteResult? fastestRoute = _dijkstra(sourceId, destId, interchangePenaltySeconds);
    
    // Run 2: Fewest Interchanges (Heavy Penalty)
    RouteResult? fewestChangesRoute = _dijkstra(sourceId, destId, 30 * 60);

    final results = <RouteResult>[];
    if (fastestRoute != null) results.add(fastestRoute);

    if (fewestChangesRoute != null) {
      bool isDifferent = fastestRoute?.pathLineIds.join(',') != fewestChangesRoute.pathLineIds.join(',');

      if (isDifferent) {
        results.add(fewestChangesRoute);
      }
    }

    if (results.length < 2 && fastestRoute != null) {
      // Edge-penalty approach: Penalize the edges of the first route
      final Set<String> penaltyEdges = {};
      for (int i = 0; i < fastestRoute.path.length - 1; i++) {
         penaltyEdges.add('${fastestRoute.path[i].id}->${fastestRoute.path[i+1].id}');
      }
      
      RouteResult? altRoute = _dijkstra(sourceId, destId, interchangePenaltySeconds, penaltyEdges: penaltyEdges);
      if (altRoute != null && altRoute.pathLineIds.join(',') != fastestRoute.pathLineIds.join(',')) {
        if (altRoute.totalTimeMin <= fastestRoute.totalTimeMin + 180) {
          results.add(altRoute);
        }
      }
    }

    if (results.isEmpty) {
      throw RouteNotFoundException("No route found between these stops.");
    }

    // SMART SORT LOGIC
    results.sort((a, b) {
      int timeDiff = (a.totalTimeMin - b.totalTimeMin).abs();
      if (timeDiff <= 10) {
        int aTransfers = a.path.where((s) => s.type == StationType.interchange).length;
        int bTransfers = b.path.where((s) => s.type == StationType.interchange).length;
        if (aTransfers != bTransfers) {
          return aTransfers.compareTo(bTransfers);
        }
      }
      return a.totalTimeMin.compareTo(b.totalTimeMin);
    });

    return results;
  }

  RouteResult? _dijkstra(String sourceId, String destId, int interchangePenaltySeconds, {Set<String>? penaltyNodes, Set<String>? penaltyEdges}) {
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

        // 🚀 DYNAMIC INTERCHANGE GUARD
        if (currentLine != null && currentLine != edge.routeId) {
          if (!_isInterchange(currentId)) {
            continue;
          }
        }

        // SMART PENALTY
        if (currentLine != null &&
            currentLine != edge.routeId &&
            edge.routeId != 'WALK' &&
            currentLine != 'WALK') {
          addedCost += interchangePenaltySeconds;
        }

        // AVOIDANCE PENALTY FOR ALTERNATE ROUTE
        if (penaltyNodes != null && penaltyNodes.contains(edge.toNodeId) && edge.toNodeId != destId) {
          addedCost += 100000.0; // Massive weight to force a different path
        }

        if (penaltyEdges != null && penaltyEdges.contains('$currentId->${edge.toNodeId}')) {
          addedCost += 100000.0; // Heavily penalize the edge to find next best path
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
