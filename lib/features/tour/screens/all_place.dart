import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';

import '../../../core/utils/app_haptics.dart'; 
import '../../home/screens/place_detail_screen.dart';

class AllPlacesScreen extends StatefulWidget {
  const AllPlacesScreen({super.key});

  @override
  State<AllPlacesScreen> createState() => _AllPlacesScreenState();
}

class _AllPlacesScreenState extends State<AllPlacesScreen> {
  // --- DATA ---
  final List<String> _categories = ["All", "Mountains", "Temples", "Lakes", "City", "Historical"];
  final List<String> _states = ["Uttar Pradesh", "Kerala", "Rajasthan", "Punjab", "Delhi", "Himachal"];
  final List<String> _cities = ["Varanasi", "Munnar", "Jaipur", "Amritsar", "New Delhi", "Manali"];

  final List<Map<String, dynamic>> _allPlaces = [
    {
      "id": 1,
      "title": "Varanasi Ghats",
      "location": "Uttar Pradesh",
      "image": "https://images.unsplash.com/photo-1561361513-2d000a50f0dc?q=80&w=2076",
      "rating": "4.8",
      "category": "Temples",
      "height": 280.0,
      "isLiked": false,
      "temp": "28°C",
      "weather": "Haze",
      "isPinned": true,
    },
    {
      "id": 2,
      "title": "Munnar Hills",
      "location": "Kerala",
      "image": "https://images.unsplash.com/photo-1596328225255-a5d6174a743a?q=80&w=1978",
      "rating": "4.9",
      "category": "Mountains",
      "height": 220.0,
      "isLiked": false,
      "temp": "18°C",
      "weather": "Rainy",
      "isPinned": false,
    },
    {
      "id": 3,
      "title": "Hawa Mahal",
      "location": "Jaipur",
      "image": "https://images.unsplash.com/photo-1477587458883-47145ed94245?q=80&w=2070",
      "rating": "4.7",
      "category": "Historical",
      "height": 300.0,
      "isLiked": false,
      "temp": "32°C",
      "weather": "Sunny",
      "isPinned": true,
    },
    {
      "id": 4,
      "title": "Golden Temple",
      "location": "Amritsar",
      "image": "https://images.unsplash.com/photo-1593183570656-78bda043df99?q=80&w=2070",
      "rating": "5.0",
      "category": "Temples",
      "height": 240.0,
      "isLiked": false,
      "temp": "24°C",
      "weather": "Clear",
      "isPinned": false,
    },
    {
      "id": 5,
      "title": "Udaipur Lake",
      "location": "Rajasthan",
      "image": "https://images.unsplash.com/photo-1595262589078-d4c5145b2098?q=80&w=1964",
      "rating": "4.6",
      "category": "Lakes",
      "height": 260.0,
      "isLiked": false,
      "temp": "29°C",
      "weather": "Cloudy",
      "isPinned": false,
    },
    {
      "id": 6,
      "title": "India Gate",
      "location": "New Delhi",
      "image": "https://images.unsplash.com/photo-1587474265402-9e6b7d41f021?q=80&w=1972",
      "rating": "4.5",
      "category": "City",
      "height": 200.0,
      "isLiked": false,
      "temp": "34°C",
      "weather": "Sunny",
      "isPinned": false,
    },
  ];

  late List<Map<String, dynamic>> _displayPlaces;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // --- STATES ---
  bool _isBarExpanded = true;
  bool _isSearchActive = false;
  bool _showOnlyFavorites = false;
  bool _isMicActive = false; 

  // Design Constants
  final Color neonCyan = const Color(0xFF00E5FF);

  @override
  void initState() {
    super.initState();
    _displayPlaces = List.from(_allPlaces);

    _scrollController.addListener(() {
      if (_scrollController.offset <= 0) {
        if (!_isBarExpanded) setState(() => _isBarExpanded = true);
      } else if (_scrollController.offset > 50 &&
          _scrollController.position.userScrollDirection == ScrollDirection.reverse) {
        if (_isBarExpanded) {
          setState(() {
            _isBarExpanded = false;
            _isSearchActive = false;
            _isMicActive = false;
            FocusScope.of(context).unfocus();
          });
        }
      }
    });
  }

  void _toggleBar() {
    setState(() {
      _isBarExpanded = !_isBarExpanded;
    });
    AppHaptics.mediumImpact();
  }

  void _toggleSearch() {
    setState(() {
      _isSearchActive = !_isSearchActive;
      if (!_isSearchActive) {
        _searchController.clear();
        _isMicActive = false;
        _applyFilters();
      }
    });
  }

  void _toggleMic() {
    setState(() {
      _isMicActive = !_isMicActive;
    });
    AppHaptics.mediumImpact();
    if (_isMicActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Listening..."), duration: Duration(milliseconds: 800), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _toggleFavoriteFilter() {
    setState(() {
      _showOnlyFavorites = !_showOnlyFavorites;
      _applyFilters();
    });
    AppHaptics.lightImpact();
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    
    setState(() {
      var tempPlaces = _allPlaces.where((place) {
        final matchesQuery = place['title'].toString().toLowerCase().contains(query);
        final matchesFav = _showOnlyFavorites ? place['isLiked'] == true : true;
        return matchesQuery && matchesFav;
      }).toList();

      tempPlaces.sort((a, b) {
        bool aPinned = a['isPinned'] ?? false;
        bool bPinned = b['isPinned'] ?? false;
        if (aPinned && !bPinned) return -1; 
        if (!aPinned && bPinned) return 1;  
        return 0; 
      });

      _displayPlaces = tempPlaces;
    });
  }

  void _onLikeChanged(int id, bool isLiked) {
    setState(() {
      final index = _allPlaces.indexWhere((element) => element['id'] == id);
      if (index != -1) {
        _allPlaces[index]['isLiked'] = isLiked;
        _applyFilters();
      }
    });
  }

  void _onPinToggle(int id) {
    setState(() {
      final index = _allPlaces.indexWhere((element) => element['id'] == id);
      if (index != -1) {
        _allPlaces[index]['isPinned'] = !(_allPlaces[index]['isPinned'] ?? false);
        _applyFilters(); 
      }
    });
    AppHaptics.mediumImpact();
  }

  // --- IOS STYLE POPUP (Unchanged) ---
  void _showIOSDetailPopup(Map<String, dynamic> place) {
    AppHaptics.heavyImpact();
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha:0.4),
      pageBuilder: (context, _, __) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(color: Colors.black.withValues(alpha:0.2)),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  height: 600,
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(color: neonCyan.withValues(alpha:0.1), blurRadius: 40, spreadRadius: 2)
                    ],
                  ),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                        child: Stack(
                          children: [
                            Image.network(
                              place['image'], 
                              height: 320, 
                              width: double.infinity, 
                              fit: BoxFit.cover,
                            ),
                          ],
                        ),
                      ),
                      // ... (rest of the popup remains the same)
                      Expanded(
                        child: Container(
                           padding: const EdgeInsets.all(20),
                           alignment: Alignment.center,
                           child: Text("More details coming soon...", style: TextStyle(color: Colors.grey.shade800)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final screenWidth = MediaQuery.of(context).size.width;
    final double glassBarWidth = _isSearchActive ? screenWidth - 40 : 160; // Slightly wider for icons

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D), // Exact dark background from image
      body: Stack(
        children: [
          // GRID CONTENT
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Extra space at top to clear the floating buttons perfectly
              SliverToBoxAdapter(child: SizedBox(height: topPadding + 70)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column
                      Expanded(
                        child: Column(
                          children: _displayPlaces
                              .asMap().entries.where((e) => e.key % 2 == 0)
                              .map((e) => _buildCardWrapper(e.value)).toList(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Right Column
                      Expanded(
                        child: Column(
                          children: _displayPlaces
                              .asMap().entries.where((e) => e.key % 2 != 0)
                              .map((e) => _buildCardWrapper(e.value)).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),

          // 🔥 EXACTLY ALIGNED BACK BUTTON (Matches Reel Screen)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            top: topPadding + 12, // Exact match
            left: _isSearchActive ? -80 : 16,
            child: GestureDetector(
              onTap: () {
                AppHaptics.lightImpact();
                Navigator.maybePop(context); 
              },
              child: _buildGlassButton(icon: Icons.arrow_back_ios_new_rounded),
            ),
          ),

          // 🔥 EXACTLY ALIGNED GLASS BAR
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            top: topPadding + 12, // Exact match
            right: 16,
            width: _isBarExpanded 
                ? (_isSearchActive ? screenWidth - 32 : glassBarWidth) 
                : 44, // Match width to height when collapsed
            child: GestureDetector(
              onTap: () { if (!_isBarExpanded) _toggleBar(); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutBack,
                height: 44, // EXACT HEIGHT MATCH
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.horizontal(
                    left: const Radius.circular(30),
                    right: Radius.circular(_isBarExpanded ? 30 : 30), // Always pill shaped
                  ),
                  color: Colors.white.withValues(alpha:0.15), // Premium frosted match
                  border: Border.all(color: Colors.white.withValues(alpha:0.1), width: 0.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha:0.2), blurRadius: 10)
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Container(
                        width: _isBarExpanded ? (_isSearchActive ? screenWidth - 34 : glassBarWidth - 2) : 42,
                        height: 44,
                        alignment: Alignment.center,
                        child: _isBarExpanded ? _buildExpandedBarContent() : _buildCollapsedArrow(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedBarContent() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start, 
      mainAxisSize: MainAxisSize.max,
      children: [
        if (_isSearchActive) ...[
          const SizedBox(width: 12),
          const Icon(Icons.search, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (val) => _applyFilters(),
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: "Search city...",
                hintStyle: TextStyle(color: Colors.white54, fontSize: 14),
                border: InputBorder.none,
                isDense: true, 
                contentPadding: EdgeInsets.zero,
              ),
              textAlignVertical: TextAlignVertical.center,
            ),
          ),
          GestureDetector(
            onTap: _toggleSearch,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
          const SizedBox(width: 8),
        ] else ...[
          Expanded(
            child: Row(
               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
               children: [
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white, size: 20),
                    onPressed: _toggleSearch,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(_showOnlyFavorites ? CupertinoIcons.heart_fill : CupertinoIcons.heart, 
                      color: _showOnlyFavorites ? Colors.redAccent : Colors.white, size: 20),
                    onPressed: _toggleFavoriteFilter,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(Icons.tune_rounded, color: neonCyan, size: 20),
                    onPressed: _showFilterPopup, // Need to define this if not present
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
               ],
            ),
          )
        ],
      ],
    );
  }

  void _showFilterPopup() {} // Placeholder, add your existing logic here

  Widget _buildCollapsedArrow() {
    return Icon(Icons.menu_open_rounded, color: neonCyan, size: 18);
  }

  Widget _buildGlassButton({required IconData icon}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(50),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 44, height: 44, // EXACT MATCH
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha:0.15),
            border: Border.all(color: Colors.white.withValues(alpha:0.2), width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.only(right: 2.0),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildCardWrapper(Map<String, dynamic> place) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PlaceCard(
        place: place,
        neonCyan: neonCyan,
        onLikeChanged: _onLikeChanged,
        onLongPress: () => _showIOSDetailPopup(place), 
        onPinToggle: _onPinToggle,
      ),
    );
  }
}

// 🔥 REDESIGNED CARD WIDGET (Exact match to reference image)
class PlaceCard extends StatefulWidget {
  final Map<String, dynamic> place;
  final Color neonCyan;
  final Function(int, bool) onLikeChanged;
  final VoidCallback onLongPress;
  final Function(int) onPinToggle;

  const PlaceCard({
    super.key, 
    required this.place, 
    required this.neonCyan,
    required this.onLikeChanged,
    required this.onLongPress,
    required this.onPinToggle,
  });

  @override
  State<PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<PlaceCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  bool _isLiked = false;
  bool _isHeartAnimating = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.place['isLiked'] ?? false;
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut)
    );
  }

  @override
  void didUpdateWidget(PlaceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.place['isLiked'] != _isLiked) {
      setState(() => _isLiked = widget.place['isLiked']);
    }
  }

  void _handleLikeAction() {
    setState(() {
      _isLiked = !_isLiked;
      _isHeartAnimating = true;
    });
    widget.onLikeChanged(widget.place['id'], _isLiked);
    _controller.forward().then((_) {
      _controller.reverse();
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _isHeartAnimating = false);
      });
    });
    AppHaptics.lightImpact();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isPinned = widget.place['isPinned'] ?? false;

    return GestureDetector(
      onTap: () {
        AppHaptics.heavyImpact();
        Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (context, animation, secondaryAnimation) => PlaceDetailScreen(
              place: widget.place, // Card ka pura data pass kar rahe hain
              userLat: 28.6139, // Dummy or actual user location
              userLng: 77.2090,
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
      },
      onDoubleTap: _handleLikeAction,
      onLongPress: widget.onLongPress,
      child: Container(
        height: widget.place['height'],
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26), // Super smooth rounded corners
          color: const Color(0xFF1E1E1E), // Dark placeholder
          image: DecorationImage(
            image: NetworkImage(widget.place['image']),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low, 
          ),
          boxShadow: [
             BoxShadow(color: Colors.black.withValues(alpha:0.2), blurRadius: 8, offset: const Offset(0, 4))
          ]
        ),
        child: Stack(
          children: [
            // Smooth Dark Gradient at bottom for text readability
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.transparent, Colors.black.withValues(alpha:0.85)],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
            
            // Heart Animation Overlay
            if (_isHeartAnimating)
              Center(
                child: ScaleTransition(
                  scale: _scale,
                  child: const Icon(Icons.favorite, color: Colors.white, size: 80),
                ),
              ),

            // 🔥 Top Right: Pinterest Style Pin Icon
            Positioned(
              top: 12, right: 12,
              child: GestureDetector(
                onTap: () => widget.onPinToggle(widget.place['id']),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isPinned ? Colors.white : Colors.black.withValues(alpha:0.3), 
                    shape: BoxShape.circle, // Circular like the image
                    border: Border.all(color: Colors.white.withValues(alpha:0.1), width: 0.5)
                  ),
                  child: Icon(
                    CupertinoIcons.pin_fill, // Sleek pin icon
                    color: isPinned ? Colors.black : Colors.white,
                    size: 14
                  ),
                ),
              ),
            ),

            // 🔥 Bottom Section: Text and Rating
            Positioned(
              bottom: 16, left: 16, right: 40,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Exact Match: Cyan Rating Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.neonCyan.withValues(alpha:0.15), // Translucent cyan
                      borderRadius: BorderRadius.circular(12), // Pill shape
                      border: Border.all(color: widget.neonCyan.withValues(alpha:0.4), width: 1), // Distinct border
                    ),
                    child: Text(
                      widget.place['rating'], 
                      style: TextStyle(color: widget.neonCyan, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Title
                  Text(
                    widget.place['title'], 
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3), 
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis
                  ),
                  const SizedBox(height: 4),
                  
                  // Location
                  Row(
                    children: [
                      Icon(CupertinoIcons.location_solid, color: Colors.grey.shade400, size: 12),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.place['location'], 
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.w500), 
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 🔥 Bottom Right: Heart Icon (Pinterest style)
            Positioned(
              bottom: 16, right: 16,
              child: GestureDetector(
                onTap: _handleLikeAction,
                child: Icon(
                  _isLiked ? CupertinoIcons.heart_fill : CupertinoIcons.heart, // Smooth iOS icons
                  color: _isLiked ? Colors.white : Colors.white, // In Pinterest dark mode, usually it stays white or turns red based on preference. Let's keep it white/red.
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}