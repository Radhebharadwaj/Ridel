import 'dart:ui';
import 'dart:convert';
import 'package:flutter/cupertino.dart'; 
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/ridel_sheet.dart'; 
import '../services/wikipedia_service.dart';
import '../widgets/place_images_sheet_content.dart'; 

// ==========================================
// API SERVICE (Directly in file as requested)
// ==========================================
class PlaceDataService {
  static Future<Map<String, dynamic>?> getWikiDetails(String placeName) async {
    try {
      String query = placeName.split(',').first.trim().replaceAll(' ', '_');
      final url = Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/$query');
      final response = await http.get(url, headers: {'Accept': 'application/json'});
      if (response.statusCode == 200) return json.decode(response.body);
    } catch (_) {}
    return null;
  }
}

// ==========================================
// MAIN DETAIL SCREEN WIDGET
// ==========================================
class PlaceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> place;
  final double userLat;
  final double userLng;

  const PlaceDetailScreen({
    super.key, 
    required this.place, 
    required this.userLat, 
    required this.userLng
  });

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  final Color neonCyan = const Color(0xFF00E5FF);
  final Color appBgColor = const Color(0xFF0B0E17); // Consistent Deep Dark Theme
  
  bool _isLoading = true;
  String _description = "A beautiful and mesmerizing place to visit. Perfect for your next adventure.";
  
  // 🚀 Fluid Swipe States
  double _dragOffset = 0;
  bool _isPopping = false; 
  
  List<String> _images = [];
  int _currentImageIndex = 0;
  final PageController _pageController = PageController();

  final List<Map<String, String>> _suggestions = [
    {"title": "Hidden Waterfalls", "img": "https://images.unsplash.com/photo-1593693397690-362cb9666cb3?q=80&w=800&auto=format&fit=crop"},
    {"title": "Sunset Point", "img": "https://images.unsplash.com/photo-1605649487212-4d43be970bfe?q=80&w=800&auto=format&fit=crop"},
    {"title": "Ancient Ruins", "img": "https://images.unsplash.com/photo-1620766165457-a80fe5604888?q=80&w=800&auto=format&fit=crop"},
  ];

  @override
  void initState() {
    super.initState();
    // 🔥 FIX: 'img' ki jagah 'image' key use ki hai kyunki all_places.dart yahi bhej raha hai
    _images.add(widget.place['image'] ?? ''); 
    _fetchDetails();
  }

  void _fetchDetails() async {
    final results = await Future.wait([
      PlaceDataService.getWikiDetails(widget.place['title']),
      WikipediaService.fetchRealPlaceImagesPaginated(widget.place['title'], widget.place['image'] ?? ''),
    ]);

    if (mounted) {
      final wikiData = results[0] as Map<String, dynamic>?;
      final imgData = results[1] as Map<String, dynamic>;

      setState(() { 
        if (wikiData != null && wikiData['extract'] != null) {
          _description = wikiData['extract'];
        }
        List<String> extraImages = [];
        if (imgData['images'] != null) {
          extraImages = List<String>.from(imgData['images']); 
        }
        _images = [widget.place['image'].toString(), ...extraImages].toSet().toList();
        _isLoading = false; 
      });
    }
  }

  void _callAction() async {
    AppHaptics.heavyImpact();
    final Uri url = Uri.parse("tel:100"); 
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  void _openGallery() {
    AppHaptics.heavyImpact();
    RidelSheet.show(
      context, 
      title: "${widget.place['title']} Gallery", 
      showCloseButton: true,
      sheetColor: appBgColor,
      child: PlaceImagesSheetContent(
        title: widget.place['title'], 
        mainImageUrl: widget.place['image'] ?? ''
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
    int maxSlides = _images.length > 5 ? 6 : _images.length;

    return Scaffold(
      // 🔥 MAGIC: Background transparent, taaki swipe down pe pichla screen dikhe
      backgroundColor: Colors.transparent, 
      body: NotificationListener<ScrollNotification>(
        // 🚀 THE FLUID FINGER-TRACKING LOGIC
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            if (notification.metrics.pixels < 0 && !_isPopping) {
              setState(() { _dragOffset = -notification.metrics.pixels; });
            } else if (_dragOffset > 0 && notification.metrics.pixels >= 0) {
               setState(() { _dragOffset = 0; });
            }
          } else if (notification is ScrollEndNotification) {
            if (_dragOffset > 80 && !_isPopping) {
              setState(() => _isPopping = true);
              AppHaptics.mediumImpact();
              Navigator.pop(context);
            } else {
              setState(() { _dragOffset = 0; }); // Snap wapas
            }
          }
          return false;
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: _dragOffset > 0 ? 0 : 300), // Instant follow, smooth snap
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _dragOffset, 0),
          child: Stack( // 🔥 NAYA: Stack add kiya taaki button fix rahe
            children: [
              // 1. ORIGINAL SCROLL CONTENT
              ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, overscroll: false),
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    // 🖼️ HEADER
                    SliverAppBar(
                      expandedHeight: MediaQuery.of(context).size.height * 0.45, // Slightly larger for grand feel
                      stretch: true,
                      pinned: true,
                      backgroundColor: Colors.transparent, 
                      automaticallyImplyLeading: false, // 👈 Ensures default back button doesn't show
                      flexibleSpace: FlexibleSpaceBar(
                        stretchModes: const [StretchMode.zoomBackground],
                        background: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 🎠 CAROUSEL
                            PageView.builder(
                              controller: _pageController,
                              physics: const BouncingScrollPhysics(),
                              onPageChanged: (index) {
                                AppHaptics.selectionClick();
                                setState(() => _currentImageIndex = index);
                              },
                              itemCount: maxSlides,
                              itemBuilder: (context, index) {
                                if (index == 5 && _images.length > 5) {
                                  return GestureDetector(
                                    onTap: _openGallery,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(_images[index], fit: BoxFit.cover),
                                        BackdropFilter(
                                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5), 
                                          child: Container(color: appBgColor.withOpacity(0.6))
                                        ),
                                        Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min, 
                                            children: [
                                              const Icon(Icons.photo_library_rounded, color: Colors.white, size: 40), 
                                              const SizedBox(height: 10), 
                                              Text("+${_images.length - 5} More Photos", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
                                            ]
                                          )
                                        )
                                      ],
                                    ),
                                  );
                                }
                                return Image.network(_images[index], fit: BoxFit.cover);
                              },
                            ),
                            
                            // 🌫️ SEAMLESS SHADOW GRADIENT TO MATCH EXACTLY WITH CONTENT BACKGROUND
                            IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent, 
                                      Colors.black.withOpacity(0.1), 
                                      appBgColor.withOpacity(0.7), 
                                      appBgColor 
                                    ],
                                    stops: const [0.0, 0.4, 0.8, 1.0],
                                  ),
                                ),
                              ),
                            ),

                            // 🔥 Perfect Alignment of Title, Location & Dots
                            Positioned(
                              bottom: 20, left: 24, right: 24,
                              child: IgnorePointer(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.place['title'], 
                                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1, height: 1.1)
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(CupertinoIcons.location_solid, color: neonCyan, size: 14),
                                        const SizedBox(width: 6),
                                        Text(
                                          widget.place['location'] ?? 'Unknown', 
                                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w600)
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    
                                    // Carousel Dots below location
                                    if (maxSlides > 1)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: List.generate(maxSlides, (index) {
                                          bool isActive = _currentImageIndex == index;
                                          return AnimatedContainer(
                                            duration: const Duration(milliseconds: 300), 
                                            margin: const EdgeInsets.symmetric(horizontal: 4), 
                                            height: 4, 
                                            width: isActive ? 20 : 6, 
                                            decoration: BoxDecoration(
                                              color: isActive ? neonCyan : Colors.white.withOpacity(0.4), 
                                              borderRadius: BorderRadius.circular(10)
                                            )
                                          );
                                        }),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 📜 CONTENT (Floating perfectly over the gradient)
                    SliverToBoxAdapter(
                      child: Container(
                        color: appBgColor, // Seamless blend, no solid box boundary
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),

                            // 💎 ULTIMATE CLEAN CAPSULE BUTTONS (Matched to Image)
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _buildPrimaryBtn(CupertinoIcons.car_detailed, "Go", neonCyan, () => AppHaptics.heavyImpact()),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: _buildSecondaryBtn(CupertinoIcons.phone, "Call", _callAction),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: _buildSecondaryBtn(CupertinoIcons.ticket, "Tickets", () => AppHaptics.lightImpact()),
                                ),
                              ],
                            ),

                            const SizedBox(height: 35),
                            const Text("The Vibe", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            _isLoading 
                              ? const Center(child: CupertinoActivityIndicator(color: Color(0xFF00E5FF)))
                              : Text(
                                  _description, 
                                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15, height: 1.6, fontWeight: FontWeight.w500)
                                ),

                            const SizedBox(height: 35),
                            const Text("Need to Know", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF151821), // Slightly lighter than bg for contrast
                                borderRadius: BorderRadius.circular(24), 
                                border: Border.all(color: Colors.white.withOpacity(0.05))
                              ),
                              child: Column(
                                children: [
                                  _buildBulletPoint(Icons.access_time_filled_rounded, "Timings", "06:00 AM – 08:00 PM (Daily)"),
                                  _buildBulletPoint(Icons.map_rounded, "Address", "${widget.place['title']}, ${widget.place['location']}, India"),
                                  _buildBulletPoint(Icons.thermostat_rounded, "Weather", "${widget.place['temp']} • Best time to visit is now."),
                                  _buildBulletPoint(Icons.money_rounded, "Entry Fee", "₹50 per person (Free for kids under 10)", isLast: true),
                                ],
                              ),
                            ),

                            const SizedBox(height: 40),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                              children: [
                                const Text("Keep Exploring", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)), 
                                Icon(Icons.arrow_forward_rounded, color: Colors.white.withOpacity(0.5), size: 20)
                              ]
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),

                    // 🎢 HORIZONTAL SCROLL FOR SUGGESTIONS
                    SliverToBoxAdapter(
                      child: Container(
                        color: appBgColor,
                        height: 180,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(left: 24, right: 8, bottom: 20),
                          itemCount: _suggestions.length,
                          itemBuilder: (context, index) {
                            return GestureDetector(
                              onTap: () => AppHaptics.selectionClick(),
                              child: Container(
                                width: 140, margin: const EdgeInsets.only(right: 16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24), 
                                  image: DecorationImage(image: NetworkImage(_suggestions[index]['img']!), fit: BoxFit.cover)
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24), 
                                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, appBgColor.withOpacity(0.9)])
                                  ), 
                                  alignment: Alignment.bottomLeft, 
                                  padding: const EdgeInsets.all(16), 
                                  child: Text(_suggestions[index]['title']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    
                    // Safe bottom padding
                    SliverToBoxAdapter(child: Container(color: appBgColor, height: 60)),
                  ],
                ),
              ),

              // 2. 🔥 EXACTLY ALIGNED GLASS BACK BUTTON
              Positioned(
                top: MediaQuery.of(context).padding.top + 12, // Exact pichli screen jaisi positioning
                left: 16,
                child: GestureDetector(
                  onTap: () {
                    if (!_isPopping) {
                      setState(() => _isPopping = true);
                      AppHaptics.lightImpact();
                      Navigator.pop(context);
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(50),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: 44, 
                        height: 44, // Exact pichli screen wala size
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.15), // Same frosted glass look
                          border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.5),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.only(right: 2.0),
                          child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  // 💎 PRIMARY BUTTON (Cyan & Black - Matches Image perfectly)
  Widget _buildPrimaryBtn(IconData icon, String label, Color accentColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(100),
          boxShadow: [BoxShadow(color: accentColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.black, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  // 💎 SECONDARY BUTTON (Dark Frosted - Matches Image perfectly)
  Widget _buildSecondaryBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFF1E2029), // Smooth dark premium grey
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: Colors.white.withOpacity(0.05))
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildBulletPoint(IconData icon, String title, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8), 
            decoration: BoxDecoration(color: neonCyan.withOpacity(0.1), shape: BoxShape.circle), 
            child: Icon(icon, color: neonCyan, size: 16)
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Text(title, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w600)), 
                const SizedBox(height: 2), 
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, height: 1.3))
              ]
            )
          )
        ],
      ),
    );
  }
}