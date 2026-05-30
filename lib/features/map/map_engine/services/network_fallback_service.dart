import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class NetworkFallbackService {
  static const Duration initialRetryDelay = Duration(seconds: 1);
  static const Duration maxRetryDelay = Duration(seconds: 30);
  static const int maxRetries = 3;
  static const Duration circuitBreakerTimeout = Duration(seconds: 60);

  // 🚀 FIX 2: LRU (Least Recently Used) Cache setup
  static const int maxRamCacheItems = 50;
  final LinkedHashMap<String, _CacheEntry> _memoryCache =
      LinkedHashMap<String, _CacheEntry>();

  final http.Client _client;
  bool _cacheLoaded = false;

  bool _circuitOpen = false;
  DateTime? _circuitOpenedAt;
  int _consecutiveFailures = 0;

  // 🚀 FIX 3: Disk I/O Debouncer to prevent Main-Thread Stutters
  Timer? _diskWriteTimer;
  final Map<String, _CacheEntry> _pendingDiskWrites = {};

  NetworkFallbackService({http.Client? client})
      : _client = client ?? http.Client();

  Future<void> loadCache() async {
    if (_cacheLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs.getKeys().where((key) => key.startsWith('network_cache_'));

    for (final key in keys) {
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) continue;
      try {
        final data = json.decode(jsonStr) as Map<String, dynamic>;
        final entry = _CacheEntry.fromJson(data);
        final originalKey = key.substring('network_cache_'.length);
        _memoryCache[originalKey] = entry;
      } catch (_) {
        await prefs.remove(key);
      }
    }
    _enforceLRU();
    _cacheLoaded = true;
  }

  Future<http.Response> requestWithFallback({
    required Uri endpoint,
    required Future<http.Response> Function() request,
    required Future<http.Response> Function(Uri endpoint) fallback,
    String? cacheKey,
    Duration cacheTTL = const Duration(minutes: 5),
    bool useCircuitBreaker = true,
  }) async {
    if (useCircuitBreaker && _circuitOpen) {
      if (_shouldResetCircuit()) {
        _resetCircuit();
      } else {
        return await fallback(endpoint); // 🚀 FIX 4: Endpoint-aware fallback
      }
    }

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await request().timeout(const Duration(seconds: 10));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          _resetCircuit();
          if (cacheKey != null) {
            _updateCache(cacheKey, response, cacheTTL);
          }
          return response;
        } else if (response.statusCode >= 500) {
          _recordFailure();
          throw http.ClientException('Server error ${response.statusCode}');
        } else {
          return response;
        }
      } catch (e) {
        if (attempt == maxRetries) {
          _recordFailure();
          break;
        }
        final delayMillis = initialRetryDelay.inMilliseconds * (1 << attempt);
        await Future.delayed(Duration(
            milliseconds: delayMillis.clamp(initialRetryDelay.inMilliseconds,
                maxRetryDelay.inMilliseconds)));
      }
    }

    // RAM Cache Lookup (Mark as recently used)
    if (cacheKey != null && _memoryCache.containsKey(cacheKey)) {
      final entry = _memoryCache.remove(cacheKey)!;
      _memoryCache[cacheKey] = entry; // Move to end (most recently used)

      if (!entry.isExpired) {
        return entry.toResponse();
      }
    }

    try {
      return await fallback(endpoint);
    } catch (_) {
      rethrow;
    }
  }

  void _updateCache(String key, http.Response response, Duration ttl) {
    final entry = _CacheEntry(
      body: response.body,
      statusCode: response.statusCode,
      headers: Map<String, String>.from(response.headers),
      timestamp: DateTime.now(),
      ttl: ttl,
    );

    _memoryCache.remove(key);
    _memoryCache[key] = entry;
    _enforceLRU();

    // 🚀 Schedule Async Disk Write (Debounced)
    _pendingDiskWrites[key] = entry;
    _scheduleDiskWrite();
  }

  void _enforceLRU() {
    while (_memoryCache.length > maxRamCacheItems) {
      _memoryCache.remove(_memoryCache.keys.first); // Removes the oldest item
    }
  }

  void _scheduleDiskWrite() {
    if (_diskWriteTimer?.isActive ?? false) return;

    // Batch writes every 2 seconds to avoid micro-stutters
    _diskWriteTimer = Timer(const Duration(seconds: 2), () async {
      if (_pendingDiskWrites.isEmpty) return;

      final Map<String, _CacheEntry> writesToProcess =
          Map.from(_pendingDiskWrites);
      _pendingDiskWrites.clear();

      final prefs = await SharedPreferences.getInstance();

      for (var entry in writesToProcess.entries) {
        // 🚀 FIX 5: Smart Isolate - Only spin up if body is large (e.g. > 10KB)
        String jsonStr;
        if (entry.value.body.length > 10000) {
          jsonStr = await Isolate.run(() => json.encode(entry.value.toJson()));
        } else {
          jsonStr = json.encode(entry.value.toJson());
        }
        prefs.setString('network_cache_${entry.key}', jsonStr);
      }
    });
  }

  void _recordFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= 5 && !_circuitOpen) {
      _circuitOpen = true;
      _circuitOpenedAt = DateTime.now();
    }
  }

  void _resetCircuit() {
    _circuitOpen = false;
    _circuitOpenedAt = null;
    _consecutiveFailures = 0;
  }

  bool _shouldResetCircuit() {
    if (_circuitOpenedAt == null) return false;
    return DateTime.now().difference(_circuitOpenedAt!) > circuitBreakerTimeout;
  }

  void dispose() {
    _client.close();
    _diskWriteTimer?.cancel();
    _memoryCache.clear();
    _pendingDiskWrites.clear();
  }
}

class _CacheEntry {
  final String body;
  final int statusCode;
  final Map<String, String> headers;
  final DateTime timestamp;
  final Duration ttl;

  _CacheEntry({
    required this.body,
    required this.statusCode,
    required this.headers,
    required this.timestamp,
    required this.ttl,
  });

  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
  http.Response toResponse() =>
      http.Response(body, statusCode, headers: headers);

  Map<String, dynamic> toJson() => {
        'body': body,
        'statusCode': statusCode,
        'headers': headers,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'ttl': ttl.inMilliseconds,
      };

  factory _CacheEntry.fromJson(Map<String, dynamic> json) => _CacheEntry(
        body: json['body'] as String,
        statusCode: json['statusCode'] as int,
        headers: Map<String, String>.from(json['headers'] as Map),
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        ttl: Duration(milliseconds: json['ttl'] as int),
      );
}
