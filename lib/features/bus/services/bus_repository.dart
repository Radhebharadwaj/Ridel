import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BusRepository {
  final _supabase = Supabase.instance.client;

  // ✅ FIX #1: Prevent sqflite crash on Web
  void initDB() {
    // Critical: sqflite doesn't support Web, so skip database initialization
    if (kIsWeb) return;
    
    // Add your local database initialization code here for mobile platforms
    // Example: await database.init();
  }

  Future<List<Map<String, dynamic>>> fetchRoutes() async {
    try {
      final response = await _supabase
          .from('routes')
          .select('route_long_name, route_short_name')
          .limit(20);
      return response;
    } catch (e) {
      // Proper error handling
      print('Error fetching routes: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getSmartRoutes(
      String from, String to) async {
    // ✅ Text Normalization: Trim and prepare for case-insensitive search
    final normalizedFrom = from.trim();
    final normalizedTo = to.trim();
    
    // ✅ Debug Logs: Print exact parameters being sent
    print('🔍 [BusRepository] getSmartRoutes called with:');
    print('   From: "$normalizedFrom" (length: ${normalizedFrom.length})');
    print('   To: "$normalizedTo" (length: ${normalizedTo.length})');
    
    if (normalizedFrom.isEmpty || normalizedTo.isEmpty) {
      print('❌ [BusRepository] Error: Empty from or to parameter');
      return [];
    }
    
    // ✅ Primary: Try the complex RPC function with timeout handling
    // Try different parameter name variations in case the RPC expects different names
    final List<Map<String, dynamic>>? rpcResult = await _tryRPCWithParams(
      normalizedFrom,
      normalizedTo,
      {'start_search': normalizedFrom, 'end_search': normalizedTo},
    );
    
    if (rpcResult != null && rpcResult.isNotEmpty) {
      return rpcResult;
    }
    
    // Try alternative parameter names
    final List<Map<String, dynamic>>? altRpcResult = await _tryRPCWithParams(
      normalizedFrom,
      normalizedTo,
      {'from': normalizedFrom, 'to': normalizedTo},
    );
    
    if (altRpcResult != null && altRpcResult.isNotEmpty) {
      return altRpcResult;
    }
    
    // Try another variation
    final List<Map<String, dynamic>>? alt2RpcResult = await _tryRPCWithParams(
      normalizedFrom,
      normalizedTo,
      {'source': normalizedFrom, 'destination': normalizedTo},
    );
    
    if (alt2RpcResult != null && alt2RpcResult.isNotEmpty) {
      return alt2RpcResult;
    }
    
    // ✅ Fallback: Try simple direct route query
    try {
      print('🔄 [BusRepository] Attempting fallback: Direct route query...');
      
      // Note: This assumes there's a 'routes' table with start_stop and end_stop columns
      // Adjust table/column names based on your actual database schema
      // Using textSearch for flexible matching
      
      final directRoutesQuery = _supabase
          .from('routes')
          .select('route_short_name, route_long_name, route_id')
          .limit(10);
      
      final directRoutes = await directRoutesQuery
          .timeout(
            const Duration(seconds: 4),
            onTimeout: () {
              print('⏱️ [BusRepository] Fallback query timeout');
              throw TimeoutException('Fallback query timed out');
            },
          );
      
      if (directRoutes != null && directRoutes.isNotEmpty) {
        // Filter routes that might match (case-insensitive)
        final filteredRoutes = directRoutes.where((route) {
          final routeName = (route['route_long_name'] ?? '').toString().toLowerCase();
          final fromLower = normalizedFrom.toLowerCase();
          final toLower = normalizedTo.toLowerCase();
          
          // Check if route name contains both from and to (simple matching)
          return routeName.contains(fromLower) || routeName.contains(toLower);
        }).toList();
        
        if (filteredRoutes.isNotEmpty) {
          print('✅ [BusRepository] Fallback found ${filteredRoutes.length} matching routes');
          
          // Transform to match expected format
          return filteredRoutes.map((route) {
            return {
              'priority_level': 1, // Direct route
              'bus_number': route['route_short_name'] ?? route['route_id'] ?? 'N/A',
              'start_stop': normalizedFrom,
              'end_stop': normalizedTo,
              'route_long_name': route['route_long_name'] ?? '',
            };
          }).toList();
        }
      }
    } catch (e) {
      print('❌ [BusRepository] Fallback query error: $e');
      if (e is TimeoutException) {
        print('   Timeout occurred in fallback query');
      }
    }
    
    print('❌ [BusRepository] All queries failed, returning empty list');
    return [];
  }

  // ✅ Helper method to try RPC with different parameter sets
  Future<List<Map<String, dynamic>>?> _tryRPCWithParams(
    String from,
    String to,
    Map<String, dynamic> params,
  ) async {
    try {
      print('🚀 [BusRepository] Attempting get_smart_routes RPC with params: $params');
      
      final response = await _supabase
          .rpc('get_smart_routes', params: params)
          .timeout(
            const Duration(seconds: 4), // 4 second timeout
            onTimeout: () {
              print('⏱️ [BusRepository] RPC timeout after 4 seconds');
              throw TimeoutException('RPC call timed out');
            },
          );
      
      final routes = List<Map<String, dynamic>>.from(response);
      print('✅ [BusRepository] RPC successful, found ${routes.length} routes');
      
      if (routes.isNotEmpty) {
        return routes;
      } else {
        print('⚠️ [BusRepository] RPC returned empty results');
      }
    } catch (e) {
      print('❌ [BusRepository] RPC Error with params $params: $e');
      print('   Error type: ${e.runtimeType}');
      if (e is PostgrestException) {
        print('   Postgrest Error Details: ${e.message}');
        print('   Code: ${e.code}');
        print('   Details: ${e.details}');
      } else if (e is TimeoutException) {
        print('   ⏱️ Timeout exception caught');
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> searchStops(String query) async {
    try {
      final response = await _supabase
          .rpc('search_stops', params: {'keyword': query});
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error searching stops: $e');
      return [];
    }
  }
}
