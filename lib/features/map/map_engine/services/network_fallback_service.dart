import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Production-ready network fallback service with retry policies, circuit breakers, and graceful degradation.
class NetworkFallbackService {
  static const Duration _initialRetryDelay = Duration(seconds: 1);
  static const Duration _maxRetryDelay = Duration(seconds: 30);
  static const int _maxRetries = 3;
  static const Duration _circuitBreakerTimeout = Duration(seconds: 60);
  
  // Circuit breaker state
  static bool _circuitOpen = false;
  static DateTime? _circuitOpenedAt;
  static int _consecutiveFailures = 0;
  
  // Health check endpoints
  static final List<String> _healthEndpoints = [
    'https://www.google.com',
    'https://api.olamaps.io/health',
    'https://router.project-osrm.org/',
  ];
  
  /// Make a network request with automatic retry and fallback.
  static Future<http.Response> requestWithFallback({
    required Future<http.Response> Function() request,
    required Future<http.Response> Function() fallback,
    String? cacheKey,
    Duration cacheTTL = const Duration(minutes: 5),
    bool useCircuitBreaker = true,
  }) async {
    // Check circuit breaker
    if (useCircuitBreaker && _circuitOpen) {
      if (_shouldResetCircuit()) {
        _resetCircuit();
      } else {
        debugPrint("⚠️ Circuit breaker open, using fallback");
        return await fallback();
      }
    }
    
    // Try primary request with retry
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final response = await request().timeout(const Duration(seconds: 10));
        
        if (response.statusCode >= 200 && response.statusCode < 300) {
          // Success - reset circuit breaker
          _resetCircuit();
          
          // Cache successful response if cacheKey provided
          if (cacheKey != null) {
            await _cacheResponse(cacheKey, response, cacheTTL);
          }
          
          return response;
        } else if (response.statusCode >= 500) {
          // Server error - increment failures
          _recordFailure();
          throw http.ClientException('Server error ${response.statusCode}');
        } else {
          // Client error (4xx) - don't retry
          return response;
        }
      } catch (e) {
        debugPrint("⚠️ Request attempt $attempt failed: $e");
        
        if (attempt == _maxRetries) {
          _recordFailure();
          break;
        }
        
        // Exponential backoff
        final delay = Duration(
          milliseconds: _initialRetryDelay.inMilliseconds * (1 << attempt),
        ).clamp(_initialRetryDelay, _maxRetryDelay);
        
        await Future.delayed(delay);
      }
    }
    
    // All retries failed - try cache
    if (cacheKey != null) {
      final cached = await _getCachedResponse(cacheKey);
      if (cached != null) {
        debugPrint("📦 Using cached response for $cacheKey");
        return cached;
      }
    }
    
    // Try fallback
    try {
      debugPrint("🔄 Using fallback for failed request");
      return await fallback();
    } catch (e) {
      debugPrint("❌ Fallback also failed: $e");
      rethrow;
    }
  }
  
  /// Check network health with multiple endpoints.
  static Future<bool> checkNetworkHealth() async {
    for (final endpoint in _healthEndpoints) {
      try {
        final response = await http.get(Uri.parse(endpoint)).timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          debugPrint("✅ Network health check passed via $endpoint");
          return true;
        }
      } catch (e) {
        debugPrint("⚠️ Health check failed for $endpoint: $e");
      }
    }
    
    debugPrint("❌ All network health checks failed");
    return false;
  }
  
  /// Get cached response if available and not expired.
  static Future<http.Response?> getCachedResponse(String cacheKey) async {
    return await _getCachedResponse(cacheKey);
  }
  
  /// Clear all cached responses.
  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith('network_cache_'));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
  
  /// Get circuit breaker status.
  static Map<String, dynamic> getCircuitStatus() {
    return {
      'open': _circuitOpen,
      'openedAt': _circuitOpenedAt?.toIso8601String(),
      'consecutiveFailures': _consecutiveFailures,
      'timeout': _circuitBreakerTimeout.inSeconds,
    };
  }
  
  /// Manually reset circuit breaker.
  static void resetCircuitBreaker() {
    _resetCircuit();
  }
  
  // --- Private helpers ---
  
  static void _recordFailure() {
    _consecutiveFailures++;
    
    if (_consecutiveFailures >= 5 && !_circuitOpen) {
      _circuitOpen = true;
      _circuitOpenedAt = DateTime.now();
      debugPrint("🔴 Circuit breaker opened after $_consecutiveFailures failures");
    }
  }
  
  static void _resetCircuit() {
    _circuitOpen = false;
    _circuitOpenedAt = null;
    _consecutiveFailures = 0;
    debugPrint("🟢 Circuit breaker reset");
  }
  
  static bool _shouldResetCircuit() {
    if (_circuitOpenedAt == null) return false;
    
    final timeSinceOpen = DateTime.now().difference(_circuitOpenedAt!);
    return timeSinceOpen > _circuitBreakerTimeout;
  }
  
  static Future<void> _cacheResponse(
    String cacheKey,
    http.Response response,
    Duration ttl,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final fullKey = 'network_cache_$cacheKey';
    
    final cacheEntry = {
      'body': response.body,
      'statusCode': response.statusCode,
      'headers': response.headers,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'ttl': ttl.inMilliseconds,
    };
    
    await prefs.setString(fullKey, json.encode(cacheEntry));
  }
  
  static Future<http.Response?> _getCachedResponse(String cacheKey) async {
    final prefs = await SharedPreferences.getInstance();
    final fullKey = 'network_cache_$cacheKey';
    final cachedJson = prefs.getString(fullKey);
    
    if (cachedJson == null) return null;
    
    try {
      final cacheEntry = json.decode(cachedJson) as Map<String, dynamic>;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(cacheEntry['timestamp'] as int);
      final ttl = Duration(milliseconds: cacheEntry['ttl'] as int);
      
      if (DateTime.now().difference(timestamp) < ttl) {
        return http.Response(
          cacheEntry['body'] as String,
          cacheEntry['statusCode'] as int,
          headers: Map<String, String>.from(cacheEntry['headers'] as Map),
        );
      } else {
        await prefs.remove(fullKey);
      }
    } catch (e) {
      debugPrint("❌ Cache corruption for $cacheKey: $e");
      await prefs.remove(fullKey);
    }
    
    return null;
  }
  
  /// Create a fallback response for common endpoints.
  static Future<http.Response> createFallbackResponse(String endpoint) {
    // Provide sensible defaults for common endpoints
    if (endpoint.contains('olamaps.io')) {
      return Future.value(http.Response(
        '{"status": "fallback", "message": "Using offline data"}',
        200,
        headers: {'Content-Type': 'application/json'},
      ));
    } else if (endpoint.contains('osrm')) {
      return Future.value(http.Response(
        '{"routes": [], "code": "Fallback"}',
        200,
        headers: {'Content-Type': 'application/json'},
      ));
    }
    
    // Generic fallback
    return Future.value(http.Response(
      '{"error": "Service unavailable", "fallback": true}',
      503,
      headers: {'Content-Type': 'application/json'},
    ));
  }
}