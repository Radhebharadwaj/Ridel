import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OfflineService {
  static final OfflineService _instance = OfflineService._();
  factory OfflineService() => _instance;
  OfflineService._();

  bool _isOnline = true;
  final StreamController<bool> _connectionStream =
      StreamController<bool>.broadcast();

  Stream<bool> get networkStream => _connectionStream.stream;
  Timer? _pingTimer;

  bool get isOnlineSync => _isOnline;

  Future<bool> get isOnline async {
    await _performLightweightCheck();
    return _isOnline;
  }

  void startPolling({Duration interval = const Duration(seconds: 15)}) {
    _pingTimer?.cancel();
    _performLightweightCheck();
    // Frequent but ultra-lightweight polling
    _pingTimer = Timer.periodic(interval, (_) => _performLightweightCheck());
  }

  void stopPolling() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void dispose() {
    stopPolling();
    _connectionStream.close();
  }

  // 🚀 FIX 1: Zero-Payload Native DNS Ping instead of heavy HTTP GET
  Future<void> _performLightweightCheck() async {
    try {
      if (kIsWeb) {
        // Web-safe check (browsers block raw sockets)
        final response = await http.get(Uri.parse('https://clients3.google.com/generate_204'))
            .timeout(const Duration(seconds: 3));
        _updateStatus(response.statusCode == 204 || response.statusCode == 200);
      } else {
        // Native mobile check
        final result = await InternetAddress.lookup('google.com');
        _updateStatus(result.isNotEmpty && result.first.rawAddress.isNotEmpty);
      }
    } catch (_) {
      _updateStatus(false);
    }
  }

  void _updateStatus(bool online) {
    if (_isOnline != online) {
      _isOnline = online;
      if (!_connectionStream.isClosed) {
        _connectionStream.add(online);
      }
    }
  }
}
