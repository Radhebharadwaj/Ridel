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

  RouteStation({
    required this.id,
    required this.name,
    required this.lineName,
    required this.lineCode,
    required this.lineColor,
    required this.time,
    required this.type,
    this.instruction,
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
    return RouteResult(
      path: path,
      totalFare: totalFare,
      totalTimeMin: (totalTimeSeconds / 60).ceil(),
      totalStops: totalStops,
      totalDistance: totalDistance,
      pathLineIds: pathLineIds,
    );
  }
}