import 'dart:ui';
import 'dart:convert';
import 'package:flutter/cupertino.dart'; 
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/ridel_sheet.dart'; 
import '../services/wikipedia_service.dart';
import '../widgets/place_images_sheet_content.dart'; // Fixed import path

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

class PlaceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> place;
  final double userLat;
  final double userLng;

  const PlaceDetailScreen({super.key, required this.place, required this.userLat, required this.userLng});

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
    _images.add(widget.place['img']); 
    _fetchDetails();
  }

  void _fetchDetails() async {
    final results = await Future.wait([
      PlaceDataService.getWikiDetails(widget.place['title']),
      WikipediaService.fetchRealPlaceImagesPaginated(widget.place['title'], widget.place['img']),
    ]);

    if (mounted) {
      final wikiData = results[0] as Map<String, dynamic>?;
      final imgData = results[1] as Map<String, dynamic>;

      setState(() { 
        if (wikiData != null && wikiData['extract'] != null) _description = wikiData['extract'];
        List<String> extraImages = [];
        if (imgData['images'] != null) extraImages = List<String>.from(imgData['images']); 
        _images = [widget.place['img'].toString(), ...extraImages].toSet().toList();
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
      context, title: "${widget.place['title']} Gallery", showCloseButton: true,
      sheetColor: appBgColor,
      child: PlaceImagesSheetContent(title: widget.place['title'], mainImageUrl: widget.place['img']),
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
          // Sirf screen ko niche slide kar raha hu (No hard borders, No scale down!)
          transform: Matrix4.translationValues(0, _dragOffset, 0),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, overscroll: false),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // 🖼️ HEADER
                SliverAppBar(
                  expandedHeight: MediaQuery.of(context).size.height * 0.40, // Wider image look
                  stretch: true,
                  pinned: true,
                  backgroundColor: Colors.transparent, // Let gradient handle it
                  leading: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: GestureDetector(
                      onTap: () {
                        if (!_isPopping) {
                          setState(() => _isPopping = true);
                          AppHaptics.lightImpact();
                          Navigator.pop(context);
                        }
                      },
                      child: ClipOval(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft, end: Alignment.bottomRight,
                                colors: [Colors.white.withOpacity(0.4), Colors.white.withOpacity(0.02)],
                              ),
                              border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.2),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.only(left: 6.0), 
                              child: Icon(Icons.arrow_back_ios, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
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
                                    BackdropFilter(filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5), child: Container(color: appBgColor.withOpacity(0.6))),
                                    Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.photo_library_rounded, color: Colors.white, size: 40), const SizedBox(height: 10), Text("+${_images.length - 5} More Photos", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]))
                                  ],
                                ),
                              );
                            }
                            return Image.network(_images[index], fit: BoxFit.cover);
                          },
                        ),
                        
                        // 🌫️ SEAMLESS SHADOW GRADIENT TO 0B0E17
                        IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                colors: [
                                  appBgColor.withOpacity(0.3), 
                                  Colors.transparent, 
                                  appBgColor.withOpacity(0.0), 
                                  appBgColor.withOpacity(0.8), 
                                  appBgColor 
                                ],
                                stops: const [0.0, 0.2, 0.65, 0.9, 1.0],
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          bottom: 30, left: 24, right: 24,
                          child: IgnorePointer(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.place['title'], style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1, height: 1.1)),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on_rounded, color: Color(0xFF00E5FF), size: 16),
                                    const SizedBox(width: 6),
                                    Text(widget.place['loc'], style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (maxSlides > 1)
                          Positioned(
                            bottom: 12, left: 0, right: 0,
                            child: IgnorePointer(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(maxSlides, (index) {
                                  bool isActive = _currentImageIndex == index;
                                  return AnimatedContainer(duration: const Duration(milliseconds: 300), margin: const EdgeInsets.symmetric(horizontal: 4), height: 5, width: isActive ? 20 : 5, decoration: BoxDecoration(color: isActive ? neonCyan : Colors.white54, borderRadius: BorderRadius.circular(10)));
                                }),
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

                        // 💎 ULTIMATE SLIM GLASSY CAPSULES
                        Row(
                          children: [
                            Expanded(
                              // Front Car Icon for "Go" as requested
                              child: _buildGlassyBtn(Icons.directions_car_rounded, "Go", neonCyan, isPrimary: true, onTap: () => AppHaptics.heavyImpact()),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildGlassyBtn(CupertinoIcons.phone, "Call", Colors.white, isPrimary: false, onTap: _callAction),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildGlassyBtn(CupertinoIcons.ticket, "Tickets", Colors.white, isPrimary: false, onTap: () => AppHaptics.lightImpact()),
                            ),
                          ],
                        ),

                        const SizedBox(height: 35),
                        const Text("The Vibe", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _isLoading 
                          ? const CircularProgressIndicator(color: Color(0xFF00E5FF))
                          : Text(_description, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16, height: 1.5, fontWeight: FontWeight.w500)),

                        const SizedBox(height: 35),
                        const Text("Need to Know", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.05))),
                          child: Column(
                            children: [
                              _buildBulletPoint(Icons.access_time_filled_rounded, "Timings", "06:00 AM – 08:00 PM (Daily)"),
                              _buildBulletPoint(Icons.map_rounded, "Address", "${widget.place['title']}, ${widget.place['loc']}, India"),
                              _buildBulletPoint(Icons.thermostat_rounded, "Weather", "${widget.place['temp']} • Best time to visit is now."),
                              _buildBulletPoint(Icons.money_rounded, "Entry Fee", "₹50 per person (Free for kids under 10)", isLast: true),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Keep Exploring", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)), Icon(Icons.arrow_forward_rounded, color: Colors.white.withOpacity(0.5), size: 20)]),
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
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), image: DecorationImage(image: NetworkImage(_suggestions[index]['img']!), fit: BoxFit.cover)),
                            child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, appBgColor.withOpacity(0.9)])), alignment: Alignment.bottomLeft, padding: const EdgeInsets.all(16), child: Text(_suggestions[index]['title']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
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
        ),
      ),
    );
  }

  // 💎 INCONSISTENT GLASSY CAPSULES (SLIM & BEAUTIFUL)
  Widget _buildGlassyBtn(IconData icon, String label, Color accentColor, {required bool isPrimary, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100), // Perfect Capsule
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            height: 48, // 🔥 SLIM WIDTH
            decoration: BoxDecoration(
              color: isPrimary ? accentColor : Colors.white.withOpacity(0.08),
              // Lighting edge on top-left, shadow on bottom-right (Glass reflection effect)
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(isPrimary ? 0.6 : 0.4), width: 1.5),
                left: BorderSide(color: Colors.white.withOpacity(isPrimary ? 0.6 : 0.4), width: 1.5),
                bottom: BorderSide(color: Colors.black.withOpacity(isPrimary ? 0.2 : 0.4), width: 1.5),
                right: BorderSide(color: Colors.black.withOpacity(isPrimary ? 0.2 : 0.4), width: 1.5),
              )
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: isPrimary ? Colors.black : Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(color: isPrimary ? Colors.black : Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
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
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: neonCyan.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: neonCyan, size: 16)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w600)), const SizedBox(height: 2), Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, height: 1.3))]))
        ],
      ),
    );
  }
}