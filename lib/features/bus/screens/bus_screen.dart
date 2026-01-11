import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:ridel/core/services/mic_service.dart';
import 'package:ridel/features/bus/screens/bus_route_screen.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/bus/services/bus_repository.dart';

class BusScreen extends StatefulWidget {
  const BusScreen({super.key});

  @override
  State<BusScreen> createState() => _BusScreenState();
}

class _BusScreenState extends State<BusScreen> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // --- Bus Repository ---
  final BusRepository _busRepository = BusRepository();
  Future<List<Map<String, dynamic>>>? _routesFuture;
  bool _isLoading = false;

  // --- Animation Controllers ---
  late AnimationController _entryController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _micGlowController; // New Glow for internal Mic

  // --- Text Controllers ---
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  bool _isMicActiveForFrom = true; // Track which field receives voice input
  
  // ✅ State variables to track selected stations
  Map<String, dynamic>? _selectedSourceStation;
  Map<String, dynamic>? _selectedDestStation;

  // --- Carousel State ---
  final PageController _pageController = PageController();
  int _activePage = 0;
  Timer? _carouselTimer;

  // --- UI State ---
  bool _isServicesExpanded = false;
  bool _isHistoryVisible = false;
  bool _isHistoryEnabled = true;

  @override
  bool get wantKeepAlive => true;

  final List<Map<String, String>> _busHistory = [
    {'from': 'Laxmi Nagar', 'to': 'Noida Sec 18'},
    {'from': 'Anand Vihar ISBT', 'to': 'Gurugram Cyber City'},
    {'from': 'Sarai Kale Khan', 'to': 'Dhaula Kuan'},
    {'from': 'Kashmere Gate', 'to': 'Nehru Place'},
  ];

  final List<Map<String, dynamic>> _otherServices = [
    {'icon': Icons.map_rounded, 'label': 'Bus Map'},
    {'icon': Icons.price_change_rounded, 'label': 'Fares'},
    {'icon': Icons.timelapse_rounded, 'label': 'Timetable'},
    {'icon': Icons.help_outline_rounded, 'label': 'Help'},
    {'icon': Icons.directions_bus_filled_rounded, 'label': 'Depots'},
    {'icon': Icons.report_problem_rounded, 'label': 'Report'},
    {'icon': Icons.find_in_page_rounded, 'label': 'Lost Item'},
    {'icon': Icons.contact_phone_rounded, 'label': 'Contact'},
  ];

  @override
  void initState() {
    super.initState();
    // Entry Animations
    _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryController, curve: Curves.fastOutSlowIn));
    _entryController.forward();

    // Mic Glow Animation
    _micGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _startAutoSlide();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _micGlowController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _pageController.dispose();
    _stopAutoSlide();
    super.dispose();
  }

  void _startAutoSlide() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (_pageController.hasClients) {
        int nextPage = _activePage + 1;
        if (nextPage > 1) nextPage = 0;
        _pageController.animateToPage(nextPage, duration: const Duration(milliseconds: 800), curve: Curves.fastOutSlowIn);
      }
    });
  }

  void _stopAutoSlide() {
    _carouselTimer?.cancel();
  }

  void _handleMicTap(bool isFrom) {
    final micService = Provider.of<MicService>(context, listen: false);
    AppHaptics.mediumImpact(); 
    setState(() => _isMicActiveForFrom = isFrom);
    if (micService.isListening) {
      micService.stopListening();
    } else {
      micService.startListening();
    }
  }

  void _toggleHistoryPanel() {
    AppHaptics.lightImpact();
    setState(() {
      _isHistoryVisible = !_isHistoryVisible;
    });
  }

  void _clearHistory() {
    AppHaptics.mediumImpact();
    setState(() {
      _busHistory.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    final topPadding = MediaQuery.of(context).padding.top;
    final micService = Provider.of<MicService>(context);
    final hour = DateTime.now().hour;
    String greeting = "Good Morning";
    if (hour >= 12 && hour < 17) greeting = "Good Afternoon";
    if (hour >= 17) greeting = "Good Evening";

    // Handle Mic Text Injection
    if (micService.isListening || micService.autoSubmitTriggered) {
      if (_isMicActiveForFrom) {
        _fromController.text = micService.recognizedText;
        _fromController.selection = TextSelection.fromPosition(TextPosition(offset: _fromController.text.length));
      } else {
        _toController.text = micService.recognizedText;
        _toController.selection = TextSelection.fromPosition(TextPosition(offset: _toController.text.length));
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Background Glow (Orange for Bus)
          Positioned(
            top: -100, right: -50,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.15),
                    blurRadius: 150,
                    spreadRadius: 20,
                  )
                ]
              ),
            ),
          ),

          // 2. Main Scrollable Content
          SingleChildScrollView(
            padding: EdgeInsets.only(top: topPadding + 15, left: 20, right: 20, bottom: 100),
            physics: const BouncingScrollPhysics(),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(greeting),
                    const SizedBox(height: 30),
                    
                    // --- IDENTICAL SEARCH BOX TO METRO ---
                    _buildSearchBox(micService),
                    
                    const SizedBox(height: 25),

                    if (_routesFuture != null)
                      _buildResultsSection(),

                    // --- IDENTICAL CAROUSEL TO METRO ---
                    GestureDetector(
                      onPanDown: (_) => _stopAutoSlide(),
                      child: Container(
                        height: 140,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF151515).withValues(alpha: 0.9),
                              const Color(0xFF151515).withValues(alpha: 0.7),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: PageView(
                            controller: _pageController,
                            onPageChanged: (index) {
                              setState(() => _activePage = index);
                            },
                            children: [
                              _buildCarouselSlide(
                                title: "WhatsApp Ticket",
                                subtitle: "Scan QR & Travel Ticketless",
                                icon: Icons.qr_code_rounded,
                                color: const Color(0xFF25D366),
                                bgGradient: [const Color(0xFF25D366).withValues(alpha: 0.1), Colors.transparent]
                              ),
                              _buildCarouselSlide(
                                title: "One India Pass",
                                subtitle: "Recharge Bus Card Instantly",
                                icon: Icons.credit_card_rounded,
                                color: Colors.blueAccent,
                                bgGradient: [Colors.blue.withValues(alpha: 0.1), Colors.transparent]
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(2, (index) => _buildDot(index))),

                    const SizedBox(height: 30),

                    // --- SERVICES SECTION ---
                    _buildExpandableServicesSection(),

                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
          ),

          // 3. History Overlay
          if (_isHistoryVisible)
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleHistoryPanel,
                child: Container(color: Colors.black.withValues(alpha: 0.6)),
              ),
            ),

          // 4. History Panel
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.fastOutSlowIn,
            bottom: _isHistoryVisible ? 0 : -600,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.6,
            child: _buildHistoryPanel(),
          ),
        ],
      ),
    );
  }

  void _searchRoutes() {
    // ✅ FIX: Text controllers se directly text uthao (Manual typing support)
    final fromText = _fromController.text.trim();
    final toText = _toController.text.trim();
    
    // Validation
    if (fromText.isEmpty || toText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter both start and end locations.', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    // Keyboard hide karo search start hone par
    FocusScope.of(context).unfocus();
    
    setState(() {
      _isLoading = true;
      // ✅ FIX: Database query directly text ke basis par hogi
      _routesFuture = _busRepository.getSmartRoutes(
        fromText,
        toText,
      ).whenComplete(() {
        // Search complete hone par loading band karo
        if (mounted) {
          setState(() => _isLoading = false);
        }
      });
    });
  }

  Widget _buildResultsSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _routesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No routes found.', style: TextStyle(color: Colors.white)));
        }

        final routes = snapshot.data!;
        // Assuming the Future is complete, set isLoading to false
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        });
        return _buildResultsList(routes);
      },
    );
  }

  Widget _buildResultsList(List<Map<String, dynamic>> routes) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: routes.length,
      itemBuilder: (context, index) {
        final route = routes[index];
        final priority = route['priority_level'];

        switch (priority) {
          case 1:
            return _buildDirectRouteCard(route);
          case 2:
            return _buildInterchangeRouteCard(route);
          case 3:
            return _buildWalkingRouteCard(route);
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _buildDirectRouteCard(Map<String, dynamic> route) {
    return Card(
      color: Colors.grey[900],
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        title: Text(
          'Bus ${route['bus_number'] ?? 'N/A'}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${route['start_stop'] ?? 'N/A'} -> ${route['end_stop'] ?? 'N/A'}',
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _buildInterchangeRouteCard(Map<String, dynamic> route) {
    return Card(
      color: Colors.grey[900],
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bus ${route['bus_1_number'] ?? 'N/A'} -> Change at ${route['interchange_stop'] ?? 'N/A'} -> Bus ${route['bus_2_number'] ?? 'N/A'}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            if (route['walk_instruction'] != null && route['walk_instruction'] != 'Same Stop Change')
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  route['walk_instruction'],
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalkingRouteCard(Map<String, dynamic> route) {
    return Card(
      color: Colors.grey[900],
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.directions_walk, color: Colors.orange),
        title: Text(
          'Bus ${route['bus_1_number'] ?? 'N/A'} -> 🚶 Walk -> Bus ${route['bus_2_number'] ?? 'N/A'}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          route['walk_instruction'] ?? 'N/A',
          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildHeader(String greeting) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // LEFT SIDE: Icon + Text
        Row(
          children: [
            Container(
              height: 48, width: 48,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.1), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
              child: const Icon(Icons.directions_bus_rounded, color: Colors.orange, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting, style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                const Text("Traveler", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        
        // RIGHT SIDE: Location + SOS + History
        Row(
          children: [
            // 1. Location Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
              child: Row(
                children: [
                  const Text("Delhi", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded, color: Colors.blue.shade300, size: 16)
                ],
              ),
            ),
            
            const SizedBox(width: 10),

            // 2. SOS BUTTON (Added Back)
            GestureDetector(
              onTap: () { 
                AppHaptics.mediumImpact(); 
                // Add SOS Logic here if needed
              }, 
              child: Container(
                height: 40, width: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, 
                  color: Colors.red.withValues(alpha: 0.15), 
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3))
                ),
                child: const Icon(Icons.sos_rounded, color: Colors.redAccent, size: 18),
              ),
            ),

            const SizedBox(width: 10),

            // 3. History Button
            GestureDetector(
              onTap: _toggleHistoryPanel,
              child: Container(
                height: 40, width: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.08), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
                child: const Icon(Icons.history_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- 1. SEARCH BOX CONTAINER ---
  Widget _buildSearchBox(MicService micService) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF151515), // Outer Box
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildTypeAheadInput(
                  'From Stand', 
                  Icons.directions_bus_outlined, 
                  Colors.greenAccent, 
                  _fromController,
                  isFromField: true,
                  isMicActive: micService.isListening && _isMicActiveForFrom, 
                  onMicTap: () => _handleMicTap(true)
                )
              ),
              const SizedBox(width: 10),
              // Map/Shrink Button
              _buildSquareButton(
                icon: Icons.map_rounded, 
                color: Colors.white.withValues(alpha: 0.1), 
                iconColor: Colors.blue.shade300, 
                onTap: () { 
                  AppHaptics.lightImpact(); 
                  debugPrint("Open Map"); 
                }
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildTypeAheadInput(
                  'To Destination', 
                  Icons.location_on_outlined, 
                  Colors.redAccent, 
                  _toController,
                  isFromField: false,
                  isMicActive: micService.isListening && !_isMicActiveForFrom, 
                  onMicTap: () => _handleMicTap(false)
                )
              ),
              const SizedBox(width: 10),
              // Search Button
              _buildSquareButton(
                icon: Icons.arrow_forward_rounded,
                color: const Color(0xFFFF4500), // Orange for Bus
                iconColor: Colors.white,
                onTap: _searchRoutes,
                isLoading: _isLoading,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- 2. THE KEY FIX: TYPE AHEAD INPUT WITH DARK INNER BOX ---
  Widget _buildTypeAheadInput(String hint, IconData icon, Color iconColor, TextEditingController externalController, {required bool isFromField, required bool isMicActive, required VoidCallback onMicTap}) {
    // ✅ Updated to match Metro Design (Darker Inner Container)
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F), // ✅ Inner Dark Color (Metro Style)
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          // Icon Left
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          
          // TypeAhead Logic
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: externalController,
              builder: (context, value, child) {
                return TypeAheadField<Map<String, dynamic>>(
                  builder: (context, typeAheadController, focusNode) {
                    // Sync controllers logic preserved
                    if (typeAheadController.text != externalController.text) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (typeAheadController.text != externalController.text) {
                          typeAheadController.text = externalController.text;
                          typeAheadController.selection = TextSelection.fromPosition(
                            TextPosition(offset: externalController.text.length),
                          );
                        }
                      });
                    }
                    
                    return TextField(
                      controller: typeAheadController,
                      focusNode: focusNode,
                      onTap: () { AppHaptics.lightImpact(); },
                      onChanged: (value) {
                        if (externalController.text != value) {
                          externalController.text = value;
                        }
                      },
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      cursorColor: Colors.orange,
                      // ✅ Decoration Simplified (No Borders, No Prefix Icon)
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    );
                  },
                  suggestionsCallback: (pattern) async {
                    if (pattern.isEmpty) return [];
                    return await _busRepository.searchStops(pattern);
                  },
                  itemBuilder: (context, suggestion) {
                    return ListTile(
                      title: Text(
                        suggestion['stop_name'] ?? '', 
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      tileColor: Colors.grey[850],
                    );
                  },
                  onSelected: (suggestion) {
                    final stopName = suggestion['stop_name'] ?? '';
                    if (isFromField) {
                      _fromController.text = stopName;
                      _selectedSourceStation = suggestion;
                    } else {
                      _toController.text = stopName;
                      _selectedDestStation = suggestion;
                    }
                    setState(() {});
                    FocusScope.of(context).unfocus();
                    
                    // Auto-trigger search logic preserved
                    Future.delayed(const Duration(milliseconds: 200), () {
                      if (mounted && _fromController.text.trim().isNotEmpty && _toController.text.trim().isNotEmpty) {
                        _searchRoutes();
                      }
                    });
                  },
                  decorationBuilder: (context, child) {
                    return Material(
                      type: MaterialType.card,
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey[850],
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 250),
                        child: child,
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Mic Icon (Aligned Right inside the box)
          GestureDetector(
            onTap: onMicTap,
            child: AnimatedBuilder(
              animation: _micGlowController,
              builder: (context, child) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isMicActive ? Colors.orange.withValues(alpha: 0.2) : Colors.transparent,
                    boxShadow: isMicActive ? [BoxShadow(color: Colors.orange.withValues(alpha: 0.5), blurRadius: 5 + (_micGlowController.value * 8))] : [],
                  ),
                  child: Icon(Icons.mic_rounded, color: isMicActive ? Colors.orange : Colors.grey.shade600, size: 20),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- 3. SQUARE BUTTON (Helper) ---
  Widget _buildSquareButton({required IconData icon, required Color color, required Color iconColor, required VoidCallback onTap, bool isLoading = false}) {
    return GestureDetector(
      onTap: onTap, 
      child: Container(
        height: 50, 
        width: 50, 
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)), 
        child: isLoading 
            ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))) 
            : Icon(icon, color: iconColor, size: 24)
      )
    );
  }

  Widget _buildCarouselSlide({required String title, required String subtitle, required IconData icon, required Color color, required List<Color> bgGradient}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(gradient: LinearGradient(colors: bgGradient, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Row(
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 6), Text(subtitle, style: TextStyle(color: Colors.grey.shade400, fontSize: 12, height: 1.4), maxLines: 2)])),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.3))), child: Icon(icon, color: color, size: 28))
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    bool isActive = _activePage == index;
    return AnimatedContainer(duration: const Duration(milliseconds: 300), margin: const EdgeInsets.symmetric(horizontal: 4), height: 6, width: isActive ? 20 : 6, decoration: BoxDecoration(color: isActive ? Colors.orange : Colors.grey.shade800, borderRadius: BorderRadius.circular(3)));
  }

  Widget _buildExpandableServicesSection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () {
                AppHaptics.lightImpact();
                setState(() {
                  _isServicesExpanded = !_isServicesExpanded;
                });
              },
              child: Container(
                color: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    const Text("Other Services", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 5),
                    AnimatedRotation(
                      turns: _isServicesExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        AnimatedCrossFade(
          firstChild: _buildServiceGrid(limit: 4),
          secondChild: _buildServiceGrid(limit: _otherServices.length),
          crossFadeState: _isServicesExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 400),
          sizeCurve: Curves.fastOutSlowIn,
        ),
      ],
    );
  }

  Widget _buildServiceGrid({required int limit}) {
    return Padding(
      padding: const EdgeInsets.only(top: 15),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 0.85, 
          crossAxisSpacing: 10,
          mainAxisSpacing: 8, 
        ),
        itemCount: limit,
        itemBuilder: (context, index) {
          final service = _otherServices[index];
          return _buildServiceIcon(service['icon'], service['label']);
        },
      ),
    );
  }

  Widget _buildServiceIcon(IconData icon, String label) {
    return GestureDetector(
      onTap: () { AppHaptics.lightImpact(); },
      child: Column(
        children: [
          Container(
            height: 50, width: 50, 
            decoration: BoxDecoration(color: const Color(0xFF151515), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
            child: Icon(icon, color: Colors.grey.shade300, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 10, fontWeight: FontWeight.w500), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildHistoryPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF101010).withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, -10))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: _isHistoryEnabled,
                      activeThumbColor: Colors.orange,
                      onChanged: (val) {
                        AppHaptics.lightImpact();
                        setState(() => _isHistoryEnabled = val);
                      },
                    ),
                  ),
                  Text(_isHistoryEnabled ? "History On" : "Paused", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ],
              ),
              Container(height: 4, width: 40, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2))),
              GestureDetector(
                onTap: _clearHistory,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _busHistory.isEmpty
                ? Center(child: Text("No recent searches", style: TextStyle(color: Colors.grey[600])))
                : ListView.builder(
                    itemCount: _busHistory.length,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (ctx, index) {
                      final item = _busHistory[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.history_rounded, color: Colors.blueGrey),
                          title: Text("${item['from']} → ${item['to']}", style: const TextStyle(color: Colors.white, fontSize: 14)),
                          trailing: const Icon(Icons.north_west_rounded, size: 16, color: Colors.grey),
                          onTap: () {
                            setState(() {
                              _fromController.text = item['from']!;
                              _toController.text = item['to']!;
                              _isHistoryVisible = false; 
                            });
                            AppHaptics.mediumImpact();
                          },
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 80), 
        ],
      ),
    );
  }
}