class RouteUtils {
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return "${meters.toStringAsFixed(0)} m";
    } else {
      return "${(meters / 1000).toStringAsFixed(1)} km";
    }
  }
}
