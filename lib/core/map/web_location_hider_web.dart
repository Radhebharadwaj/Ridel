// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

void hideWebLocationDot() {
  // Prevent duplicate injections
  if (html.document.getElementById('web-location-hider') != null) return;
  
  final styleElement = html.StyleElement();
  styleElement.id = 'web-location-hider';
  styleElement.text = '''
    .mapboxgl-user-location-dot, .maplibregl-user-location-dot,
    .mapboxgl-user-location-accuracy-circle, .maplibregl-user-location-accuracy-circle { 
      display: none !important; 
    }
  ''';
  html.document.head?.append(styleElement);
}

void showWebLocationDot() {
  final element = html.document.getElementById('web-location-hider');
  element?.remove();
}
