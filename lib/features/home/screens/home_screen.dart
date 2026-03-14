import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; 
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_header.dart'; 
import '../../../core/utils/toast_service.dart'; 

import '../widgets/ai_hero_card.dart';
import '../widgets/place_card.dart';
import 'place_detail_screen.dart'; 

import '../../tour/screens/reel_feed_screen.dart';
import 'package:ridel/features/tour/screens/all_place.dart' hide PlaceCard;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final int _initialPage = 10000; 
  late final PageController _pageController;
  int _realIndex = 0; 
  
  Timer? _carouselTimer;
  Timer? _pauseTimer;
  bool _isPaused = false;
  bool _isAiThinking = false;
  
  // 🔥 REFRESH & SWIPE STATE
  bool _isRefreshing = false;
  double _dragOffset = 0.0;

  final double _userLat = 28.6139;
  final double _userLng = 77.2090;

  final List<Map<String, dynamic>> _allPlaces = [
    {"title": "Kedarnath", "loc": "Uttarakhand", "rating": "5.0", "temp": "8°C", "tags": ["religious", "hindu", "mountain", "peace"], "img": "https://images.unsplash.com/photo-1626621341517-bbf3d9990a23?q=80&w=1000&auto=format&fit=crop", "lat": 30.7352, "lng": 79.0669},
    {"title": "Taj Mahal", "loc": "Agra", "rating": "4.8", "temp": "24°C", "tags": ["historical", "monument", "love"], "img": "https://images.unsplash.com/photo-1564507592333-c60657eea523?q=80&w=1000&auto=format&fit=crop", "lat": 27.1751, "lng": 78.0421},
    {"title": "Varanasi Ghats", "loc": "Uttar Pradesh", "rating": "4.9", "temp": "26°C", "tags": ["religious", "hindu", "river", "spiritual"], "img": "https://images.unsplash.com/photo-1561361513-2d000a50f0dc?q=80&w=1000&auto=format&fit=crop", "lat": 25.3176, "lng": 83.0062},
    {"title": "Kerala Backwaters", "loc": "Kerala", "rating": "4.9", "temp": "28°C", "tags": ["nature", "water", "peace", "boat"], "img": "https://images.unsplash.com/photo-1602216056096-3b40cc0c9944?q=80&w=1000&auto=format&fit=crop", "lat": 10.0889, "lng": 77.0595},
    {"title": "Goa Beaches", "loc": "Goa", "rating": "4.7", "temp": "31°C", "tags": ["party", "beach", "fun", "friends"], "img": "https://images.unsplash.com/photo-1512343879784-a960bf40e7f2?q=80&w=1000&auto=format&fit=crop", "lat": 15.2993, "lng": 74.1240},
  ];

  List<Map<String, dynamic>> _currentPlaces = [];

  @override
  void initState() {
    super.initState();
    _currentPlaces = List.from(_allPlaces); 
    _pageController = PageController(viewportFraction: 0.85, initialPage: _initialPage);
    _startAutoSlide();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _carouselTimer?.cancel();
    _pauseTimer?.cancel();
    super.dispose();
  }

  // --- 🔥 NAVIGATION ROUTING ACTIONS ---

  void _openReelFeed() {
    AppHaptics.heavyImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const ReelFeedScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
          return SlideTransition(position: slideAnimation, child: FadeTransition(opacity: animation, child: child));
        },
      ),
    );
  }

  void _openGridView() {
    AppHaptics.lightImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => AllPlacesScreen(), // All places screen open hogi
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  // --- 🔥 PULL TO REFRESH LOGIC ---

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    AppHaptics.mediumImpact();
    setState(() => _isRefreshing = true);

    await Future.delayed(const Duration(seconds: 2));
    
    bool hasInternet = false;

    if (mounted) {
      if (hasInternet) {
        setState(() {
          _currentPlaces.shuffle(); 
          _isRefreshing = false;
        });
        AppHaptics.heavyImpact();
      } else {
        setState(() => _isRefreshing = false);
        AppHaptics.heavyImpact();
        
        ToastService.showError(context, "Connection failed. Showing cached places."); 
      }
    }
  }


  void _startAutoSlide() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 7), (timer) { 
      if (_pageController.hasClients && !_isAiThinking && !_isPaused) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 1200), 
          curve: Curves.fastOutSlowIn
        );
      }
    });
  }

  void _pauseAutoSlideTemporary([int seconds = 8]) {
    setState(() => _isPaused = true);
    _pauseTimer?.cancel();
    _pauseTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) setState(() => _isPaused = false);
    });
  }

  void _handleAiSearch(String mood) async {
    if (mood.isEmpty) return;
    AppHaptics.heavyImpact();
    FocusScope.of(context).unfocus(); 
    setState(() { _isAiThinking = true; });

    await Future.delayed(const Duration(milliseconds: 1500));

    final String searchLower = mood.toLowerCase();
    final filtered = _allPlaces.where((place) {
      final tags = place['tags'] as List<String>;
      return tags.any((tag) => searchLower.contains(tag)) || 
             place['title'].toString().toLowerCase().contains(searchLower) ||
             place['loc'].toString().toLowerCase().contains(searchLower);
    }).toList();

    setState(() {
      _currentPlaces = filtered.isNotEmpty ? filtered : _allPlaces; 
      _realIndex = 0;
      _isAiThinking = false;
    });

    if (_pageController.hasClients) {
      _pageController.jumpToPage(_initialPage);
    }
  }

  void _openPlaceDetail(Map<String, dynamic> place) async {
    AppHaptics.lightImpact();
    setState(() => _isPaused = true); 
    _carouselTimer?.cancel(); 

    await Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false, 
        transitionDuration: const Duration(milliseconds: 500), 
        reverseTransitionDuration: const Duration(milliseconds: 400), 
        pageBuilder: (context, animation, secondaryAnimation) => PlaceDetailScreen(
          place: place,
          userLat: _userLat,
          userLng: _userLng,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

          return FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
            child: SlideTransition(position: slideAnimation, child: child),
          );
        },
      ),
    );

    _pauseAutoSlideTemporary(3); 
    _startAutoSlide(); 
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      resizeToAvoidBottomInset: false, 
      body: Stack(
        children: [
          // 🔥 GLOBAL GESTURE DETECTOR FOR SWIPE UP & SWIPE DOWN
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              setState(() { _dragOffset += details.delta.dy; });
            },
            onVerticalDragEnd: (details) {
              if (_dragOffset > 120 && !_isRefreshing) {
                // Swipe Down => Refresh
                _handleRefresh();
              } else if (_dragOffset < -80 || details.primaryVelocity! < -300) {
                // Swipe Up => Open Reels
                _openReelFeed();
              }
              setState(() { _dragOffset = 0.0; });
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top + 101), 
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20), 
                  child: AiHeroCard(onSearch: _handleAiSearch)
                ),
                
                const SizedBox(height: 30), 
              
                // 🔥 PERFECT GRID ALIGNMENT
                Padding(
                  padding: const EdgeInsets.only(left: 40, right: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 1. Explore opens Reel Screen
                      GestureDetector(
                        onTap: _openReelFeed,
                        child: Text("Explore", style: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5, height: 1.0)),
                      ),
                      // 2. See All opens Grid View
                      GestureDetector(
                        onTap: _openGridView,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2.0),
                          child: Text("See All", style: GoogleFonts.inter(color: const Color(0xFF00E5FF), fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                
                Expanded(
                  child: Listener(
                    onPointerDown: (_) => _pauseAutoSlideTemporary(8), 
                    child: PageView.builder(
                      controller: _pageController,
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()), 
                      onPageChanged: (index) {
                        AppHaptics.selectionClick(); 
                        setState(() => _realIndex = index % _currentPlaces.length);
                      },
                      itemBuilder: (context, index) {
                        if (_currentPlaces.isEmpty) return const SizedBox();
                        final realIdx = index % _currentPlaces.length;
                        final place = _currentPlaces[realIdx];

                        return AnimatedBuilder(
                          animation: _pageController,
                          builder: (context, child) {
                            double pageOffset = 0;
                            if (_pageController.position.haveDimensions) {
                              pageOffset = _pageController.page! - index;
                            }
                            
                            double scale = (1 - (pageOffset.abs() * 0.15)).clamp(0.85, 1.0);
                            double darkness = (pageOffset.abs() * 0.6).clamp(0.0, 0.7);
                            double squeeze = pageOffset * 25.0; 

                            return Transform.translate(
                              offset: Offset(squeeze, 0),
                              child: Transform.scale(
                                scale: scale,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10), 
                                      child: PlaceCard(
                                        title: place['title'], 
                                        location: place['loc'], 
                                        rating: place['rating'], 
                                        weather: place['temp'], 
                                        imageUrl: place['img'],
                                        parallaxOffset: _pageController.position.haveDimensions
                                          ? _pageController.page! - index 
                                          : 0.0,
                                        onTap: () => _openPlaceDetail(place),
                                        onSwipeUp: _openReelFeed,
                                      )
                                    ),
                                    
                                    IgnorePointer( 
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(32),
                                            color: Colors.black.withOpacity(darkness), 
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_currentPlaces.length, (index) => _buildDot(index, isDark)),
                ),
                const SizedBox(height: 100), 
              ],
            ),
          ),

          // --- HEADER POSITIONED ---
          Positioned(
            top: 0, 
            left: 0, 
            right: 0, 
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SizedBox(height: 10), 
                    AppHeader(), 
                  ],
                ),
              ),
            ),
          ),

          // --- 🔥 CUSTOM REFRESH INDICATOR UI ---
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            top: _isRefreshing ? MediaQuery.of(context).padding.top + 80 : -100,
            left: 0, right: 0,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5), width: 1.5),
                      boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.3), blurRadius: 15)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Color(0xFF00E5FF), strokeWidth: 2.5)),
                        SizedBox(width: 12),
                        Text("Finding new places...", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (_isAiThinking)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: (isDark ? Colors.black : Colors.white).withOpacity(0.5),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Color(0xFF00E5FF), strokeWidth: 3),
                        const SizedBox(height: 20),
                        Text("Curating places for your mood...", style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5))
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDot(int index, bool isDark) {
    bool isActive = _realIndex == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 6, width: isActive ? 28 : 6, 
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF00E5FF) : (isDark ? Colors.white24 : Colors.black26), 
        borderRadius: BorderRadius.circular(10),
        boxShadow: isActive ? [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.5), blurRadius: 6)] : [],
      ),
    );
  }
}