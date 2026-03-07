import 'dart:convert';
import 'package:http/http.dart' as http;

class WikipediaService {
  // 1. Aas-paas ke places lane ke liye
  static Future<List<Map<String, dynamic>>> fetchNearbyPlaces(double lat, double lon) async {
    final String url = 
        'https://en.wikipedia.org/w/api.php?action=query&generator=geosearch&ggscoord=$lat|$lon&ggsradius=10000&ggslimit=5&prop=pageimages|description&piprop=thumbnail&pithumbsize=600&format=json';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['query'] != null && data['query']['pages'] != null) {
          final pages = data['query']['pages'] as Map<String, dynamic>;
          List<Map<String, dynamic>> places = [];

          pages.forEach((key, value) {
            if (value.containsKey('thumbnail')) {
              places.add({
                'id': value['pageid'],
                'title': value['title'],
                'description': value['description'] ?? 'Historical Place',
                'imageUrl': value['thumbnail']['source'],
                'lat': value['lat'],
                'lon': value['lon'],
              });
            }
          });
          return places;
        }
      }
      return [];
    } catch (e) {
      print("Wiki API Error: $e");
      return [];
    }
  }

  static Future<Map<String, dynamic>> fetchRealPlaceImagesPaginated(
      String title, String mainImageUrl, {String? continueToken}) async {
    
    final int? pageId = await _fetchPageIdFromTitle(title);
    if (pageId == null) return {'images': <String>[], 'continueToken': null};

    // gimlimit=20 kiya hai taaki ek baar me 20 images aayein
    String url = 'https://en.wikipedia.org/w/api.php?action=query&generator=images&gimlimit=20&prop=imageinfo&iiprop=url&format=json&pageids=$pageId';

    // Agar token hai, toh agle page ki demand karo
    if (continueToken != null && continueToken.isNotEmpty) {
      url += '&gimcontinue=${Uri.encodeComponent(continueToken)}';
    }

    List<String> images = [];
    String? nextToken;

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Agle page ka token nikalna
        if (data.containsKey('continue') && data['continue'].containsKey('gimcontinue')) {
          nextToken = data['continue']['gimcontinue'];
        }

        if (data['query'] != null && data['query']['pages'] != null) {
          final pages = data['query']['pages'] as Map<String, dynamic>;
          pages.forEach((key, value) {
            if (value.containsKey('imageinfo')) {
              String imgUrl = value['imageinfo'][0]['url'];
              // Faltu Wikipedia logos ko filter out karna aur sirf JPG/PNG lena
              if ((imgUrl.toLowerCase().endsWith('.jpg') || imgUrl.toLowerCase().endsWith('.png')) && imgUrl != mainImageUrl) {
                if (!imgUrl.toLowerCase().contains('logo') && !imgUrl.toLowerCase().contains('icon')) {
                   images.add(imgUrl);
                }
              }
            }
          });
        }
      }
      return {'images': images, 'continueToken': nextToken};
    } catch (e) {
      return {'images': <String>[], 'continueToken': null};
    }
  }

  // 2. Place ki Summary
  static Future<String> fetchPlaceSummary(int pageId) async {
    final String url = 'https://en.wikipedia.org/w/api.php?action=query&prop=extracts&exintro=1&explaintext=1&format=json&pageids=$pageId';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final pages = data['query']['pages'] as Map<String, dynamic>;
        return pages[pageId.toString()]['extract'] ?? "No description available.";
      }
      return "Description not available.";
    } catch (e) {
      return "Failed to load description.";
    }
  }

  // 3. Carousel ke liye Extra Images
  static Future<List<String>> fetchPlaceImages(int pageId, String mainImageUrl) async {
    final String url = 'https://en.wikipedia.org/w/api.php?action=query&generator=images&gimlimit=10&prop=imageinfo&iiprop=url&format=json&pageids=$pageId';
    List<String> images = [mainImageUrl]; // Pehli image wahi hogi jo card par thi

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['query'] != null && data['query']['pages'] != null) {
          final pages = data['query']['pages'] as Map<String, dynamic>;
          
          pages.forEach((key, value) {
            if (value.containsKey('imageinfo')) {
              String imgUrl = value['imageinfo'][0]['url'];
              // Sirf real images lenge (SVG logos/icons ignore karenge)
              if (imgUrl.toLowerCase().endsWith('.jpg') || imgUrl.toLowerCase().endsWith('.png')) {
                if (imgUrl != mainImageUrl) {
                  images.add(imgUrl);
                }
              }
            }
          });
        }
      }
      return images;
    } catch (e) {
      return images; 
    }
  }

  // 4. 🚀 NAYA: Title se Page ID nikalna aur fir real images lana (ERROR FIX)
  static Future<List<String>> fetchRealPlaceImages(String title, String mainImageUrl) async {
    final int? pageId = await _fetchPageIdFromTitle(title);
    if (pageId == null) {
      return [mainImageUrl]; 
    }
    return fetchPlaceImages(pageId, mainImageUrl);
  }

  static Future<int?> _fetchPageIdFromTitle(String title) async {
    final String searchUrl = 'https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeComponent(title)}&utf8=&format=json';
    try {
      final response = await http.get(Uri.parse(searchUrl));
      if (response.statusCode == 200) {
        final searchData = json.decode(response.body);
        if (searchData['query'] != null && searchData['query']['search'] != null && searchData['query']['search'].isNotEmpty) {
          return searchData['query']['search'][0]['pageid'] as int;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}