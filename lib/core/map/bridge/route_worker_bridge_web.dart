import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:web/web.dart' as web;

class RouteWorkerBridge {
  static web.Worker? _worker;
  static int _requestCounter = 0;
  static final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  static void initialize() {
    if (!kIsWeb) return;
    try {
      _worker = web.Worker('js/ridel_route_worker.js'.toJS);
      
      final callback = ((web.MessageEvent event) {
        final data = event.data as JSObject;
        
        final successProp = data.getProperty('success'.toJS) as JSBoolean?;
        final success = successProp?.toDart ?? false;
        
        final idProp = data.getProperty('requestId'.toJS) as JSNumber;
        final id = idProp.toDartInt;
        
        if (!success) {
          final errorProp = data.getProperty('error'.toJS) as JSString?;
          _pending.remove(id)?.completeError(Exception(errorProp?.toDart ?? "Worker error"));
          return;
        }

        final primaryBuffer = data.getProperty('primaryBuffer'.toJS) as JSFloat64Array;
        final primaryPointCount = (data.getProperty('primaryPointCount'.toJS) as JSNumber).toDartInt;
        final altBuffers = (data.getProperty('altBuffers'.toJS) as JSArray<JSFloat64Array>).toDart;
        final altPointCounts = (data.getProperty('altPointCounts'.toJS) as JSArray<JSNumber>).toDart;
        
        final allDurationsRaw = (data.getProperty('allDurations'.toJS) as JSArray<JSNumber>).toDart;
        final allDurations = allDurationsRaw.map((e) => e.toDartDouble).toList();
        
        final distanceKm = (data.getProperty('distanceKm'.toJS) as JSNumber).toDartDouble;
        final durationMins = (data.getProperty('durationMins'.toJS) as JSNumber).toDartInt;
        final firstInstruction = (data.getProperty('firstInstruction'.toJS) as JSString).toDart;
        
        final congestionProp = data.getProperty('congestion'.toJS);
        List<String>? congestion;
        if (!congestionProp.isUndefinedOrNull) {
          try {
            final jsonStr = (congestionProp as JSString).toDart;
            final decoded = jsonDecode(jsonStr) as List;
            congestion = decoded.map((e) => e.toString()).toList();
          } catch (e) {
            debugPrint("Failed to decode congestion: $e");
          }
        }
        
        // Decode JS objects into Dart lists
        final List<List<LatLng>> allRoutes = [];
        
        // Decode primary
        allRoutes.add(_decodeBuffer(primaryBuffer, primaryPointCount));
        
        // Decode alternates
        for (int i = 0; i < altBuffers.length; i++) {
          allRoutes.add(_decodeBuffer(altBuffers[i], altPointCounts[i].toDartInt));
        }
        
        // Convert steps safely
        final stepsProp = data.getProperty('steps'.toJS);
        List<Map<String, dynamic>> steps = [];
        if (!stepsProp.isUndefinedOrNull) {
          try {
             final jsonStr = (stepsProp as JSString).toDart;
             final decoded = jsonDecode(jsonStr) as List;
             steps = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
          } catch (e) {
            debugPrint("Failed to decode steps: $e");
          }
        }
        
        _pending.remove(id)?.complete({
          'allRoutesCoordinates': allRoutes,
          'distanceKm': distanceKm,
          'durationMins': durationMins,
          'allDurationSeconds': allDurations,
          'firstInstruction': firstInstruction,
          'congestion': congestion,
          'steps': steps,
        });
      }).toJS;
      
      _worker!.setProperty('onmessage'.toJS, callback);
    } catch (e) {
      debugPrint("Worker initialization failed: $e");
    }
  }

  static List<LatLng> _decodeBuffer(JSFloat64Array jsBuffer, int pointCount) {
    final floatList = jsBuffer.toDart;
    final List<LatLng> route = List.generate(pointCount, (i) {
      // Remember Web Worker sets it as [lng, lat]
      return LatLng(floatList[i * 2 + 1], floatList[i * 2]);
    });
    return route;
  }

  static Future<Map<String, dynamic>> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    required String mode,
    required String apiKey,
    List<LatLng>? waypoints,
  }) {
    if (_worker == null) {
      return Future.error(Exception("Web Worker not initialized"));
    }
    
    final id = _requestCounter++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final waypointsJs = waypoints?.map((wp) => {
      'lat': wp.latitude,
      'lng': wp.longitude,
    }).toList();

    final requestData = {
      'requestId': id,
      'origin': {'lat': origin.latitude, 'lng': origin.longitude},
      'destination': {'lat': destination.latitude, 'lng': destination.longitude},
      'mode': mode,
      'apiKey': apiKey,
      'waypoints': waypointsJs,
    }.jsify();

    _worker!.callMethod('postMessage'.toJS, requestData);

    return completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
      _pending.remove(id);
      throw TimeoutException("Web Worker route calculation timed out");
    });
  }

  static void dispose() {
    _worker?.callMethod('terminate'.toJS);
    _pending.clear();
  }
}
