// lib/features/map/services/map_search_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/place_model.dart';
import 'supabase_search_db.dart'; // Make sure this matches your file name
import 'open_map_service.dart';
import 'package:ridel/core/services/place_service.dart';

class MapSearchService {
  final SupabaseSearchService _supabaseDb = SupabaseSearchService();
  final OpenMapService _openMapService = OpenMapService();
  final PlaceService _premiumPlaceService = PlaceService();
  bool _isLoadingDetails = false;

  // =========================================================================
  // 🔥 1. THE 3-TIER FALLBACK SEARCH ENGINE
  // =========================================================================
  Future<List<PlaceModel>> getSuggestions(String query) async {
    if (query.trim().length < 2) return [];

    List<PlaceModel> finalResults = [];

    try {
      // TIER 1: SUPABASE (0 Cost, Lightning Fast, Trending Data)
      final localResults = await _supabaseDb.getTrendingSuggestions(query);
      finalResults.addAll(localResults);

      // Agar sufficient results nahi mile, toh external APIs ko hit karo
      if (finalResults.length < 3) {
        
        // TIER 2: OPEN STREET MAPS (Free Tier)
        final openMapResults = await _openMapService.searchPlaces(query);
        finalResults.addAll(openMapResults);

        // TIER 3: OLA PREMIUM MAPS (Fallback for tough Indian addresses)
        if (finalResults.isEmpty) {
          final olaResults = await _premiumPlaceService.searchPremiumPlaces(query);
          finalResults.addAll(olaResults);
        }
      }
      
      // Remove duplicates based on place_id or name
      return _removeDuplicates(finalResults);
      
    } catch (e) {
      if (kDebugMode) print("❌ Search Engine Error: $e");
      return finalResults;
    }
  }

  // =========================================================================
  // 🔥 2. SILENT BACKGROUND SYNC (The Master Data Builder)
  // Call this when user TAPS on a search result
  // =========================================================================
  Future<void> onPlaceSelected(PlaceModel place) async {
    // 1. Save to Local Mobile History (For "Recent Searches" UI)
    await _saveToLocalHistory(place);

    // 2. The Smart Filter: Check if it's a public place worth saving to Global DB
    if (_isWorthCaching(place)) {
      await _supabaseDb.logSuccessfulSearch(place);
    } else {
      if (kDebugMode) print("🚫 CACHE BLOCKED: '${place.name}' is private.");
    }
  }

  // =========================================================================
  // 🔥 3. THE SMART FILTER (GATEKEEPER)
  // =========================================================================
  bool _isWorthCaching(PlaceModel place) {
    final nameLower = place.name.toLowerCase();

    // Reject short meaningless queries
    if (nameLower.length < 4) return false;

    // Reject private locations
    List<String> blackList = ['home', 'work', 'flat', 'house', 'plot', 'makan', 'room', 'gali', 'block'];
    for (String word in blackList) {
      if (nameLower.contains(word)) return false;
    }

    // Allow only valid public categories
    List<String> allowedTypes = [
      'airport', 'station', 'restaurant', 'locality', 'business', 'point_of_interest',
      'hospital', 'mall', 'cafe', 'transit_station', 'tourist_attraction', 'city', 'town', 'village'
    ];
    
    if (place.category != 'unknown') {
      bool isTypeAllowed = allowedTypes.any((type) => place.category.toLowerCase().contains(type));
      if (!isTypeAllowed) return false; 
    }

    return true; // Safe to save!
  }

  // =========================================================================
  // 🔥 4. LOCAL HISTORY (For Recents Tab)
  // =========================================================================
  Future<void> _saveToLocalHistory(PlaceModel place) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('recent_searches') ?? [];
    
    // Convert to JSON and remove if already exists (to push to top)
    final placeJson = json.encode(place.toJson());
    history.removeWhere((item) => item.contains(place.name)); 
    
    // Add to top, keep max 5 recents
    history.insert(0, placeJson);
    if (history.length > 5) history = history.sublist(0, 5);
    
    await prefs.setStringList('recent_searches', history);
  }

  Future<List<PlaceModel>> getLocalHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('recent_searches') ?? [];
    return history.map((e) => PlaceModel.fromJson(json.decode(e))).toList();
  }

  // Helper
  List<PlaceModel> _removeDuplicates(List<PlaceModel> items) {
    final seen = <String>{};
    return items.where((item) => seen.add(item.name.toLowerCase())).toList();
  }
}