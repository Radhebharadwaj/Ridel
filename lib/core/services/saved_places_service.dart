import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SavedPlace {
  final String type;
  final double latitude;
  final double longitude;

  SavedPlace({
    required this.type,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory SavedPlace.fromJson(Map<String, dynamic> json) => SavedPlace(
        type: json['type'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
}

class SavedPlacesService extends ChangeNotifier {
  static const String _placesKey = 'saved_places';
  List<SavedPlace> _places = [];

  List<SavedPlace> get places => _places;

  SavedPlacesService() {
    _loadPlaces();
  }

  Future<void> _loadPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final String? placesJson = prefs.getString(_placesKey);
    if (placesJson != null) {
      try {
        final List<dynamic> decodedList = json.decode(placesJson);
        _places = decodedList.map((item) => SavedPlace.fromJson(item)).toList();
        notifyListeners();
      } catch (e) {
        debugPrint('Error loading saved places: $e');
      }
    }
  }

  Future<void> savePlace(
      BuildContext context, String type, double lat, double lng) async {
    // Constraint: MAXIMUM of 5 places
    if (_places.length >= 5 && !_places.any((p) => p.type == type)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 5 places can be saved.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Constraint: type string MUST be 5 characters or less
    if (type.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Place type must be 5 characters or less.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final newPlace = SavedPlace(type: type, latitude: lat, longitude: lng);

    // Check if type already exists, if so replace it
    final existingIndex = _places.indexWhere((p) => p.type == type);
    if (existingIndex != -1) {
      _places[existingIndex] = newPlace;
    } else {
      _places.add(newPlace);
    }

    await _saveToLocal();
    notifyListeners();

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await _uploadPlace(newPlace, user.id);
    } else {
      // Notification: When saved locally while logged out
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Place saved locally. Log in to sync across devices.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> removePlace(String type) async {
    _places.removeWhere((p) => p.type == type);
    await _saveToLocal();
    notifyListeners();

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client
            .from('user_saved_places')
            .delete()
            .eq('user_id', user.id)
            .eq('place_type', type);
      } catch (e) {
        debugPrint('Error deleting place from cloud: $e');
      }
    }
  }

  Future<void> _saveToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedList =
        json.encode(_places.map((p) => p.toJson()).toList());
    await prefs.setString(_placesKey, encodedList);
  }

  Future<void> _uploadPlace(SavedPlace place, String userId) async {
    try {
      // Upsert to handle both insert and update
      await Supabase.instance.client.from('user_saved_places').upsert({
        'user_id': userId,
        'place_type': place.type,
        'latitude': place.latitude,
        'longitude': place.longitude,
      });
    } catch (e) {
      debugPrint('Error uploading place to cloud: $e');
    }
  }

  // Supabase Sync: Runs when the user logs in
  Future<void> syncPlacesToCloud() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    for (var place in _places) {
      await _uploadPlace(place, user.id);
    }
  }
}
