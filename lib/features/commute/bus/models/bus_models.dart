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
  final String agencyId;

  BusFareRule({required this.minKm, required this.maxKm, required this.price, required this.agencyId});

  factory BusFareRule.fromMap(Map<String, dynamic> map) {
    return BusFareRule(
      minKm: map['min_km'] is num ? (map['min_km'] as num).toDouble() : double.tryParse(map['min_km']?.toString() ?? '0.0') ?? 0.0,
      maxKm: map['max_km'] is num ? (map['max_km'] as num).toDouble() : double.tryParse(map['max_km']?.toString() ?? '0.0') ?? 0.0,
      price: map['price_normal'] is int ? map['price_normal'] : int.tryParse(map['price_normal']?.toString() ?? '0') ?? 0,
      agencyId: map['agency_id']?.toString() ?? map['AGENCY_ID']?.toString() ?? 'DTC_NON_AC',
    );
  }
}