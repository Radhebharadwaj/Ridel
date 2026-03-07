// lib/features/map/models/place_model.dart

class PlaceModel {
  final String placeId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String category;

  PlaceModel({
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.category,
  });

  // DB ya API se data lene ke liye
  factory PlaceModel.fromJson(Map<String, dynamic> json) {
    return PlaceModel(
      placeId: json['place_id'] ?? '',
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      category: json['category'] ?? 'unknown',
    );
  }

  // DB mein data bhejney ke liye
  Map<String, dynamic> toJson() {
    return {
      'p_place_id': placeId,
      'p_name': name,
      'p_address': address,
      'p_lat': latitude,
      'p_lng': longitude,
      'p_category': category,
    };
  }
}