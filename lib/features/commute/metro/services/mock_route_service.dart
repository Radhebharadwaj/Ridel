import 'package:flutter/material.dart';
// 🔥 Import path ko ekdum theek kar diya gaya hai (Shared folder se utha raha hai)
import 'package:ridel/features/commute/shared/models/route_models.dart';

class MockRouteService {
  static const cYellow = Color(0xFFF6D71A);
  static const cViolet = Color(0xFF8115FF);

  static RouteResult getDummyRoute() {
    // 🔥 Yahan se 'const' hata diya hai kyunki RouteResult ab dynamic location (lat, lon) support karta hai
    return RouteResult(
      totalFare: 40,
      totalTimeMin: 45,
      totalStops: 8,
      totalDistance: 12.5,
      path: [
        RouteStation(
            id: "1",
            name: "Hauz Khas",
            lineName: "Yellow Line",
            lineCode: "LN2",
            lineColor: cYellow,
            time: "10:00 AM",
            type: StationType.source),
        RouteStation(
            id: "2",
            name: "Green Park",
            lineName: "Yellow Line",
            lineCode: "LN2",
            lineColor: cYellow,
            time: "10:03 AM",
            type: StationType.normal),
        RouteStation(
            id: "3",
            name: "AIIMS",
            lineName: "Yellow Line",
            lineCode: "LN2",
            lineColor: cYellow,
            time: "10:07 AM",
            type: StationType.normal),
        RouteStation(
            id: "4",
            name: "INA",
            lineName: "Yellow Line",
            lineCode: "LN2",
            lineColor: cYellow,
            time: "10:12 AM",
            type: StationType.normal),
        // Interchange
        RouteStation(
            id: "5",
            name: "Central Secretariat",
            lineName: "Yellow Line",
            lineCode: "LN2",
            lineColor: cYellow,
            time: "10:20 AM",
            type: StationType.interchange,
            instruction: "Change here for Violet Line"),
        RouteStation(
            id: "6",
            name: "Khan Market",
            lineName: "Violet Line",
            lineCode: "LN6",
            lineColor: cViolet,
            time: "10:25 AM",
            type: StationType.normal),
        RouteStation(
            id: "7",
            name: "JLN Stadium",
            lineName: "Violet Line",
            lineCode: "LN6",
            lineColor: cViolet,
            time: "10:29 AM",
            type: StationType.normal),
        RouteStation(
            id: "8",
            name: "Mandi House",
            lineName: "Violet Line",
            lineCode: "LN6",
            lineColor: cViolet,
            time: "10:35 AM",
            type: StationType.destination),
      ],
    );
  }
}
