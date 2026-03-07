// lib/features/map/services/supabase_search_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/place_model.dart';

class SupabaseSearchService {
  final _supabase = Supabase.instance.client;

  /// 🔥 BACKGROUND MAGIC: Saves successful searches
  Future<void> logSuccessfulSearch(PlaceModel place) async {
    try {
      await _supabase.rpc('log_smart_place_search', params: place.toJson());
      if (kDebugMode) print("✅ SILENT SYNC: Place '${place.name}' logged!");
    } catch (e) {
      if (kDebugMode) print("❌ SILENT SYNC FAILED: $e");
    }
  }

  /// ⚡ FUZZY AUTOCOMPLETE: Handles typos and bad spelling!
  Future<List<PlaceModel>> getTrendingSuggestions(String query) async {
    if (query.trim().length < 2) return [];

    try {
      // 🚀 Calling the new Fuzzy Search RPC we created in Supabase
      final response = await _supabase.rpc('fuzzy_search_places', params: {
        'search_query': query.trim()
      });

      return (response as List).map((json) => PlaceModel.fromJson(json)).toList();
    } catch (e) {
      if (kDebugMode) print("❌ FETCH TRENDING FAILED: $e");
      return [];
    }
  }
}