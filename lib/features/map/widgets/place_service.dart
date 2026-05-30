import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ridel/features/map/models/place_model.dart'; 

class SavedPlacesService {
  static const String _homeKey = 'user_home_place';
  static const String _workKey = 'user_work_place';

  static Future<void> saveHome(PlaceModel place) async {
    final prefs = await SharedPreferences.getInstance();
    // 🚀 THE FIX: category ko bhi save me add kiya
    final String data = json.encode({
      'placeId': place.placeId, 
      'name': place.name, 
      'lat': place.latitude, 
      'lng': place.longitude, 
      'address': place.address,
      'category': place.categories.isNotEmpty ? place.categories.first : 'unknown' // 🚀 Added
    });
    await prefs.setString(_homeKey, data);
  }

  static Future<void> saveWork(PlaceModel place) async {
    final prefs = await SharedPreferences.getInstance();
    // 🚀 THE FIX: category ko bhi save me add kiya
    final String data = json.encode({
      'placeId': place.placeId, 
      'name': place.name, 
      'lat': place.latitude, 
      'lng': place.longitude, 
      'address': place.address,
      'category': place.categories.isNotEmpty ? place.categories.first : 'unknown' // 🚀 Added
    });
    await prefs.setString(_workKey, data);
  }

  static Future<PlaceModel?> getHome() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_homeKey);
    if (data == null) return null;
    final map = json.decode(data);
    
    // 🚀 THE FIX: Fetch karte waqt category pass kar rahe hain
    return PlaceModel(
      placeId: map['placeId'] ?? 'home_id_fallback', 
      name: map['name'], 
      address: map['address'] ?? '', 
      latitude: map['lat'], 
      longitude: map['lng'],
      categories: [map['category'] ?? 'Home'], // 🚀 Added Default Category
    );
  }

  static Future<PlaceModel?> getWork() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_workKey);
    if (data == null) return null;
    final map = json.decode(data);
    
    // 🚀 THE FIX: Fetch karte waqt category pass kar rahe hain
    return PlaceModel(
      placeId: map['placeId'] ?? 'work_id_fallback', 
      name: map['name'], 
      address: map['address'] ?? '', 
      latitude: map['lat'], 
      longitude: map['lng'],
      categories: [map['category'] ?? 'Work'], // 🚀 Added Default Category
    );
  }

  static Future<void> deleteHome() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_homeKey);
  }

  static Future<void> deleteWork() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_workKey);
  }
}