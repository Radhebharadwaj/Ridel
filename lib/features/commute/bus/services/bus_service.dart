import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ridel/features/commute/shared/services/database_helper.dart';
import 'package:ridel/features/commute/shared/models/route_models.dart';

import 'package:collection/collection.dart';

enum BusRoutePreference { fastest, lessInterchange }

class BusService {
  static final BusService _instance = BusService._internal();
  factory BusService() => _instance;
  BusService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Map<String, String> _stopNames = {};
  bool _isInitialized = false;


  Future<void> initialize() async {
    if (_isInitialized) return;
    debugPrint("🚌 BusService: Loading lightweight Stop Names only...");

    // 🚀 LOBOTOMIZED: Only loading stops for UI dropdowns
    final results = await _dbHelper.getAllBusStops();
    for (var row in results) {
      String id = row['stop_id'].toString();
      _stopNames[id] = row['stop_name'].toString();
    }
    
    _isInitialized = true;
    debugPrint("✅ Bus Service Ready (Cloudflare Backend Mode)!");
  }

  Future<RouteResult?> findBusRoute(
    String sourceName,
    String destName, {
    BusRoutePreference preference = BusRoutePreference.fastest,
  }) async {
    if (!_isInitialized) await initialize();

    String? sourceId = _findStopIdByName(sourceName);
    String? destId = _findStopIdByName(destName);

    if (sourceId == null || destId == null) {
      return null;
    }

    try {
      final url = Uri.https('ridel.ridel.workers.dev', '/api/bus/route', {'start': sourceId, 'end': destId});
      
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      debugPrint("Raw Worker Response: ${response.statusCode}");

      if (response.statusCode == 200 || (response.statusCode >= 400 && response.statusCode < 500)) {
        if (response.body.trim().isEmpty) {
          throw RouteNotFoundException("Server returned ${response.statusCode} with no data");
        }
        try {
          final data = jsonDecode(response.body);
          if (data['status'] == 'error' || response.statusCode >= 400) {
            throw RouteNotFoundException(data['message'] ?? 'No route found between these stops.');
          }
          if (data['status'] == 'success' || data.containsKey('route_steps')) {
            return _parseServerResponse(data);
          }
        } catch (e) {
          if (e is RouteNotFoundException) rethrow;
          if (e is TypeError || e is FormatException) rethrow;
          if (response.statusCode >= 400 && response.statusCode < 500) {
            throw RouteNotFoundException("No route found between these stops.");
          }
        }
        throw Exception("Unknown server response");
      } else {
        debugPrint("❌ Backend returned ${response.statusCode}");
        throw Exception("Network error. Please check your internet connection.");
      }
    } on TimeoutException catch (_) {
      throw Exception("Network error. Please check your internet connection.");
    } on SocketException catch (_) {
      throw Exception("Network error. Please check your internet connection.");
    } on RouteNotFoundException catch (_) {
      rethrow;
    } catch (e) {
      debugPrint('JSON PARSING ERROR: $e');
      if (e is TypeError || e is FormatException) {
        throw Exception("Data mapping error: $e");
      }
      if (e.toString().contains('No route found') || e.toString().contains('Unknown server response')) {
        rethrow;
      }
      debugPrint("❌ Network error connecting to Cloudflare Worker: $e");
      throw Exception("Network error. Please check your internet connection.");
    }
  }

  RouteResult _parseServerResponse(Map<String, dynamic> data) {
    final List<dynamic> routeSteps = data['route_steps'] ?? [];
    final int totalTimeMinutes = int.tryParse(data['total_time_minutes'].toString()) ?? 0;
    // totalTransfers is unused in the current RouteResult model
    final int totalFareInr = int.tryParse(data['total_fare_inr'].toString()) ?? 0;

    final path = routeSteps.map((step) {
      StationType type = StationType.normal;
      final String action = step['action']?.toString().toUpperCase() ?? '';
      
      if (action == 'BOARD') {
        type = StationType.source;
      } else if (action == 'ALIGHT') {
        type = StationType.destination;
      } else if (action == 'TRANSFER') {
        type = StationType.interchange;
      }

      return RouteStation(
        id: step['stop_name'] ?? '',
        name: step['stop_name'] ?? '',
        lineName: step['bus_number'] ?? '',
        lineCode: step['bus_number'] ?? '',
        lineColor: Colors.orange, // Default for bus
        time: "0", 
        type: type,
        instruction: action,
        lat: double.tryParse(step['lat'].toString()) ?? 0.0,
        lon: double.tryParse(step['lng'].toString()) ?? 0.0,
        busNumber: step['bus_number'] ?? '',
        frequency: "0",
      );
    }).toList();

    return RouteResult.fromSeconds(
      path: path,
      totalFare: totalFareInr, 
      totalTimeSeconds: totalTimeMinutes * 60,
      totalStops: routeSteps.length,
      totalDistance: 0.0,
      pathLineIds: path.map((s) => s.lineCode).toSet().toList(),
    );
  }

  String? _findStopIdByName(String name) {
    return _stopNames.entries
        .firstWhereOrNull((e) => e.value.toLowerCase() == name.toLowerCase())
        ?.key;
  }
}
