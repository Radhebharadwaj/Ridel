import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'package:ridel/features/tour/screens/all_place.dart';
import 'chat_screen.dart';
import '../../../core/utils/app_haptics.dart';

class TourScreen extends StatefulWidget {
  const TourScreen({super.key});

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  int _selectedCategoryIndex = 0;
  final List<String> _categories = ["ALL", "SPIRITUAL", "ADVENTURE", "NATURE", "URBAN", "HERITAGE"];
  
  late PageController _categoryController;
  late PageController _trendingController;
  Timer? _carouselTimer;
  int _currentTrendingIndex = 0;

  bool _isMenuOpen = false;
  bool _isServicesExpanded = false;
  
  bool _isSearchActive = false;
  bool _isMicActive = false; 
  
  final TextEditingController _aiInputController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  final List<Map<String, String>> _trendingPlaces = [
    {
      "image": "https://images.unsplash.com/photo-1626621341517-bbf3d9990a23?q=80&w=2070&auto=format&fit=crop", 
      "title": "Kedarnath",
      "location": "Rudraprayag, Uttarakhand",
      "rating": "5.0",
      "temp": "8°C"
    },
    {
      "image": "https://images.unsplash.com/photo-1564507592333-c60657eea523?q=80&w=2071&auto=format&fit=crop", 
      "title": "Taj Mahal",
      "location": "Agra, Uttar Pradesh",
      "rating": "4.9",
      "temp": "28°C"
    },
    {
      "image": "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=2073&auto=format&fit=crop",
      "title": "Goa Beach",
      "location": "Goa, India",
      "rating": "4.7",
      "temp": "32°C"
    },
  ];

  @override
  void initState() {
    super.initState();
    _categoryController = PageController(viewportFraction: 0.25, initialPage: _selectedCategoryIndex);
    _trendingController = PageController(viewportFraction: 1.0);
    
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (_currentTrendingIndex < _trendingPlaces.length - 1) {
        _currentTrendingIndex++;
      } else {
        _currentTrendingIndex = 0;
      }
      
      if (_trendingController.hasClients) {
        _trendingController.animateToPage(
          _currentTrendingIndex,
          duration: const Duration(milliseconds: 800),
          curve: Curves.fastOutSlowIn,
        );
      }
    });
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _trendingController.dispose();
    _carouselTimer?.cancel();
    _aiInputController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); 

    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final double fullSearchWidth = screenWidth - 110; 
    const neonCyan = Color(0xFF00E5FF);

    return Scaffold(
      backgroundColor: Colors.black, 
      resizeToAvoidBottomInset: false, 
      body: Stack(
        children: [
          Positioned(
            top: -120, left: -50,
            child: Container(
              width: 350, height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF004D40).withOpacity(0.2), 
                    blurRadius: 150, 
                    spreadRadius: 20,
                  )
                ]
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 15),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("EXPLORE", style: TextStyle(color: Colors.grey.shade500, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            const Text("Incredible India", style: TextStyle(color: Colors.white, fontSize: 26, fontFamily: 'Serif', fontWeight: FontWeight.w500, letterSpacing: -0.5)),
                          ],
                        ),
                        
                        GestureDetector(
                          onTap: () {
                            AppHaptics.mediumImpact(); 
                            setState(() {
                              _isMenuOpen = !_isMenuOpen;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _isMenuOpen ? neonCyan.withOpacity(0.15) : Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12), 
                              border: Border.all(color: _isMenuOpen ? neonCyan.withOpacity(0.6) : Colors.white.withOpacity(0.1)),
                              boxShadow: _isMenuOpen ? [BoxShadow(color: neonCyan.withOpacity(0.3), blurRadius: 10)] : []
                            ),
                            child: Icon(
                              _isMenuOpen ? Icons.close_rounded : Icons.dashboard_customize_rounded,
                              color: _isMenuOpen ? neonCyan : Colors.white, 
                              size: 20
                            ),
                          ),
                        )
                      ],
                    ),

                    AnimatedSize(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOutCubic,
                      child: SizedBox(
                        height: _isMenuOpen ? 65 : 0,
                        child: _isMenuOpen ? Padding(
                          padding: const EdgeInsets.only(top: 20.0),
                          child: Center(
                            child: Container(
                              width: MediaQuery.of(context).size.width,
                              height: 42,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.white.withOpacity(0.04),
                                border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.5),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 100, height: 34,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.02),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.5),
                                        ),
                                      ),
                                      PageView.builder(
                                        controller: _categoryController,
                                        itemCount: _categories.length,
                                        onPageChanged: (index) {
                                          // 🔥 FIX 2: Corrected function call
                                          AppHaptics.lightImpact();
                                          setState(() => _selectedCategoryIndex = index);
                                        },
                                        itemBuilder: (context, index) {
                                          bool isSelected = _selectedCategoryIndex == index;
                                          return Center(
                                            child: AnimatedDefaultTextStyle(
                                              duration: const Duration(milliseconds: 250),
                                              curve: Curves.easeOut,
                                              style: TextStyle(
                                                color: isSelected ? neonCyan : Colors.white.withOpacity(0.3),
                                                fontSize: isSelected ? 13 : 10,
                                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                                                letterSpacing: 1,
                                                fontFamily: 'Sans',
                                                shadows: isSelected ? [Shadow(color: neonCyan.withOpacity(0.5), blurRadius: 5)] : [],
                                              ),
                                              child: Text(_categories[index], maxLines: 1, overflow: TextOverflow.visible, textAlign: TextAlign.center),
                                            ),
                                          );
                                        },
                                      ),
                                      Positioned(left: 0, top: 0, bottom: 0, width: 30, child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.black.withOpacity(0.8), Colors.transparent])))),
                                      Positioned(right: 0, top: 0, bottom: 0, width: 30, child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withOpacity(0.8)])))),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ) : const SizedBox.shrink(),
                      ),
                    ),

                    const SizedBox(height: 25),

                    Container(
                      width: double.infinity,
                      height: 180,
                      clipBehavior: Clip.hardEdge, 
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(35), 
                        gradient: const LinearGradient(colors: [Color(0xFF001515), Color(0xFF002B2B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        boxShadow: [BoxShadow(color: neonCyan.withOpacity(0.08), blurRadius: 25, offset: const Offset(0, 10))],
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            top: -60, left: -60,
                            child: Container(
                              width: 180, height: 180,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: neonCyan.withOpacity(0.1)),
                              child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60), child: Container(color: Colors.transparent)),
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 40,
                                  child: Stack(
                                    children: [
                                      AnimatedOpacity(
                                        duration: const Duration(milliseconds: 200),
                                        opacity: _isSearchActive ? 0.0 : 1.0,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(color: const Color(0xFF003838), borderRadius: BorderRadius.circular(20), border: Border.all(color: neonCyan.withOpacity(0.3))),
                                            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome, color: neonCyan, size: 12), SizedBox(width: 6), Text("AI TRIP PLANNER", style: TextStyle(color: neonCyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5))]),
                                          ),
                                        ),
                                      ),
                                      
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 350),
                                          curve: Curves.easeInOutCubic,
                                          clipBehavior: Clip.hardEdge,
                                          width: _isSearchActive ? fullSearchWidth : 40, 
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: _isSearchActive ? const Color(0xFF001F1F) : Colors.white.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(30),
                                            border: _isSearchActive ? Border.all(color: Colors.white.withOpacity(0.2)) : null,
                                            boxShadow: _isSearchActive ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)] : []
                                          ),
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            physics: const NeverScrollableScrollPhysics(), 
                                            child: SizedBox(
                                              width: _isSearchActive ? fullSearchWidth : 40, 
                                              child: _isSearchActive 
                                                ? Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      const Padding(padding: EdgeInsets.only(left: 12.0), child: Icon(Icons.search, color: Colors.white54, size: 18)),
                                                      Expanded(
                                                        child: Padding(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                                          child: TextField(
                                                            controller: _searchController,
                                                            autofocus: true,
                                                            style: const TextStyle(color: Colors.white, fontSize: 14),
                                                            cursorColor: neonCyan,
                                                            decoration: const InputDecoration(
                                                              hintText: "Search places...",
                                                              hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                                                              border: InputBorder.none,
                                                              isDense: true,
                                                              contentPadding: EdgeInsets.zero,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      GestureDetector(
                                                        onTapDown: (_) => setState(() => _isMicActive = true),
                                                        onTapUp: (_) => setState(() => _isMicActive = false),
                                                        onTapCancel: () => setState(() => _isMicActive = false),
                                                        onTap: () { AppHaptics.mediumImpact(); },
                                                        child: AnimatedContainer(
                                                          duration: const Duration(milliseconds: 200),
                                                          padding: const EdgeInsets.all(6),
                                                          decoration: BoxDecoration(
                                                            shape: BoxShape.circle,
                                                            color: _isMicActive ? neonCyan.withOpacity(0.2) : Colors.transparent,
                                                            boxShadow: _isMicActive ? [BoxShadow(color: neonCyan.withOpacity(0.4), blurRadius: 8)] : []
                                                          ),
                                                          child: Icon(Icons.mic_rounded, color: _isMicActive ? neonCyan : Colors.white60, size: 20),
                                                        ),
                                                      ),
                                                      GestureDetector(
                                                        onTap: () {
                                                          AppHaptics.lightImpact();
                                                          setState(() { _isSearchActive = false; _searchController.clear(); });
                                                        },
                                                        child: Container(
                                                          padding: const EdgeInsets.only(left: 5, right: 12.0), 
                                                          color: Colors.transparent,
                                                          child: const Icon(Icons.close, color: Colors.white, size: 20)
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : GestureDetector(
                                                    onTap: () {
                                                      AppHaptics.mediumImpact();
                                                      setState(() => _isSearchActive = true);
                                                    },
                                                    child: const Center(child: Icon(Icons.search_rounded, color: Colors.white, size: 20)),
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const Spacer(),

                                Padding(
                                  padding: const EdgeInsets.only(right: 115.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text("Confused where to go?", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, height: 1.1)),
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        height: 30,
                                        child: TextField(
                                          controller: _aiInputController,
                                          onTap: () { AppHaptics.lightImpact(); },
                                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                                          cursorColor: neonCyan,
                                          decoration: InputDecoration(
                                            hintText: "Tell AI your mood...", 
                                            hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                            border: InputBorder.none,
                                            contentPadding: EdgeInsets.zero,
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          Positioned(
                            right: 20, bottom: 20,
                            child: GestureDetector(
                              onTap: () {
                                AppHaptics.heavyImpact(); 
                                Navigator.push(
                                  context, 
                                  PageRouteBuilder(
                                    // 🔥 FIX 3: Removed 'const' 
                                    pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(),
                                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                      const begin = Offset(1.0, 0.0);
                                      const end = Offset.zero;
                                      const curve = Curves.fastOutSlowIn;
                                      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                                      return SlideTransition(position: animation.drive(tween), child: child);
                                    },
                                  )
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: neonCyan.withOpacity(0.2), blurRadius: 15, spreadRadius: 1)]),
                                child: const Row(children: [Text("Chat", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)), SizedBox(width: 8), Icon(Icons.chat_bubble_outline_rounded, color: Colors.black, size: 18)]),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    Center(
                      child: GestureDetector(
                        onTap: () {
                          AppHaptics.lightImpact(); 
                          setState(() {
                            _isServicesExpanded = !_isServicesExpanded;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.1))
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _isServicesExpanded ? "Close Services" : "Quick Services",
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                _isServicesExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, 
                                color: neonCyan, size: 16
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    
                    AnimatedSize(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOutBack,
                      child: SizedBox(
                        height: _isServicesExpanded ? 90 : 0,
                        child: _isServicesExpanded ? Padding(
                          padding: const EdgeInsets.only(top: 15.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildServiceIcon(Icons.flight, "Flights", neonCyan),
                              _buildServiceIcon(Icons.train, "Trains", neonCyan),
                              _buildServiceIcon(Icons.hotel, "Hotels", neonCyan),
                            ],
                          ),
                        ) : const SizedBox.shrink(),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Trending Now", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        if(!_isMenuOpen) 
                          GestureDetector(
                            onTap: () {
                              AppHaptics.lightImpact(); 
                              Navigator.push(
                                  context, 
                                  PageRouteBuilder(
                                    // 🔥 FIX 4: Removed 'const' 
                                    pageBuilder: (context, animation, secondaryAnimation) => AllPlacesScreen(), 
                                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                      const begin = Offset(1.0, 0.0);
                                      const end = Offset.zero;
                                      const curve = Curves.fastOutSlowIn;
                                      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                                      return SlideTransition(position: animation.drive(tween), child: child);
                                    },
                                  )
                              );
                            },
                            child: Text("See All", style: TextStyle(color: neonCyan.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    
                    SizedBox(
                      height: screenHeight * 0.4,
                      child: PageView.builder(
                        controller: _trendingController,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _trendingPlaces.length,
                        onPageChanged: (index) {
                          setState(() {
                            _currentTrendingIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final place = _trendingPlaces[index];
                          return _buildTrendingCard(
                            image: place["image"]!,
                            title: place["title"]!,
                            location: place["location"]!,
                            rating: place["rating"]!,
                            temp: place["temp"]!,
                            neonCyan: neonCyan
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildServiceIcon(IconData icon, String label, Color color) {
    return GestureDetector(
      onTap: () { AppHaptics.lightImpact(); }, 
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11))
        ],
      ),
    );
  }

  Widget _buildTrendingCard({
    required String image, 
    required String title, 
    required String location,
    required String rating, 
    required String temp,
    required Color neonCyan
  }) {
    return GestureDetector(
      onTap: () { AppHaptics.mediumImpact(); }, 
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(35), 
          image: DecorationImage(image: NetworkImage(image), fit: BoxFit.cover),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))]
        ),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(35), 
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, 
                  colors: [Colors.transparent, Colors.black.withOpacity(0.9)]
                )
              )
            ),
            Positioned(
              top: 20, right: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(temp, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(width: 4),
                        const Icon(Icons.wb_sunny_rounded, color: Colors.orangeAccent, size: 14)
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 20, left: 20, right: 20, 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: neonCyan, borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [const Icon(Icons.star, size: 12, color: Colors.black), const SizedBox(width: 4), Text(rating, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black))]),
                      )
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.grey.shade400, size: 14),
                      const SizedBox(width: 4),
                      Text(location, style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.w400)),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}