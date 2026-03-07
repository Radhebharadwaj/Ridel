import 'dart:math';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/ridel_sheet.dart'; 
import '../services/wikipedia_service.dart'; // ✅ Wikipedia Service (Images lane ke liye)
import 'place_images_sheet_content.dart'; // ✅ Teri full gallery sheet

// ==========================================
// 1. SMART API SERVICES (Wiki + OSM)
// ==========================================
class WikiPlaceDetails {
  final String title;
  final String extract;
  final String? imageUrl;
  final String articleUrl;
  WikiPlaceDetails({required this.title, required this.extract, this.imageUrl, required this.articleUrl});
}

class OSMPlaceDetails {
  final String? phone;
  final String? openingHours;
  final String? website;
  OSMPlaceDetails({this.phone, this.openingHours, this.website});
}

class PlaceDataService {
  static Future<WikiPlaceDetails?> getWikiDetails(String placeName) async {
    try {
      String query = placeName.split(',').first.trim().replaceAll(' ', '_');
      final url = Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/$query');
      final response = await http.get(url, headers: {'Accept': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['type'] == 'disambiguation') return null; 
        return WikiPlaceDetails(
          title: data['title'] ?? placeName,
          extract: data['extract'] ?? 'No detailed description available.',
          imageUrl: data['originalimage']?['source'] ?? data['thumbnail']?['source'], 
          articleUrl: data['content_urls']?['desktop']?['page'] ?? 'https://wikipedia.org',
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<OSMPlaceDetails?> getOSMDetails(double lat, double lon) async {
    try {
      final query = '[out:json][timeout:5];(nwr(around:50, $lat, $lon)[name];);out tags limit 1;';
      final url = Uri.parse('https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['elements'] != null && data['elements'].isNotEmpty) {
          final tags = data['elements'][0]['tags'];
          return OSMPlaceDetails(
            phone: tags['phone'] ?? tags['contact:phone'],
            openingHours: tags['opening_hours'],
            website: tags['website'] ?? tags['contact:website'],
          );
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getNearbyPlaces(double lat, double lon) async {
    final String url = 'https://en.wikipedia.org/w/api.php?action=query&generator=geosearch&ggscoord=$lat|$lon&ggsradius=10000&ggslimit=5&prop=pageimages|description&piprop=thumbnail&pithumbsize=600&format=json';
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
                'description': value['description'] ?? 'Historical site',
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
      return [];
    }
  }
}

// ==========================================
// 2. MAIN DETAIL CONTENT WIDGET
// ==========================================
class PlaceDetailContent extends StatefulWidget {
  final Map<String, dynamic> place;
  final double userLat;
  final double userLng;

  const PlaceDetailContent({
    super.key,
    required this.place,
    required this.userLat,
    required this.userLng,
  });

  @override
  State<PlaceDetailContent> createState() => _PlaceDetailContentState();
}

class _PlaceDetailContentState extends State<PlaceDetailContent> {
  static const Color neonCyan = Color(0xFF00E5FF);
  
  bool _isLoadingInfo = true;
  WikiPlaceDetails? _wikiDetails;
  OSMPlaceDetails? _osmDetails;
  
  bool _showNearbyCapsules = false;
  bool _isLoadingNearby = false;
  List<Map<String, dynamic>> _nearbyPlaces = [];
  int? _expandedCapsuleIndex;

  // 🚀 Carousel States
  List<String> _carouselImages = [];
  int _currentCarouselIndex = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _fetchRealPlaceData();
  }

  void _fetchRealPlaceData() async {
    double lat = widget.place['lat'] != null ? (widget.place['lat'] as num).toDouble() : widget.userLat;
    double lng = widget.place['lng'] != null ? (widget.place['lng'] as num).toDouble() : widget.userLng;
    String fallbackImage = widget.place['img'] ?? widget.place['imageUrl'] ?? '';

    // Parallel API Calls - Ab images bhi ek sath aayengi!
    final results = await Future.wait([
      PlaceDataService.getWikiDetails(widget.place['title']),
      PlaceDataService.getOSMDetails(lat, lng),
      WikipediaService.fetchRealPlaceImagesPaginated(widget.place['title'], fallbackImage),
    ]);

    if (mounted) {
      setState(() {
        _wikiDetails = results[0] as WikiPlaceDetails?;
        _osmDetails = results[1] as OSMPlaceDetails?;
        
        // Setup Carousel Images
        final imageResult = results[2] as Map<String, dynamic>;
        List<String> fetchedImages = imageResult['images'] as List<String>? ?? [];
        String mainImg = _wikiDetails?.imageUrl ?? fallbackImage;
        
        // Remove duplicates & ensure main image is first
        _carouselImages = [mainImg, ...fetchedImages].toSet().toList(); 
        
        _isLoadingInfo = false;
      });
    }
  }

  void _toggleNearby() async {
    AppHaptics.mediumImpact();
    setState(() {
      _showNearbyCapsules = !_showNearbyCapsules;
      if (_showNearbyCapsules && _nearbyPlaces.isEmpty) _isLoadingNearby = true;
    });

    if (_showNearbyCapsules && _nearbyPlaces.isEmpty) {
      double lat = widget.place['lat'] != null ? (widget.place['lat'] as num).toDouble() : widget.userLat;
      double lng = widget.place['lng'] != null ? (widget.place['lng'] as num).toDouble() : widget.userLng;
      
      final places = await PlaceDataService.getNearbyPlaces(lat, lng);
      if (mounted) setState(() { _nearbyPlaces = places; _isLoadingNearby = false; });
    }
  }

  double _calcDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 + c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); 
  }

  void _openWebsite() async {
    if (_osmDetails?.website == null) return;
    final Uri url = Uri.parse(_osmDetails!.website!);
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _initiatePhoneCall() async {
    if (_osmDetails?.phone == null) return;
    final Uri url = Uri.parse("tel:${_osmDetails!.phone!}");
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  // 🚀 Function to Open Full Gallery
  void _openImageGallerySheet() {
    AppHaptics.heavyImpact();
    String fallbackImage = widget.place['img'] ?? widget.place['imageUrl'] ?? '';
    RidelSheet.show(
      context,
      title: "${widget.place['title']} Gallery",
      showCloseButton: true,
      sheetColor: const Color(0xFF121212),
      child: PlaceImagesSheetContent(
        title: widget.place['title'],
        mainImageUrl: _wikiDetails?.imageUrl ?? fallbackImage,
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool hasPhone = _osmDetails?.phone != null && _osmDetails!.phone!.isNotEmpty;
    double pLat = widget.place['lat'] != null ? (widget.place['lat'] as num).toDouble() : widget.userLat;
    double pLng = widget.place['lng'] != null ? (widget.place['lng'] as num).toDouble() : widget.userLng;
    double distanceFromUser = _calcDistance(widget.userLat, widget.userLng, pLat, pLng);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 85, left: 16, right: 16, bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Action Buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () { AppHaptics.heavyImpact(); },
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(color: neonCyan, borderRadius: BorderRadius.circular(100)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(CupertinoIcons.car_detailed, color: Colors.black), SizedBox(width: 8), Text("Go", style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w600))]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: hasPhone ? _initiatePhoneCall : null,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(color: hasPhone ? Colors.white12 : Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(100)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(CupertinoIcons.phone, color: hasPhone ? Colors.white : Colors.grey), const SizedBox(width: 8), Text("Call", style: TextStyle(color: hasPhone ? Colors.white : Colors.grey, fontSize: 16, fontWeight: FontWeight.w600))]),
                  ),
                ),
              )
            ],
          ),
          const SizedBox(height: 24),

          // 2. Hours & Distance
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(children: [const Text("Hours", style: TextStyle(color: Colors.white54, fontSize: 13)), const SizedBox(height: 4), Text(_isLoadingInfo ? "..." : (_osmDetails?.openingHours ?? "Not available"), style: TextStyle(color: _osmDetails?.openingHours != null ? neonCyan : Colors.grey, fontSize: 14, fontWeight: FontWeight.w600))]),
              Column(children: [const Text("Distance", style: TextStyle(color: Colors.white54, fontSize: 13)), const SizedBox(height: 4), Row(children: [const Icon(Icons.directions, size: 16, color: Colors.white), const SizedBox(width: 4), Text("${distanceFromUser.toStringAsFixed(1)} km", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))])])
            ],
          ),
          const SizedBox(height: 24),
          
          // 🚀 3. THE MAGIC IMAGE CAROUSEL
          _buildImageCarousel(),
          const SizedBox(height: 24),

          // 4. Discover Nearby Dropdown
          GestureDetector(
            onTap: _toggleNearby,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(color: _showNearbyCapsules ? neonCyan.withOpacity(0.15) : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: _showNearbyCapsules ? neonCyan.withOpacity(0.5) : Colors.white12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [Icon(Icons.explore, color: _showNearbyCapsules ? neonCyan : Colors.white), const SizedBox(width: 12), Text("Discover Nearby", style: TextStyle(color: _showNearbyCapsules ? neonCyan : Colors.white, fontSize: 16, fontWeight: FontWeight.bold))]),
                  Icon(_showNearbyCapsules ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white54),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 5. Expandable Content
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: _showNearbyCapsules ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: _buildAboutSection(), 
            secondChild: _buildNearbyCapsulesList(),
          ),
        ],
      ),
    );
  }

  // 🚀 Image Carousel Builder
  Widget _buildImageCarousel() {
    String fallbackImage = widget.place['img'] ?? widget.place['imageUrl'] ?? '';
    List<String> displayList = _carouselImages.isEmpty ? [fallbackImage] : _carouselImages;
    
    // Max 5 images, agar 5 se zyada hain toh 6th slide 'See More' ban jayegi
    int itemCount = displayList.length > 5 ? 6 : displayList.length; 

    return SizedBox(
      height: 220,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentCarouselIndex = idx),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              
              // Aakhiri Slide: See All Photos Button
              if (index == 5 && displayList.length > 5) {
                return GestureDetector(
                  onTap: _openImageGallerySheet,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(displayList[index], fit: BoxFit.cover),
                        BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(color: Colors.black.withOpacity(0.6)),
                        ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.photo_library_outlined, color: neonCyan, size: 40),
                              const SizedBox(height: 12),
                              Text("See All ${_carouselImages.length} Photos", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                );
              }

              // Normal Image Slide
              return ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(
                  displayList[index],
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade900, child: const Icon(Icons.broken_image, color: Colors.white54)),
                ),
              );
            },
          ),
          
          // Smooth Paging Dots
          if (itemCount > 1)
            Positioned(
              bottom: 12, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(itemCount, (index) {
                  bool isActive = _currentCarouselIndex == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 6,
                    width: isActive ? 20 : 6,
                    decoration: BoxDecoration(
                      color: isActive ? neonCyan : Colors.white54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    bool hasWebsite = _osmDetails?.website != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("About", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _isLoadingInfo
            ? const Center(child: CupertinoActivityIndicator(color: neonCyan))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_wikiDetails?.extract ?? "Detailed information not available for this location.", style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
                  const SizedBox(height: 12),
                  if (_wikiDetails != null)
                    GestureDetector(
                      onTap: () async { final Uri url = Uri.parse(_wikiDetails!.articleUrl); if (await canLaunchUrl(url)) await launchUrl(url); },
                      child: const Text("More on Wikipedia", style: TextStyle(color: neonCyan, fontSize: 14, fontWeight: FontWeight.w500)),
                    ),
                ],
              ),
        
        const SizedBox(height: 32),
        const Text("Details", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildDetailRow("Phone", _osmDetails?.phone ?? "Not available", valueColor: _osmDetails?.phone != null ? neonCyan : Colors.grey),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: hasWebsite ? _openWebsite : null,
          child: _buildDetailRow("Website", hasWebsite ? "Open Website" : "Not available", valueColor: hasWebsite ? neonCyan : Colors.grey),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 15)),
        Text(value, style: TextStyle(color: valueColor ?? Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildNearbyCapsulesList() {
    if (_isLoadingNearby) return const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: neonCyan)));
    if (_nearbyPlaces.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text("No nearby places found.", style: TextStyle(color: Colors.white54))));

    return Column(
      children: List.generate(_nearbyPlaces.length, (index) {
        final place = _nearbyPlaces[index];
        bool isExpanded = _expandedCapsuleIndex == index;
        double pLat = place['lat'] != null ? (place['lat'] as num).toDouble() : widget.userLat;
        double pLng = place['lon'] != null ? (place['lon'] as num).toDouble() : widget.userLng;
        double dist = _calcDistance(widget.userLat, widget.userLng, pLat, pLng);

        return GestureDetector(
          onTap: () { AppHaptics.lightImpact(); setState(() => _expandedCapsuleIndex = isExpanded ? null : index); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: isExpanded ? const Color(0xFF1E1E1E) : Colors.black26, borderRadius: BorderRadius.circular(24), border: Border.all(color: isExpanded ? neonCyan.withOpacity(0.4) : Colors.white12)),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.white12, shape: BoxShape.circle), child: const Icon(Icons.place, color: neonCyan, size: 18)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(place['title'], style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis), Text("${dist.toStringAsFixed(1)} km away", style: const TextStyle(color: Colors.white54, fontSize: 13))])),
                    Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white54),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic,
                  child: isExpanded
                      ? Column(
                          children: [
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(place['imageUrl'], width: 60, height: 60, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(width:60, height:60, color:Colors.grey))),
                                const SizedBox(width: 12),
                                Expanded(child: Text(place['description'] ?? "Historical site near you.", style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 3, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                style: TextButton.styleFrom(backgroundColor: neonCyan.withOpacity(0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))),
                                onPressed: () {
                                  AppHaptics.heavyImpact();
                                  RidelSheet.show(
                                    context,
                                    title: place['title'],
                                    showCloseButton: true,
                                    sheetColor: const Color(0xFF121212),
                                    child: PlaceDetailContent(
                                      place: place,
                                      userLat: widget.userLat,
                                      userLng: widget.userLng,
                                    ),
                                  );
                                },
                                child: const Text("View Full Details", style: TextStyle(color: neonCyan, fontWeight: FontWeight.bold)),
                              ),
                            )
                          ],
                        )
                      : const SizedBox(width: double.infinity, height: 0),
                )
              ],
            ),
          ),
        );
      }),
    );
  }
}