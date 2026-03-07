class BusRouteInfo {
  final String routeId;
  final String busNumber; // e.g., "945", "114C"
  final String description;

  BusRouteInfo({required this.routeId, required this.busNumber, required this.description});

  factory BusRouteInfo.fromMap(Map<String, dynamic> map) {
    return BusRouteInfo(
      routeId: map['route_id'].toString(),
      busNumber: map['route_short_name']?.toString() ?? "Bus",
      description: map['route_long_name']?.toString() ?? "",
    );
  }
}

class BusFareRule {
  final double minKm;
  final double maxKm;
  final int price;

  BusFareRule({required this.minKm, required this.maxKm, required this.price});

  factory BusFareRule.fromMap(Map<String, dynamic> map) {
    return BusFareRule(
      minKm: (map['min_km'] as num).toDouble(),
      maxKm: (map['max_km'] as num).toDouble(),
      price: map['price_normal'] as int,
    );
  }
}