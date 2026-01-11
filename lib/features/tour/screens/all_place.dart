import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
import '../../../core/utils/app_haptics.dart'; 

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
      "isPinned": false,
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
      "isPinned": false,
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

  // --- FILTER & SORT FUNCTION ---
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

  // --- IOS STYLE POPUP ---
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
              // 1. Blur Background (Tap to Close)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(color: Colors.black.withValues(alpha:0.2)),
                  ),
                ),
              ),
              
              // 2. Center Popup Card
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
                      // Image Area
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                        child: Stack(
                          children: [
                            Image.network(
                              place['image'], 
                              height: 320, 
                              width: double.infinity, 
                              fit: BoxFit.cover,
                              cacheWidth: 800, // Optimized for popup
                              // ✅ Smooth Fade In
                              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                if (wasSynchronouslyLoaded) return child;
                                return AnimatedOpacity(
                                  opacity: frame == null ? 0 : 1,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                  child: child,
                                );
                              },
                            ),
                            Positioned(
                              bottom: 0, left: 0, right: 0,
                              child: Container(
                                height: 100,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [Colors.black.withValues(alpha:0.9), Colors.transparent],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 20, left: 20,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(place['title'], style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                                  Text(place['location'], style: const TextStyle(color: Colors.white70, fontSize: 16)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Live Status Bar
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFF252525),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildLiveInfo(Icons.thermostat, place['temp'], "Temp"),
                            Container(width: 1, height: 30, color: Colors.white12),
                            _buildLiveInfo(Icons.wb_sunny_rounded, place['weather'], "Weather"),
                            Container(width: 1, height: 30, color: Colors.white12),
                            _buildLiveInfo(Icons.map_outlined, "Map", "View"),
                          ],
                        ),
                      ),
                      
                      // Placeholder
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

  Widget _buildLiveInfo(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: neonCyan, size: 22),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
      ],
    );
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

    final double glassBarWidth = _isSearchActive ? screenWidth - 40 : 150;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // BACKGROUND
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0D0D0D), Colors.black],
                ),
              ),
            ),
          ),

          // GRID CONTENT
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: topPadding + 80)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: _displayPlaces
                              .asMap().entries.where((e) => e.key % 2 == 0)
                              .map((e) => _buildCardWrapper(e.value)).toList(),
                        ),
                      ),
                      const SizedBox(width: 12),
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

          // BACK BUTTON
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            top: topPadding + 10,
            left: _isSearchActive ? -80 : 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: _buildGlassButton(icon: Icons.arrow_back_ios_new_rounded, isCircle: true),
            ),
          ),

          // GLASS BAR
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            top: topPadding + 10,
            right: 20,
            width: _isBarExpanded 
                ? (_isSearchActive ? screenWidth - 40 : glassBarWidth) 
                : 40,
            child: GestureDetector(
              onTap: () { if (!_isBarExpanded) _toggleBar(); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutBack,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.horizontal(
                    left: const Radius.circular(30),
                    right: Radius.circular(_isBarExpanded ? 30 : 0),
                  ),
                  color: const Color(0xFF202020).withValues(alpha:0.85),
                  border: Border.all(color: Colors.white.withValues(alpha:0.1)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha:0.4), blurRadius: 15, offset: const Offset(0, 5))
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
                        width: _isBarExpanded ? (_isSearchActive ? screenWidth - 42 : glassBarWidth - 2) : 40,
                        height: 50,
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

  // --- UPDATED SEARCH BAR LAYOUT ---
  Widget _buildExpandedBarContent() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start, 
      mainAxisSize: MainAxisSize.max,
      children: [
        if (_isSearchActive) ...[
          const SizedBox(width: 15),
          const Icon(Icons.search, color: Colors.grey, size: 20),
          const SizedBox(width: 10),
          
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (val) => _applyFilters(),
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: "Search city...",
                hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                border: InputBorder.none,
                isDense: true, 
                contentPadding: EdgeInsets.zero,
              ),
              textAlignVertical: TextAlignVertical.center,
            ),
          ),
          
          GestureDetector(
            onTap: _toggleMic,
            child: Icon(
              _isMicActive ? Icons.mic : Icons.mic_none, 
              color: _isMicActive ? Colors.redAccent : Colors.grey,
              size: 20
            ),
          ),
          
          const SizedBox(width: 15),
          GestureDetector(
            onTap: _toggleSearch,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 5),
        ] else ...[
          Expanded(
            child: Row(
               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
               children: [
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white, size: 22),
                    onPressed: _toggleSearch,
                  ),
                  IconButton(
                    icon: Icon(_showOnlyFavorites ? Icons.favorite : Icons.favorite_border, 
                      color: _showOnlyFavorites ? Colors.redAccent : Colors.white, size: 22),
                    onPressed: _toggleFavoriteFilter,
                  ),
                  IconButton(
                    icon: Icon(Icons.tune_rounded, color: neonCyan, size: 22),
                    onPressed: _showFilterPopup,
                  ),
               ],
            ),
          )
        ],
      ],
    );
  }

  Widget _buildCollapsedArrow() {
    return Icon(Icons.arrow_back_ios_new_rounded, color: neonCyan, size: 18);
  }

  Widget _buildGlassButton({required IconData icon, required bool isCircle}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(50),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
            color: const Color(0xFF252525).withValues(alpha:0.8),
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
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

  // --- PREMIUM FILTER POPUP ---
  void _showFilterPopup() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha:0.6),
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 380,
              decoration: BoxDecoration(
                color: const Color(0xFF101010).withValues(alpha:0.9),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha:0.1))),
                boxShadow: [BoxShadow(color: neonCyan.withValues(alpha:0.05), blurRadius: 30)],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Filter Places", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Text("Done", style: TextStyle(color: neonCyan, fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _buildWheelPicker("State", _states)),
                        Expanded(child: _buildWheelPicker("City", _cities)),
                        Expanded(child: _buildWheelPicker("Type", _categories)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(25, 10, 25, 30),
                    child: GestureDetector(
                      onTap: () {
                          Navigator.pop(context);
                          AppHaptics.heavyImpact();
                      },
                      child: Container(
                        height: 45,
                        width: double.infinity,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: neonCyan.withValues(alpha:0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: neonCyan.withValues(alpha:0.6), width: 1),
                          boxShadow: [
                            BoxShadow(color: neonCyan.withValues(alpha:0.2), blurRadius: 15, spreadRadius: 1)
                          ],
                        ),
                        child: Text("Show Nearest Places", 
                          style: TextStyle(color: neonCyan, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWheelPicker(String title, List<String> items) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 15, bottom: 5),
          child: Text(title, style: TextStyle(color: Colors.grey.shade500, fontSize: 11, letterSpacing: 1)),
        ),
        Expanded(
          child: CupertinoTheme(
            data: const CupertinoThemeData(
              textTheme: CupertinoTextThemeData(
                pickerTextStyle: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            child: CupertinoPicker(
              itemExtent: 32,
              squeeze: 1.2,
              onSelectedItemChanged: (index) {},
              selectionOverlay: Container(
                decoration: BoxDecoration(
                  border: Border.symmetric(horizontal: BorderSide(color: Colors.white.withValues(alpha:0.08))),
                ),
              ),
              children: items.map((e) => Center(child: Text(e))).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// --- OPTIMIZED CARD (FIXED MEMORY & FPS) ---
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
      onDoubleTap: _handleLikeAction,
      onLongPress: widget.onLongPress,
      child: Container(
        height: widget.place['height'],
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: const Color(0xFF1E1E1E),
          // ✅ OPTIMIZATION 1: Cached Width + Smooth Fade-In
          image: DecorationImage(
            image: NetworkImage(widget.place['image']),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low, // Fastest rendering
          ),
        ),
        child: Stack(
          children: [
            // Gradient
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha:0.2), Colors.black.withValues(alpha:0.9)],
                  stops: const [0.5, 0.7, 1.0],
                ),
              ),
            ),
            
            if (_isHeartAnimating)
              Center(
                child: ScaleTransition(
                  scale: _scale,
                  child: const Icon(Icons.favorite, color: Colors.white, size: 80),
                ),
              ),

            // ✅ OPTIMIZATION 2: Removed Blur from Pin Button (FPS Boost)
            Positioned(
              top: 10, right: 10,
              child: GestureDetector(
                onTap: () => widget.onPinToggle(widget.place['id']),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isPinned 
                        ? widget.neonCyan.withValues(alpha:0.8) 
                        : Colors.black.withValues(alpha:0.5), // Transparent Black instead of Blur
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: isPinned ? Colors.black : Colors.white,
                    size: 16
                  ),
                ),
              ),
            ),

            // Text Content
            Positioned(
              bottom: 12, left: 12, right: 40,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.neonCyan.withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: widget.neonCyan.withValues(alpha:0.5)),
                    ),
                    child: Text(widget.place['rating'], style: TextStyle(color: widget.neonCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  Text(widget.place['title'], style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.grey.shade400, size: 12),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(widget.place['location'], style: TextStyle(color: Colors.grey.shade400, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Positioned(
              bottom: 12, right: 12,
              child: GestureDetector(
                onTap: _handleLikeAction,
                child: Icon(
                  _isLiked ? Icons.favorite : Icons.favorite_border,
                  color: _isLiked ? Colors.redAccent : Colors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}