import 'package:flutter/material.dart';

// ==================== CORE DATABASE MODELS ====================

class Stop {
  final String stopId;
  final String stopName;
  final double stopLat;
  final double stopLon;
  final double schematicX;
  final double schematicY;

  Stop({
    required this.stopId,
    required this.stopName,
    required this.stopLat,
    required this.stopLon,
    required this.schematicX,
    required this.schematicY,
  });

  factory Stop.fromMap(Map<String, dynamic> map) {
    return Stop(
      stopId: map['stop_id']?.toString() ?? '',
      stopName: map['stop_name']?.toString() ?? '',
      stopLat: _parseDouble(map['lat']),
      stopLon: _parseDouble(map['lon']),
      schematicX:
          map['schematic_x'] != null ? _parseDouble(map['schematic_x']) : 0.0,
      schematicY:
          map['schematic_y'] != null ? _parseDouble(map['schematic_y']) : 0.0,
    );
  }
}

/// Represents a metro line (route)
class MetroRoute {
  final String routeId;
  final String routeName;
  final Color routeColor;

  MetroRoute({
    required this.routeId,
    required this.routeName,
    required this.routeColor,
  });

  factory MetroRoute.fromMap(Map<String, dynamic> map) {
    final hex = map['route_color']?.toString() ?? 'FFFFFF';
    return MetroRoute(
      routeId: map['route_id']?.toString() ?? '',
      routeName: map['route_short_name']?.toString() ?? '',
      routeColor: hexToColor(hex), // 🔥 Cleaned: using global utility
    );
  }
}

class GraphEdge {
  final String fromNodeId;
  final String toNodeId;
  final String routeId;
  final int timeSeconds;
  final double distanceKm;
  final String? platformName; // 🚀 Naya variable yahan hai

  GraphEdge({
    required this.fromNodeId,
    required this.toNodeId,
    required this.routeId,
    required this.timeSeconds,
    required this.distanceKm,
    this.platformName,
  });

  factory GraphEdge.fromMap(Map<String, dynamic> map) {
    return GraphEdge(
      fromNodeId: map['from_node_id'].toString(),
      toNodeId: map['to_node_id'].toString(),
      routeId: map['route_id'].toString(),
      timeSeconds: _parseInt(map['time_seconds']),
      distanceKm: _parseDouble(map['distance_km']),
      platformName: map['platform_name']
          ?.toString(), // 🚀 Mapping se values utha raha hai
    );
  }
}

class Facility {
  final String stopId;
  final String facilityId;
  final String type;
  final String locationDesc;

  Facility({
    required this.stopId,
    required this.facilityId,
    required this.type,
    required this.locationDesc,
  });

  factory Facility.fromMap(Map<String, dynamic> map) {
    return Facility(
      stopId: map['stop_id']?.toString() ?? '',
      facilityId: map['facility_id']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      locationDesc: map['location_desc']?.toString() ?? '',
    );
  }
}

class Gate {
  final String stopId;
  final String gateName;
  final String locationDesc;

  Gate({
    required this.stopId,
    required this.gateName,
    required this.locationDesc,
  });

  factory Gate.fromMap(Map<String, dynamic> map) {
    return Gate(
      stopId: map['stop_id']?.toString() ?? '',
      gateName: map['gate_name']?.toString() ?? '',
      locationDesc: map['location_desc']?.toString() ?? '',
    );
  }
}

class Parking {
  final String stopId;
  final int capCar;
  final int capBike;

  Parking({
    required this.stopId,
    required this.capCar,
    required this.capBike,
  });

  factory Parking.fromMap(Map<String, dynamic> map) {
    return Parking(
      stopId: map['stop_id']?.toString() ?? '',
      capCar: _parseInt(map['cap_car']),
      capBike: _parseInt(map['cap_bike']),
    );
  }
}

// ==================== ADDED MODELS ====================

class FareConfig {
  final int id;
  final double minKm;
  final double maxKm;
  final int priceNormal;
  final String agencyId;

  FareConfig({
    required this.id,
    required this.minKm,
    required this.maxKm,
    required this.priceNormal,
    required this.agencyId,
  });

  factory FareConfig.fromMap(Map<String, dynamic> map) {
    return FareConfig(
      id: map['id'] is int ? map['id'] : int.tryParse(map['id']?.toString() ?? '0') ?? 0,
      minKm: map['min_km'] is num ? (map['min_km'] as num).toDouble() : double.tryParse(map['min_km']?.toString() ?? '0.0') ?? 0.0,
      maxKm: map['max_km'] is num ? (map['max_km'] as num).toDouble() : double.tryParse(map['max_km']?.toString() ?? '0.0') ?? 0.0,
      priceNormal: map['price_normal'] is int ? map['price_normal'] : int.tryParse(map['price_normal']?.toString() ?? '0') ?? 0,
      agencyId: map['agency_id']?.toString() ?? map['AGENCY_ID']?.toString() ?? 'DMRC',
    );
  }
}

class PlatformInfo {
  final String stopId;
  final String platformName;
  final String towardsStationCode;
  final bool isActive;

  PlatformInfo({
    required this.stopId,
    required this.platformName,
    required this.towardsStationCode,
    required this.isActive,
  });

  factory PlatformInfo.fromMap(Map<String, dynamic> map) {
    return PlatformInfo(
      stopId: map['stop_id']?.toString() ?? '',
      platformName: map['platform_name']?.toString() ?? '',
      towardsStationCode: map['towards_station_code']?.toString() ?? '',
      isActive: map['is_active'] == 1,
    );
  }
}

// ==================== COMPOSITE & RESULT MODELS ====================

class StationDetails {
  final Stop stop;
  final List<Facility> facilities;
  final List<Gate> gates;
  final Parking? parking;

  StationDetails({
    required this.stop,
    required this.facilities,
    required this.gates,
    this.parking,
  });
}

class StopSuggestion {
  final String stopId;
  final String stopName;
  final double? distance;

  StopSuggestion({
    required this.stopId,
    required this.stopName,
    this.distance,
  });
}

class GraphNode {
  final String id;
  final List<GraphEdge> outgoingEdges;

  GraphNode(this.id, this.outgoingEdges);
}

class PathfindingResult {
  final List<String> nodeIds;
  final List<GraphEdge> edges;
  final int totalTimeSeconds;
  final double totalFare;
  final double totalDistanceKm;
  final List<String> routeIds;

  PathfindingResult({
    required this.nodeIds,
    required this.edges,
    required this.totalTimeSeconds,
    required this.totalFare,
    required this.totalDistanceKm,
    required this.routeIds,
  });
}

// ==================== GLOBAL UTILITIES ====================
// 🔥 Ek baar likho, har class me use karo!

int _parseInt(dynamic val) {
  if (val == null) return 0;
  if (val is int) return val;
  if (val is double) return val.toInt();
  return int.tryParse(val.toString()) ?? 0;
}

double _parseDouble(dynamic val) {
  if (val == null) return 0.0;
  if (val is int) return val.toDouble();
  if (val is double) return val;
  return double.tryParse(val.toString()) ?? 0.0;
}

Color hexToColor(String hexString) {
  var hex = hexString.replaceAll('#', '').trim();
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length == 8) {
    final colorValue = int.tryParse(hex, radix: 16);
    if (colorValue != null) return Color(colorValue);
  }
  return const Color(0xFFFFFFFF);
}
