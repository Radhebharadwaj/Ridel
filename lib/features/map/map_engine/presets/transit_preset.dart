class TransitPreset {
  
  static const List<String> activeLayerGroups = ['transit', 'poi', 'label', 'building'];
  static const List<String> hiddenLayerGroups = ['traffic', 'parking', 'fuel'];

  static const List<dynamic> poiFilter = [
    'any',
    ['==', ['get', 'class'], 'transit'],
    ['==', ['get', 'class'], 'railway'],
    ['==', ['get', 'class'], 'bus_station'],
    ['==', ['get', 'class'], 'airport'],
    ['==', ['get', 'class'], 'subway'],
  ];

  static const dynamic transitFilter = null; 
}