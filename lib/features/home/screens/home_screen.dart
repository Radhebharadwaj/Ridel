import 'package:flutter/material.dart';
import 'dart:ui' as ui; 
import 'dart:async';
import 'package:provider/provider.dart';

// ✅ IMPORT SERVICES & SCREENS
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/services/mic_service.dart';
import 'package:ridel/features/tour/screens/suggested_card.dart';
import 'package:ridel/features/tour/screens/all_place.dart';
import 'package:ridel/features/bus/screens/bus_route_screen.dart';
import 'package:ridel/features/tour/screens/chat_screen.dart';
import 'package:ridel/features/metro/screens/select_screen.dart';

class HomeScreen extends StatefulWidget {
  final Function(int index) onNavigateToTab; 

  const HomeScreen({
    super.key,
    required this.onNavigateToTab,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  late AnimationController _micScaleController;
  late Animation<double> _micScaleAnimation;
  late AnimationController _aiPulseController;
  late Animation<double> _aiPulseAnimation;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  final ScrollController _scrollController = ScrollController();
  bool _isCompactMode = false; 

  // Controllers for Popups
  final TextEditingController _popupFromController = TextEditingController();
  final TextEditingController _popupToController = TextEditingController();

  int _currentMsgIndex = 0;
  Timer? _textTimer;

  final List<String> _messages = [
    "Confused where to go?", "Dreaming of a getaway?", "Need a travel buddy?", "Mountains or Beaches?",
    "On a tight budget?", "Craving a hidden gem?", "Foodie at heart?", "Seeking spiritual peace?",
    "Adventure calling?", "Romantic getaway?", "Solo trip on your mind?", "Family vacation time?",
    "Wanderlust kicking in?", "History buff?", "Late night thoughts?", "Need a break from work?",
    "Backpacking India?", "Luxury awaits...", "Into the wild?", "Capture the moment.",
    "Taste of India.", "Spiritual awakening?", "Adrenaline junkie?", "Honeymoon vibes?",
    "Friends reunion?", "Explore the unseen.", "Road trip ready?", "Festival season?",
    "Just one day off?", "Winter wonderland?", "Monsoon magic?", "Desert safari?",
    "Island hopping?", "Yoga retreat?", "Shopping spree?", "Art and Culture.",
    "Nightlife scene.", "Staycation mode.", "Eco-friendly travel.", "Train journeys.",
    "Travel smart.", "Unlock new places.", "Your journey begins.", "Escape the ordinary.",
    "Find your paradise.", "Let's get lost.", "Make memories.", "Ready to fly?",
    "Discover yourself.", "The world awaits."
  ];

  final List<String> _subMessages = [
    "Tell AI your mood, budget & days...", "Let's plan your perfect escape!",
    "AI is ready to explore with you...", "I can help you decide the vibe.",
    "Experience luxury for less. Ask how.", "Let's find places off the map.",
    "Discover the best local cuisines.", "Find serenity in holy cities.",
    "Trekking, rafting, or diving? Let's plan.", "Perfect spots for just the two of you.",
    "Safe & exciting solo itineraries.", "Fun for kids, relaxing for you.",
    "Let's map out your dream journey.", "Explore ancient forts & timeless tales.",
    "Plan your trip while the world sleeps.", "Find the perfect chill zone nearby.",
    "Curated hostels and budget routes.", "Book the finest stays & experiences.",
    "Safaris, camping, and nature trails.", "Photogenic spots you can't miss.",
    "A culinary journey awaits you.", "Temples, Ashrams, and inner peace.",
    "Bungee, paragliding, and more!", "Romantic destinations curated with love.",
    "Group friendly spots for memories.", "Hidden gems tourists often miss.",
    "Scenic routes and pitstops.", "Experience vibrant culture live.",
    "Perfect day-trip ideas near you.", "Snowfall and cozy fires await.",
    "Lush greenery and waterfalls calling.", "Camels, folk music, and stars.",
    "Blue waters and sandy toes.", "Rejuvenate your mind, body & soul.",
    "Best markets and bazaars in town.", "Museums, galleries & heritage walks.",
    "Best clubs and evening hangouts.", "Best local resorts for a recharge.",
    "Sustainable stays and green trips.", "Scenic rail routes you must see.",
    "AI tips for a hassle-free trip.", "Secret spots just for you.",
    "Start your adventure today.", "Unique experiences await.",
    "Your dream destination is here.", "Explore the unknown with AI.",
    "Travel stories start here.", "Fastest routes & best prices.",
    "New experiences, new you.", "Let's go somewhere new."
  ];

  @override
  bool get wantKeepAlive => true;

  final List<PlaceItem> _allPlaces = [
    PlaceItem(id: 'p1', title: 'Taj Mahal', subtitle: 'Symbol of Love, Agra', iconData: Icons.place_rounded, color: const Color(0xFF00E5FF)),
    PlaceItem(id: 'p2', title: 'Red Fort', subtitle: 'Mughal History, Delhi', iconData: Icons.fort_rounded, color: const Color(0xFF00FF94)),
    PlaceItem(id: 'p3', title: 'Jaipur City', subtitle: 'The Pink City, Rajasthan', iconData: Icons.location_city_rounded, color: const Color(0xFFFFD600)),
    PlaceItem(id: 'p4', title: 'Kerala Backwaters', subtitle: 'Serene Houseboats', iconData: Icons.water_rounded, color: Colors.tealAccent),
    PlaceItem(id: 'p5', title: 'Varanasi Ghats', subtitle: 'Spiritual Capital', iconData: Icons.temple_hindu_rounded, color: Colors.orangeAccent),
    PlaceItem(id: 'p6', title: 'Goa Beaches', subtitle: 'Sun, Sand, and Sea', iconData: Icons.beach_access_rounded, color: Colors.lightBlueAccent),
    PlaceItem(id: 'p7', title: 'Himalayas', subtitle: 'Majestic Mountains', iconData: Icons.landscape_rounded, color: Colors.white70),
  ];

  List<PlaceItem> _displayedPlaces = [];
  final List<PlaceItem> _pinnedPlaces = [];

  final List<Map<String, dynamic>> _featureCards = [
    {'title': 'Metro', 'description': 'Real-time Routes', 'color': const Color(0xFF00E5FF), 'icon': Icons.directions_subway_filled, 'type': 'Metro'},
    {'title': 'Bus', 'description': 'Live Tracking', 'color': const Color(0xFF00FF94), 'icon': Icons.directions_bus_filled, 'type': 'Bus'},
    {'title': 'Trip Plan', 'description': 'AI Itinerary', 'color': const Color(0xFFFF5E00), 'icon': Icons.luggage_rounded, 'type': 'Trip'},
    {'title': 'Stay', 'description': 'Best Hotels', 'color': const Color(0xFF2979FF), 'icon': Icons.hotel_rounded, 'type': 'Stay'},
    {'title': 'Map', 'description': 'City Guide', 'color': Colors.purpleAccent, 'icon': Icons.map_rounded, 'type': 'Map'},
    {'title': 'Food', 'description': 'Street Food', 'color': Colors.pinkAccent, 'icon': Icons.fastfood_rounded, 'type': 'Food'},
  ];

  @override
  void initState() {
    super.initState();
    _shuffleAndShowPlaces();
    
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutQuart));
    _slideAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));

    _micScaleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
    _micScaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(CurvedAnimation(parent: _micScaleController, curve: Curves.easeInOut));

    _aiPulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _aiPulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(CurvedAnimation(parent: _aiPulseController, curve: Curves.easeInOut));
    _aiPulseController.repeat(reverse: true);

    _searchFocusNode.addListener(() {
      final micService = Provider.of<MicService>(context, listen: false);
      if (!_searchFocusNode.hasFocus && micService.isListening) micService.stopListening();
    });

    _searchController.addListener(() => setState(() {}));
    _animationController.forward();
    _startTextAnimation();
  }

  void _startTextAnimation() {
    _textTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        setState(() {
          _currentMsgIndex = (_currentMsgIndex + 1) % _messages.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _micScaleController.dispose();
    _aiPulseController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _popupFromController.dispose();
    _popupToController.dispose();
    _textTimer?.cancel(); 
    super.dispose();
  }
  
  void _shuffleAndShowPlaces() {
    setState(() {
      List<PlaceItem> available = List.from(_allPlaces);
      available.shuffle(); 
      _displayedPlaces = available.take(3).toList();
    });
  }
  
  void _replacePlace(String idToRemove) {
    setState(() {
      List<PlaceItem> current = _displayedPlaces.where((item) => item.id != idToRemove).toList();
      List<PlaceItem> available = _allPlaces.where((item) => !current.any((c) => c.id == item.id) && item.id != idToRemove).toList();
      if (available.isNotEmpty) {
        available.shuffle();
        current.add(available.first);
      }
      _displayedPlaces = current;
    });
  }

  void _toggleCompactMode() {
    AppHaptics.mediumImpact(); // ✅ FIXED HAPTIC
    setState(() => _isCompactMode = !_isCompactMode);
    _scrollController.animateTo(_isCompactMode ? 450 : 0, duration: const Duration(milliseconds: 600), curve: Curves.fastOutSlowIn);
  }

  void _showTransportPopup(BuildContext context, String type, Color color, int targetTabIndex) {
    _popupFromController.clear();
    _popupToController.clear();

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) => const SizedBox(),
      transitionBuilder: (ctx, anim1, anim2, child) {
        final slideValue = Curves.fastOutSlowIn.transform(anim1.value);
        return Transform.translate(
          offset: Offset(0, (1 - slideValue) * 100),
          child: Opacity(
            opacity: anim1.value,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 95),
                child: Material(
                  color: Colors.transparent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF151515).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30, spreadRadius: 0),
                            BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 20, spreadRadius: -5),
                          ],
                        ),
                        child: type == 'Metro' 
                          ? _buildMetroInputBox(context, targetTabIndex)
                          : _buildBusInputBox(context, targetTabIndex),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetroInputBox(BuildContext context, int tabIndex) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: _buildCompactInput('From Station', Icons.train_outlined, Colors.greenAccent, _popupFromController)),
              const SizedBox(width: 10),
              _buildSquareButton(
                icon: Icons.open_in_full_rounded,
                color: Colors.white.withValues(alpha: 0.1),
                iconColor: Colors.white70,
                onTap: () {
                  AppHaptics.lightImpact(); // ✅ FIXED HAPTIC
                  Navigator.pop(context);
                  widget.onNavigateToTab(tabIndex);
                }
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildCompactInput('To Station', Icons.location_on_outlined, Colors.redAccent, _popupToController)),
              const SizedBox(width: 10),
              _buildSquareButton(
                icon: Icons.arrow_forward_rounded,
                color: Colors.blue.shade600,
                iconColor: Colors.white,
                onTap: () {
                  AppHaptics.heavyImpact(); // ✅ FIXED HAPTIC
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const SelectScreen()));
                }
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBusInputBox(BuildContext context, int tabIndex) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCompactRow('From Stand', Icons.directions_bus_outlined, Colors.greenAccent, _popupFromController),
                Divider(color: Colors.white.withValues(alpha: 0.1), height: 16),
                _buildCompactRow('To Destination', Icons.location_on_outlined, Colors.redAccent, _popupToController),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () {
                   AppHaptics.lightImpact(); // ✅ FIXED HAPTIC
                   Navigator.pop(context);
                   widget.onNavigateToTab(tabIndex);
                },
                child: Container(
                  height: 44, width: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: const Icon(Icons.open_in_full_rounded, color: Colors.white54, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                   AppHaptics.heavyImpact(); // ✅ FIXED HAPTIC
                   Navigator.pop(context);
                   Navigator.push(context, MaterialPageRoute(builder: (context) => const BusRouteScreen()));
                },
                child: Container(
                  height: 44, width: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFF8C00), Color(0xFFFF4500)]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.4), blurRadius: 10)],
                  ),
                  child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 24),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildCompactInput(String hint, IconData icon, Color iconColor, TextEditingController controller) {
    return Container(
      height: 50,
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 15), 
            cursorColor: Colors.blue, 
            decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14), border: InputBorder.none, contentPadding: EdgeInsets.zero))),
        ],
      ),
    );
  }

  Widget _buildCompactRow(String hint, IconData icon, Color iconColor, TextEditingController controller) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSquareButton({required IconData icon, required Color color, required Color iconColor, required VoidCallback onTap}) {
    return GestureDetector(onTap: onTap, child: Container(height: 50, width: 50, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: iconColor, size: 24)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final topPadding = MediaQuery.of(context).padding.top;
    final micService = Provider.of<MicService>(context);

    if (micService.isListening) {
      if (!_micScaleController.isAnimating) _micScaleController.repeat(reverse: true);
    } else {
      _micScaleController.stop();
    }

    if (micService.isListening || micService.autoSubmitTriggered) {
      _searchController.text = micService.recognizedText;
      _searchController.selection = TextSelection.fromPosition(TextPosition(offset: _searchController.text.length));
    }

    if (micService.autoSubmitTriggered) {
      _searchFocusNode.unfocus();
    }

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          // ✅ Using Stack to layer the Fixed Header over Scrollable Content
          body: Stack(
            children: [
              // 1. Background Blobs
              RepaintBoundary(
                child: Stack(
                  children: [
                    Positioned(top: -100, left: -100, child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80), child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blueAccent.withValues(alpha: 0.15))))),
                    Positioned(bottom: 100, right: -50, child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80), child: Container(width: 250, height: 250, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.purpleAccent.withValues(alpha: 0.1))))),
                  ],
                ),
              ),

              // 2. Main Content (Scrollable)
              FadeTransition(
                opacity: _fadeAnimation,
                child: Transform.translate(
                  offset: Offset(0, _slideAnimation.value),
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    slivers: [
                      // ✅ Space at TOP for the Fixed Search Bar
                      SliverPadding(padding: EdgeInsets.only(top: topPadding + 85)),

                      SliverList(
                        delegate: SliverChildListDelegate([
                          
                          // AI Chat Hero Section
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
                            child: _buildAIChatHero(),
                          ),

                          const SizedBox(height: 20),

                          // Suggested Places
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                GestureDetector(
                                  onTap: () { AppHaptics.tickImpact(); Navigator.push(context, MaterialPageRoute(builder: (context) => const AllPlacesScreen())); },
                                  child: const Text('Suggested Places', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.5)),
                                ),
                                GestureDetector(
                                  onTap: () { AppHaptics.mediumImpact(); _shuffleAndShowPlaces(); },
                                  child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20)),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0),
                            child: Column(
                              children: _displayedPlaces.asMap().entries.map((entry) {
                                final item = entry.value;
                                return AnimatedContainer(
                                  duration: Duration(milliseconds: 400 + (entry.key * 100)),
                                  curve: Curves.easeOutQuart,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: SuggestedGlassCard(
                                    item: item,
                                    onTap: () { AppHaptics.tickImpact(); },
                                    onDismissed: () { AppHaptics.mediumImpact(); _replacePlace(item.id); },
                                    onPinned: () { 
                                      AppHaptics.heavyImpact(); // ✅ FIXED HAPTIC
                                      setState(() {
                                        item.isPinned = !item.isPinned;
                                        if (item.isPinned) {
                                          _pinnedPlaces.add(item);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('${item.title} pinned!'), duration: const Duration(seconds: 1), backgroundColor: item.color.withValues(alpha: 0.8)),
                                          );
                                        } else {
                                          _pinnedPlaces.removeWhere((element) => element.id == item.id);
                                        }
                                      });
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          const SizedBox(height: 30),

                          // Explore Features
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Explore Features', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.5)),
                                GestureDetector(
                                  onTap: _toggleCompactMode,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: _isCompactMode ? const Color(0xFF00E5FF).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                                    child: Icon(_isCompactMode ? Icons.grid_view_rounded : Icons.widgets_outlined, color: _isCompactMode ? const Color(0xFF00E5FF) : Colors.white.withValues(alpha: 0.8), size: 22),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              child: GridView.builder(
                                key: ValueKey(_isCompactMode),
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: _isCompactMode ? 3 : 2, 
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  // ✅ FIX: Ratio changed from 1.45 to 1.25 to prevent overflow
                                  childAspectRatio: _isCompactMode ? 1.0 : 1.25, 
                                ),
                                itemCount: _featureCards.length,
                                itemBuilder: (context, index) {
                                  final card = _featureCards[index];
                                  return _buildFeatureGlassCard(card);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 120),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. ✅ FIXED GLASS HEADER (Search Bar + Status Bar Strip)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25), // Strong Blur
                    child: Container(
                      padding: EdgeInsets.only(top: topPadding + 10, left: 20, right: 20, bottom: 15),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4), // Dark Glass Tint
                        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                      ),
                      child: _buildSquircleGlassInput(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // AI Card with Glowing Pulse Animation
  Widget _buildAIChatHero() {
    const neonColor = Color(0xFF00E5FF);

    return GestureDetector(
      onTap: () {
        AppHaptics.mediumImpact(); // ✅ FIXED HAPTIC
        Navigator.push(context, MaterialPageRoute(builder: (context) => const ChatScreen()));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF00332c), Color(0xFF000000)],
          ),
          border: Border.all(color: neonColor.withValues(alpha: 0.3), width: 1),
          boxShadow: [
            BoxShadow(color: neonColor.withValues(alpha: 0.1), blurRadius: 15, spreadRadius: 1),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: neonColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, color: neonColor, size: 10),
                        SizedBox(width: 5),
                        Text("AI COMPANION", style: TextStyle(color: neonColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 42,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: Column(
                        key: ValueKey<int>(_currentMsgIndex),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_messages[_currentMsgIndex], style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.1), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Text(_subMessages[_currentMsgIndex], style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              height: 50,
              width: 50,
              decoration: BoxDecoration(
                color: neonColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: neonColor.withValues(alpha: 0.3)),
                boxShadow: [BoxShadow(color: neonColor.withValues(alpha: 0.15), blurRadius: 12, spreadRadius: -2)]
              ),
              child: ScaleTransition(
                scale: _aiPulseAnimation,
                child: const Icon(Icons.auto_awesome, color: neonColor, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSquircleGlassInput() {
    final micService = Provider.of<MicService>(context);
    final bool isMicListening = micService.isListening;
    final Color micIconColor = isMicListening ? Colors.redAccent : Colors.white70;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18), 
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0), 
        child: Container(
          height: 48, 
          decoration: BoxDecoration(
            color: const Color(0xFF202020).withValues(alpha: 0.7), 
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 15),
              const Icon(Icons.search, color: Colors.white54, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: const InputDecoration(hintText: 'Search places...', hintStyle: TextStyle(color: Colors.white38, fontSize: 15), border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  cursorColor: Colors.cyanAccent,
                ),
              ),
              GestureDetector(
                onTap: () { AppHaptics.mediumImpact(); isMicListening ? micService.stopListening() : micService.startListening(); if(!isMicListening) _searchFocusNode.unfocus(); },
                child: Padding(
                  padding: const EdgeInsets.only(right: 15.0),
                  child: AnimatedBuilder(
                    animation: _micScaleController,
                    builder: (context, child) {
                      return Transform.scale(scale: isMicListening ? _micScaleAnimation.value : 1.0, child: Icon(Icons.mic_none_rounded, color: micIconColor, size: 22));
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureGlassCard(Map<String, dynamic> card) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_isCompactMode ? 18 : 24),
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_isCompactMode ? 18 : 24),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.02)]),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                ),
              ),
            ),
          ),
          if (!_isCompactMode)
            Positioned(
              right: -20, bottom: -20,
              child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80), child: Container(width: 100, height: 100, decoration: BoxDecoration(shape: BoxShape.circle, color: card['color'].withValues(alpha: 0.4)))),
            ),
          _isCompactMode 
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(card['icon'], color: card['color'], size: 32), const SizedBox(height: 8), Text(card['title'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white))]))
          : Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.1))), child: Icon(card['icon'], color: card['color'], size: 24)),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(card['title'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 4), Text(card['description'], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Colors.grey[400]))]),
              ],
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(_isCompactMode ? 18 : 24),
                splashColor: card['color'].withValues(alpha: 0.2),
                highlightColor: card['color'].withValues(alpha: 0.1),
                onTap: () {
                  if (card['type'] == 'Metro') {
                    AppHaptics.mediumImpact(); // ✅ FIXED HAPTIC
                    _showTransportPopup(context, 'Metro', card['color'], 1); 
                  } else if (card['type'] == 'Bus') {
                      AppHaptics.mediumImpact(); // ✅ FIXED HAPTIC
                    _showTransportPopup(context, 'Bus', card['color'], 3); 
                  } else {
                    AppHaptics.lightImpact(); // ✅ FIXED HAPTIC
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}