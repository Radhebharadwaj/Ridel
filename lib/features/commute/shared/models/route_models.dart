import 'package:flutter/material.dart';

enum StationType { source, normal, interchange, destination }

class RouteStation {
  final String id;
  final String name;
  final String lineName;
  final String lineCode;
  final Color lineColor;
  final String time;
  final StationType type;
  final String? instruction;
  
  // 🚀 LIVE TRACKING COORDS ADDED HERE
  final double lat;
  final double lon;
  
  final String? busNumber;
  final String? frequency;
  final String? liveArrivalTime;

  RouteStation({
    required this.id,
    required this.name,
    required this.lineName,
    required this.lineCode,
    required this.lineColor,
    required this.time,
    required this.type,
    this.instruction,
    this.lat = 0.0, // Default 0.0 taaki purana code crash na ho
    this.lon = 0.0,
    this.busNumber,
    this.frequency,
    this.liveArrivalTime,
  });
}

class RouteResult {
  final List<RouteStation> path;
  final int totalFare;
  final int totalTimeMin;
  final int totalStops;
  final double totalDistance;
  final List<String> pathLineIds;

  RouteResult({
    required this.path,
    required this.totalFare,
    required this.totalTimeMin,
    required this.totalStops,
    this.totalDistance = 0.0,
    this.pathLineIds = const [],
  });

  factory RouteResult.fromSeconds({
    required List<RouteStation> path,
    required int totalFare,
    required int totalTimeSeconds,
    required int totalStops,
    required double totalDistance,
    required List<String> pathLineIds,
  }) {
    // Calculate Interchanges
    int interchangeCount = 0;
    if (path.isNotEmpty) {
      String currentLineCode = path.first.lineCode;
      for (var station in path) {
        if (station.lineCode != currentLineCode) {
          interchangeCount++;
          currentLineCode = station.lineCode;
        }
      }
    }

    // Add 6 minutes penalty per interchange
    int penaltyPerInterchange = 6;
    int rawTravelTimeMin = (totalTimeSeconds / 60).ceil();
    int actualTotalTime = rawTravelTimeMin + (interchangeCount * penaltyPerInterchange);

    return RouteResult(
      path: path,
      totalFare: totalFare,
      totalTimeMin: actualTotalTime,
      totalStops: totalStops,
      totalDistance: totalDistance,
      pathLineIds: pathLineIds,
    );
  }
}