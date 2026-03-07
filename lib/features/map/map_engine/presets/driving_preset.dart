class DrivingPreset {
  static const List<String> activeLayerGroups = ['road', 'traffic', 'poi', 'label'];
  static const List<String> hiddenLayerGroups = ['transit', 'building']; // Hide buildings for clean road view

  // 🛑 FIX: Removed the ultra-strict filter that was hiding everything.
  // Now Ola's default POIs (including fuel and parking) will show up naturally.
  static const dynamic poiFilter = null; 
  
  // Hide all transit networks entirely
  static const List<dynamic> transitFilter = ['==', ['get', 'class'], 'none'];
}