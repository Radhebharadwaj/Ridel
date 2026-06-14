import 'dart:math';
import 'package:maplibre_gl/maplibre_gl.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// 🧮 RoutingService — The Pure Math Engine
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Zero state. Zero side effects. 100% static, testable geodesic math.
/// This is the performance-critical core of Ridel's navigation system.
///
/// Every function operates on primitives or LatLng and returns primitives.
/// No ValueNotifier, no async, no side effects.
/// ─────────────────────────────────────────────────────────────────────────────

/// Result of a snap-to-route computation. Designed for zero-allocation reuse.
class SnapResult {
  /// Index of the closest segment start point in the polyline.
  int segmentIndex;

  /// The user's position projected onto the nearest polyline segment.
  double snappedLat;
  double snappedLng;

  /// Perpendicular distance from the user to the nearest segment (meters).
  /// This is the "cross-track error" — the drift off the polyline.
  double crossTrackDistance;

  /// Fraction [0.0 → 1.0] of progress along the matched segment.
  /// 0.0 = at segment start, 1.0 = at segment end.
  double alongTrackFraction;

  /// Whether the sliding window should advance forward.
  bool shouldAdvanceWindow;

  /// The bearing (degrees) of the matched segment — used for camera heading.
  double segmentBearing;

  SnapResult()
      : segmentIndex = 0,
        snappedLat = 0.0,
        snappedLng = 0.0,
        crossTrackDistance = double.infinity,
        alongTrackFraction = 0.0,
        shouldAdvanceWindow = false,
        segmentBearing = 0.0;

  LatLng get snappedLatLng => LatLng(snappedLat, snappedLng);

  void reset() {
    segmentIndex = 0;
    snappedLat = 0.0;
    snappedLng = 0.0;
    crossTrackDistance = double.infinity;
    alongTrackFraction = 0.0;
    shouldAdvanceWindow = false;
    segmentBearing = 0.0;
  }
}

class RoutingService {
  // ═══════════════════════════════════════════════════════════════════════════
  // CONSTANTS
  // ═══════════════════════════════════════════════════════════════════════════

  static const double _earthRadius = 6371000.0; // meters
  static const double _deg2rad = pi / 180.0;
  static const double _rad2deg = 180.0 / pi;

  /// Cross-track distance threshold for triggering a reroute (meters).
  static const double offRouteThresholdMeters = 30.0;

  /// Default window size for local segment scanning.
  static const int defaultWindowSize = 4;

  /// Fraction along segment beyond which the window should advance.
  static const double windowAdvanceThreshold = 0.85;

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎯 PRIMARY API — Called Every GPS Tick
  // ═══════════════════════════════════════════════════════════════════════════

  /// **The Hot Path** — Snaps a user position to the nearest polyline segment
  /// within a local window of [windowSize] segments starting from [windowStart].
  ///
  /// Computational complexity: **O(windowSize)** — typically O(4).
  ///
  /// [userLat], [userLng]: User's GPS coordinates.
  /// [polyline]: The full route polyline as a flat list of LatLng.
  /// [windowStart]: Index of the first segment to check.
  /// [windowSize]: Number of segments to check (default 4).
  /// [result]: Pre-allocated SnapResult to avoid GC pressure.
  ///
  /// Returns the mutated [result] for zero-allocation performance.
  static SnapResult snapToRoute(
    double userLat,
    double userLng,
    List<LatLng> polyline,
    int windowStart,
    SnapResult result, {
    int windowSize = defaultWindowSize,
  }) {
    result.reset();

    if (polyline.length < 2) {
      result.snappedLat = userLat;
      result.snappedLng = userLng;
      result.crossTrackDistance = 0.0;
      return result;
    }

    // Clamp window to valid range
    final int maxSegmentIndex = polyline.length - 2;
    final int wStart = windowStart.clamp(0, maxSegmentIndex);
    final int wEnd = (wStart + windowSize).clamp(0, maxSegmentIndex + 1);

    double bestDist = double.infinity;
    int bestIdx = wStart;
    double bestT = 0.0;
    double bestProjLat = userLat;
    double bestProjLng = userLng;

    // ── Local Cartesian Approximation ──
    // For short distances (< 10 km), we can treat lat/lng as a local
    // Cartesian plane with a cos(lat) correction for longitude.
    // This avoids expensive trig per-segment.
    final double cosLat = cos(userLat * _deg2rad);

    for (int i = wStart; i < wEnd; i++) {
      final LatLng a = polyline[i];
      final LatLng b = polyline[i + 1];

      // Convert to local meters (approximate, valid for navigation distances)
      final double ax = (a.longitude - userLng) * cosLat * 111320.0;
      final double ay = (a.latitude - userLat) * 110540.0;
      final double bx = (b.longitude - userLng) * cosLat * 111320.0;
      final double by = (b.latitude - userLat) * 110540.0;

      // Vector AB
      final double abx = bx - ax;
      final double aby = by - ay;

      // Vector AP (user is at origin in local coords)
      final double apx = -ax; // 0 - ax
      final double apy = -ay; // 0 - ay

      // Dot products for projection
      final double abLenSq = abx * abx + aby * aby;

      double t;
      double projX, projY;

      if (abLenSq < 1e-10) {
        // Degenerate segment (A == B)
        t = 0.0;
        projX = ax;
        projY = ay;
      } else {
        // Project P onto line AB: t = dot(AP, AB) / dot(AB, AB)
        t = (apx * abx + apy * aby) / abLenSq;
        t = t.clamp(0.0, 1.0);
        projX = ax + t * abx;
        projY = ay + t * aby;
      }

      // Distance from user (origin) to projected point
      final double dist = sqrt(projX * projX + projY * projY);

      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = i;
        bestT = t;

        // Convert projected point back to lat/lng
        bestProjLat = userLat + projY / 110540.0;
        bestProjLng = userLng + projX / (cosLat * 111320.0);
      }
    }

    result.segmentIndex = bestIdx;
    result.snappedLat = bestProjLat;
    result.snappedLng = bestProjLng;
    result.crossTrackDistance = bestDist;
    result.alongTrackFraction = bestT;
    result.segmentBearing = bearing(
      polyline[bestIdx].latitude,
      polyline[bestIdx].longitude,
      polyline[bestIdx + 1].latitude,
      polyline[bestIdx + 1].longitude,
    );

    // ── Window Advance Logic ──
    // If the user is near the end of the best segment AND the best segment
    // is near the end of the current window, slide forward.
    result.shouldAdvanceWindow = bestT > windowAdvanceThreshold &&
        bestIdx >= wEnd - 2 &&
        wEnd <= maxSegmentIndex;

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔬 GEODESIC MATH PRIMITIVES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Haversine great-circle distance between two points (meters).
  static double haversine(double lat1, double lng1, double lat2, double lng2) {
    final double dLat = (lat2 - lat1) * _deg2rad;
    final double dLng = (lng2 - lng1) * _deg2rad;

    final double a = sin(dLat * 0.5) * sin(dLat * 0.5) +
        cos(lat1 * _deg2rad) *
            cos(lat2 * _deg2rad) *
            sin(dLng * 0.5) *
            sin(dLng * 0.5);

    return _earthRadius * 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
  }

  /// Initial bearing from point 1 to point 2 (degrees, 0–360).
  static double bearing(double lat1, double lng1, double lat2, double lng2) {
    final double phi1 = lat1 * _deg2rad;
    final double phi2 = lat2 * _deg2rad;
    final double deltaLambda = (lng2 - lng1) * _deg2rad;

    final double y = sin(deltaLambda) * cos(phi2);
    final double x =
        cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda);

    return (atan2(y, x) * _rad2deg + 360.0) % 360.0;
  }

  /// Cross-track distance from point P to the geodesic segment A→B (meters).
  /// Positive = right of track, Negative = left of track.
  ///
  /// Uses the spherical cross-track formula:
  ///   dxt = asin(sin(d13/R) * sin(θ13 − θ12)) * R
  static double crossTrackDistance(
    double aLat,
    double aLng,
    double bLat,
    double bLng,
    double pLat,
    double pLng,
  ) {
    final double d13 = haversine(aLat, aLng, pLat, pLng) / _earthRadius;
    final double theta13 = bearing(aLat, aLng, pLat, pLng) * _deg2rad;
    final double theta12 = bearing(aLat, aLng, bLat, bLng) * _deg2rad;

    return asin(sin(d13) * sin(theta13 - theta12)) * _earthRadius;
  }

  /// Along-track distance from A towards B of the closest point on the
  /// great circle to point P (meters).
  ///
  ///   dat = acos(cos(d13) / cos(dxt/R)) * R
  static double alongTrackDistance(
    double aLat,
    double aLng,
    double bLat,
    double bLng,
    double pLat,
    double pLng,
  ) {
    final double d13 = haversine(aLat, aLng, pLat, pLng) / _earthRadius;
    final double dxt =
        crossTrackDistance(aLat, aLng, bLat, bLng, pLat, pLng) / _earthRadius;

    // Clamp to avoid NaN from floating-point edge cases
    final double cosArg = (cos(d13) / cos(dxt)).clamp(-1.0, 1.0);
    return acos(cosArg) * _earthRadius;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚗 NAVIGATION UTILITIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Computes the total remaining distance along the polyline from a given
  /// segment index and along-track fraction to the end (meters).
  static double remainingPolylineDistance(
    List<LatLng> polyline,
    int segmentIndex,
    double alongFraction,
  ) {
    if (polyline.length < 2 || segmentIndex >= polyline.length - 1) {
      return 0.0;
    }

    // Distance remaining on current segment
    final LatLng a = polyline[segmentIndex];
    final LatLng b = polyline[segmentIndex + 1];
    final double segLen =
        haversine(a.latitude, a.longitude, b.latitude, b.longitude);
    double total = segLen * (1.0 - alongFraction);

    // Sum remaining segments
    for (int i = segmentIndex + 1; i < polyline.length - 1; i++) {
      final LatLng p1 = polyline[i];
      final LatLng p2 = polyline[i + 1];
      total += haversine(p1.latitude, p1.longitude, p2.latitude, p2.longitude);
    }

    return total;
  }

  /// Maps a polyline segment index to the corresponding step index
  /// using pre-computed step boundary indices.
  ///
  /// [stepBoundaries] is a sorted list where `stepBoundaries[i]` is the
  /// polyline index where step `i` begins. Built once at navigation start.
  static int segmentToStepIndex(int segmentIndex, List<int> stepBoundaries) {
    // Binary search for the step that contains this segment index
    int lo = 0;
    int hi = stepBoundaries.length - 1;

    while (lo < hi) {
      final int mid = (lo + hi + 1) >> 1; // ceil division
      if (stepBoundaries[mid] <= segmentIndex) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Pre-computes step boundary indices by matching step start locations
  /// to the nearest polyline point. Run once at navigation start.
  ///
  /// Returns a list where index `i` = the polyline index where step `i` begins.
  static List<int> buildStepBoundaries(
    List<LatLng> polyline,
    List<LatLng> stepStartLocations,
  ) {
    final List<int> boundaries = List.filled(stepStartLocations.length, 0);

    int searchFrom = 0;
    for (int s = 0; s < stepStartLocations.length; s++) {
      final LatLng stepStart = stepStartLocations[s];
      double bestDist = double.infinity;
      int bestIdx = searchFrom;

      // Only search forward from the last match (steps are sequential)
      final int searchEnd = (searchFrom + 100).clamp(0, polyline.length);
      for (int i = searchFrom; i < searchEnd; i++) {
        final double d = haversine(
          stepStart.latitude,
          stepStart.longitude,
          polyline[i].latitude,
          polyline[i].longitude,
        );
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }

      boundaries[s] = bestIdx;
      searchFrom = bestIdx; // Steps are monotonically advancing
    }

    return boundaries;
  }

  /// Estimates remaining travel time given remaining distance and current speed.
  /// Falls back to an average speed if GPS speed is unavailable.
  ///
  /// Returns estimated time in **seconds**.
  static double estimateRemainingTime(
    double remainingDistanceMeters,
    double currentSpeedMps, {
    double fallbackSpeedMps = 8.33, // ~30 km/h urban default
  }) {
    final double speed =
        currentSpeedMps > 1.0 ? currentSpeedMps : fallbackSpeedMps;
    return remainingDistanceMeters / speed;
  }
}