import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

void main() async {
  try {
    const styleUrl = "https://api.olamaps.io/tiles/vector/v1/styles/default-light-standard/style.json?api_key={YOUR_API_KEY}";
    final response = await http.get(Uri.parse(styleUrl));
    debugPrint("Status: ${response.statusCode}");
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      for (var l in data['layers']) {
        final id = l['id'].toString().toLowerCase();
        if (id.contains('metro') || id.contains('subway') || id.contains('transit')) {
          debugPrint("ID: ${l['id']}");
          debugPrint("Filter: ${l['filter']}");
          debugPrint("Paint: ${l['paint']}");
        }
      }
    } else {
//      debugPrint("Received map style");
    }
  } catch (e) {
    debugPrint("Error: $e");
  }
}
