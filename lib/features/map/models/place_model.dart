import 'package:flutter/material.dart';

class PlaceModel {
  final String placeId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  // 🚀 FIX: Now strictly a List of categories for exact mapping
  final List<String> categories;

  // 🚀 FIX: Rich Metadata Fields for the Future PlaceIntelligenceService
  final double? rating;
  final String? openingHours;
  final String? phone;
  final List<String>? imageUrls;

  PlaceModel({
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.categories,
    this.rating,
    this.openingHours,
    this.phone,
    this.imageUrls,
  });

  factory PlaceModel.fromJson(Map<String, dynamic> json) {
    // Bulletproof number parsing
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    // 🚀 FIX: Safely parse single string OR list of strings into a lowercase List
    List<String> parseCategories(dynamic catData) {
      if (catData == null) return ['unknown'];
      if (catData is List) {
        return catData.map((e) => e.toString().toLowerCase().trim()).toList();
      }
      if (catData is String) {
        return catData.split(',').map((e) => e.toLowerCase().trim()).toList();
      }
      return ['unknown'];
    }

    return PlaceModel(
      placeId: json['place_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString() ??
          json['formatted_address']?.toString() ??
          '',
      latitude: parseDouble(json['latitude'] ?? json['lat']),
      longitude: parseDouble(json['longitude'] ?? json['lng']),
      categories: parseCategories(
          json['category'] ?? json['categories'] ?? json['types']),

      // Optional Rich Metadata (Will be null from basic search, populated later)
      rating: parseDouble(json['rating']),
      openingHours: json['opening_hours']?.toString(),
      phone: json['phone']?.toString(),
      imageUrls:
          json['photos'] != null ? List<String>.from(json['photos']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'place_id': placeId,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'categories': categories,
      'rating': rating,
      'opening_hours': openingHours,
      'phone': phone,
      'photos': imageUrls,
    };
  }
}

// ───── The Apple-Level Theme Engine ─────
class PlaceTheme {
  final Color color;
  final IconData icon;

  const PlaceTheme(this.color, this.icon);
}

extension PlaceModelTheme on PlaceModel {
  PlaceTheme get theme {
    // 🚀 FIX: Name-based fallback completely removed to prevent "Fortis Hospital" bugs.
    // 🚀 FIX: Expanded Apple-Level Category Mapping

    for (String cat in categories) {
      // 🏥 Health & Emergency
      if (cat == 'hospital' ||
          cat == 'clinic' ||
          cat == 'pharmacy' ||
          cat == 'doctor') {
        return const PlaceTheme(Color(0xFFFF3B30), Icons.local_hospital); // Red
      }
      // 🚗 Driving Essentials
      else if (cat == 'fuel' || cat == 'gas_station' || cat == 'petrol_pump') {
        return const PlaceTheme(
            Color(0xFFFF9500), Icons.local_gas_station); // Orange
      } else if (cat == 'parking') {
        return const PlaceTheme(Color(0xFF007AFF), Icons.local_parking); // Blue
      }
      // 🚇 Transit
      else if (cat.contains('transit') ||
          cat == 'train_station' ||
          cat == 'subway_station' ||
          cat == 'bus_station' ||
          cat == 'airport') {
        return const PlaceTheme(
            Color(0xFF5AC8FA), Icons.directions_transit); // Light Blue
      }
      // 🍔 Food & Dining
      else if (cat == 'restaurant' ||
          cat == 'cafe' ||
          cat == 'bakery' ||
          cat == 'bar' ||
          cat == 'food') {
        return const PlaceTheme(Color(0xFFFF9500), Icons.restaurant); // Orange
      }
      // 🏛️ Monuments & Culture
      else if (cat == 'museum' ||
          cat == 'hindu_temple' ||
          cat == 'mosque' ||
          cat == 'church' ||
          cat == 'tourist_attraction' ||
          cat == 'historical') {
        return const PlaceTheme(
            Color(0xFFAF52DE), Icons.account_balance); // Purple
      }
      // 🌳 Nature
      else if (cat == 'park' || cat == 'garden' || cat == 'zoo') {
        return const PlaceTheme(Color(0xFF34C759), Icons.park); // Green
      }
      // 🛍️ Shopping
      else if (cat == 'shopping_mall' ||
          cat == 'store' ||
          cat == 'supermarket' ||
          cat == 'atm') {
        return const PlaceTheme(
            Color(0xFFFFCC00), Icons.shopping_bag); // Yellow
      }
      // 🛏️ Accommodation
      else if (cat == 'lodging' || cat == 'hotel') {
        return const PlaceTheme(Color(0xFF5856D6), Icons.hotel); // Indigo
      }
    }

    // Default Pin Theme (If no matching category is found)
    return const PlaceTheme(
        Color(0xFF8E8E93), Icons.location_on); // Gray/Neutral
  }
}
