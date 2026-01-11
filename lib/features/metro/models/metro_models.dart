import 'dart:convert';
import 'package:flutter/material.dart';

class Station {
  final String id;
  final String name;
  final String code;
  final List<String> lineCodes;
  final double lat;
  final double lng;
  final bool isInterchange;
  final List<dynamic> platforms;
  final List<dynamic> gates;
  final Map<String, dynamic> facilities; 

  Station({
    required this.id,
    required this.name,
    required this.code,
    required this.lineCodes,
    required this.lat,
    required this.lng,
    required this.isInterchange,
    required this.platforms,
    required this.gates,
    required this.facilities,
  });

  factory Station.fromMap(Map<String, dynamic> data) {
    dynamic parseJson(dynamic input) {
      if (input is String) {
        try {
          return jsonDecode(input);
        } catch (e) {
          return [];
        }
      }
      return input ?? [];
    }

    Map<String, dynamic> parsedFacilities = {};
    if (data['facilities_json'] != null) {
       var f = parseJson(data['facilities_json']);
       if (f is Map<String, dynamic>) parsedFacilities = f;
    }

    List<dynamic> parsedGates = [];
    var g = parseJson(data['gates_json']);
    if (g is List) parsedGates = g;

    return Station(
      id: data['station_id'].toString(),
      name: data['name'] ?? 'Unknown',
      code: data['code'] ?? '',
      lineCodes: [], // Will be filled in Service
      lat: (data['lat'] ?? 0.0).toDouble(),
      lng: (data['lng'] ?? 0.0).toDouble(),
      isInterchange: (data['has_interchange'] == 1), 
      platforms: [], 
      gates: parsedGates,
      facilities: parsedFacilities,
    );
  }
}

class MetroLine {
  final String id;
  final String name;
  final Color color;

  MetroLine({required this.id, required this.name, required this.color});

  factory MetroLine.fromMap(Map<String, dynamic> data) {
    return MetroLine(
      id: data['line_id'].toString(),
      name: data['name'] ?? '',
      color: _hexToColor(data['color'] ?? '808080'),
    );
  }

  static Color _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}

class GraphEdge {
  final String u; final String v; final String lineId; final double distance; final int time;
  
  GraphEdge({required this.u, required this.v, required this.lineId, required this.distance, required this.time});
  
  factory GraphEdge.fromMap(Map<String, dynamic> data) {
    return GraphEdge(
      u: data['from_id'].toString(), 
      v: data['to_id'].toString(), 
      lineId: data['line_id'].toString(),
      distance: (data['distance_km'] ?? 0.0).toDouble(), 
      time: (data['time_sec'] ?? 0) ~/ 60, 
    );
  }
}

class FareSlab {
  final double km; final int price;
  FareSlab({required this.km, required this.price});
  
  factory FareSlab.fromMap(Map<String, dynamic> data) {
    return FareSlab(
      km: (data['max_km'] ?? 0.0).toDouble(),
      price: (data['fare'] ?? 0).toInt()
    );
  }
}

class RouteResult {
  final List<Station> path;
  final int totalTime;
  final double totalDistance;
  final int fare;
  final int stationsCount;
  final List<String> interchangeStations;

  RouteResult({required this.path, required this.totalTime, required this.totalDistance, required this.fare, required this.stationsCount, required this.interchangeStations});
}