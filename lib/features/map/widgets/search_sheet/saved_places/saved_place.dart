import 'dart:convert';

class SavedPlace {
  final String id;
  final String type; // home, work, custom
  final String title;
  final String address;
  final double lat;
  final double lng;

  SavedPlace({
    required this.id,
    required this.type,
    required this.title,
    required this.address,
    required this.lat,
    required this.lng,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'address': address,
      'lat': lat,
      'lng': lng,
    };
  }

  factory SavedPlace.fromMap(Map<String, dynamic> map) {
    return SavedPlace(
      id: map['id'] ?? '',
      type: map['type'] ?? 'custom',
      title: map['title'] ?? '',
      address: map['address'] ?? '',
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String toJson() => json.encode(toMap());

  factory SavedPlace.fromJson(String source) =>
      SavedPlace.fromMap(json.decode(source));

  SavedPlace copyWith({
    String? id,
    String? type,
    String? title,
    String? address,
    double? lat,
    double? lng,
  }) {
    return SavedPlace(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }
}
