import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class WikiPlaceDetails {
  final String title;
  final String description;
  final String extract;
  final String? imageUrl;
  final String articleUrl;

  WikiPlaceDetails({
    required this.title,
    required this.description,
    required this.extract,
    this.imageUrl,
    required this.articleUrl,
  });
}

class WikipediaService {
  // Wikipedia REST API (Free, Fast, No API Key required)
  static Future<WikiPlaceDetails?> getPlaceDetails(String placeName) async {
    try {
      // 1. Clean the name for URL (e.g. "Red Fort" -> "Red_Fort")
      // Remove commas and extra details, just keep the main name
      String searchQuery = placeName.split(',').first.trim().replaceAll(' ', '_');

      final url = Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/$searchQuery');
      
      final response = await http.get(url, headers: {
        'Accept': 'application/json',
        // Good practice to provide a user agent
        'User-Agent': 'RidelApp/1.0 (contact@ridel.com)', 
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Check if it's a "disambiguation" page (multiple meanings)
        if (data['type'] == 'disambiguation') {
          return null; // Handle this case based on your logic
        }

        return WikiPlaceDetails(
          title: data['title'] ?? placeName,
          description: data['description'] ?? 'Point of Interest',
          extract: data['extract'] ?? 'No detailed description available.',
          // Fetch the High-Resolution Original Image (if available)
          imageUrl: data['originalimage']?['source'] ?? data['thumbnail']?['source'], 
          articleUrl: data['content_urls']?['desktop']?['page'] ?? 'https://wikipedia.org',
        );
      }
      return null;
    } catch (e) {
      debugPrint("Wikipedia API Error: $e");
      return null;
    }
  }
}