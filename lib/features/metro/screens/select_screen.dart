import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui'; // Required for ImageFilter
import 'package:provider/provider.dart';
import 'package:ridel/core/services/mic_service.dart';
import 'package:ridel/features/metro/screens/route_screen.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/metro/services/metro_services.dart';
import 'package:ridel/features/metro/models/metro_models.dart';
import 'package:ridel/features/metro/screens/station_list.dart'; 

class SelectScreen extends StatefulWidget {
  final VoidCallback? onShrink;
  const SelectScreen({super.key, this.onShrink});

  @override
  State<SelectScreen> createState() => _SelectScreenState();
}

class _SelectScreenState extends State<SelectScreen> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  
  // Service Instance
  final MetroService _metroService = MetroService();
  
  bool _isMicActiveForFrom = true;
  late AnimationController _micGlowController;

  late AnimationController _entryController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // --- CAROUSEL STATE ---
  final PageController _pageController = PageController();
  int _activePage = 0;
  Timer? _carouselTimer;

  // --- UI STATE ---
  bool _isServicesExpanded = false;
  bool _isHistoryVisible = false;
  bool _isHistoryEnabled = true;

  @override
  bool get wantKeepAlive => true;

  final List<Map<String, dynamic>> _allServices = [
    {'icon': Icons.directions_bus_rounded, 'label': 'Feeder Bus'},
    {'icon': Icons.local_parking_rounded, 'label': 'Parking'},
    {'icon': Icons.store_mall_directory_rounded, 'label': 'Shops'},
    {'icon': Icons.help_outline_rounded, 'label': 'Help Info'},
    {'icon': Icons.wifi_rounded, 'label': 'Wi-Fi'},
    {'icon': Icons.atm_rounded, 'label': 'ATM'},
    {'icon': Icons.accessible_rounded, 'label': 'Divyangjan'},
    {'icon': Icons.wc_rounded, 'label': 'Restroom'},
    {'icon': Icons.security_rounded, 'label': 'Security'},
    {'icon': Icons.find_in_page_rounded, 'label': 'Lost & Found'},
  ];

  final List<Map<String, String>> _searchHistory = [
    {'from': 'Rajiv Chowk', 'to': 'Noida Sec 52'},
    {'from': 'Kashmere Gate', 'to': 'Hauz Khas'},
    {'from': 'Botanical Garden', 'to': 'Janakpuri West'},
    {'from': 'Chandni Chowk', 'to': 'MG Road'},
    {'from': 'Laxmi Nagar', 'to': 'Dwarka Sec 21'},
  ];

  @override
  void initState() {
    super.initState();
    _micGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1), 
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryController, curve: Curves.fastOutSlowIn));

    _entryController.forward();
    _startAutoSlide();
    
    // ✅ LOAD DATA ON START
    _metroService.loadAllData();
  }

  @override
  void dispose() {
    _micGlowController.dispose();
    _entryController.dispose(); 
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
        _pageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 800),
            curve: Curves.fastOutSlowIn
        );
      }
    });
  }

  void _stopAutoSlide() {
    _carouselTimer?.cancel();
  }

  void _handleMicTap(bool isFrom) {
    final micService = Provider.of<MicService>(context, listen: false);
    AppHaptics.mediumImpact(); // FEEL: Mic Toggle
    setState(() => _isMicActiveForFrom = isFrom);
    if (micService.isListening) {
      micService.stopListening();
    } else {
      micService.startListening();
    }
  }

  void _toggleHistoryPanel() {
    AppHaptics.lightImpact(); // FEEL: Panel Slide
    setState(() {
      _isHistoryVisible = !_isHistoryVisible;
    });
  }

  void _clearHistory() {
    AppHaptics.mediumImpact(); // FEEL: Delete Action
    setState(() {
      _searchHistory.clear();
    });
  }

  // ✅ Helper function to calculate and navigate to route
  Future<void> _calculateAndNavigateRoute() async {
    String rawFrom = _fromController.text.trim();
    String rawTo = _toController.text.trim();

    var fromStation = _metroService.getStationByName(rawFrom);
    var toStation = _metroService.getStationByName(rawTo);

    // Error Checks
    if (fromStation == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unknown station: '$rawFrom'"), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));
      return;
    }
    if (toStation == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Unknown station: '$rawTo'"), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));
      return;
    }
    if (rawFrom.toLowerCase() == rawTo.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Start and End stations cannot be the same!"), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
      return;
    }

    final result = _metroService.calculateRoute(fromStation.name, toStation.name);

    if (result != null) {
      Navigator.push(
        context, 
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => RouteScreen(routeData: result),
          transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No route found between these stations."), backgroundColor: Colors.orange));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final topPadding = MediaQuery.of(context).padding.top;
    final micService = Provider.of<MicService>(context);

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
          // Background Glow
          Positioned(
            top: -100, left: -50,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.15),
                    blurRadius: 150,
                    spreadRadius: 20,
                  )
                ]
              ),
            ),
          ),

          // 2. Main Content
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
                    _buildHeader(),
                    const SizedBox(height: 30),
                    
                    // 🔥 KEY UPDATE: LIVE LOADING INDICATOR 🔥
                    ValueListenableBuilder<bool>(
                      valueListenable: _metroService.isLoading,
                      builder: (context, isLoading, _) {
                        return ValueListenableBuilder<String>(
                          valueListenable: _metroService.loadingStatus,
                          builder: (context, status, _) {
                            if (isLoading) {
                              // Show Loading State
                              return Container(
                                height: 120,
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF151515),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      height: 20, 
                                      width: 20, 
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue)
                                    ),
                                    const SizedBox(height: 15),
                                    Text(
                                      status.isEmpty ? "Initializing..." : status, 
                                      style: const TextStyle(color: Colors.white70, fontSize: 13)
                                    ),
                                  ],
                                ),
                              );
                            }
                            // Data loaded? Show Search Box!
                            return _buildSearchBox(micService);
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 25),

                    // Auto Sliding Box
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
                              _buildCarouselSlide(title: "Smart Recharge", subtitle: "Top-up your Metro Card instantly", icon: Icons.credit_card_rounded, color: Colors.orangeAccent, bgGradient: [Colors.orange.withValues(alpha: 0.1), Colors.transparent]),
                              _buildCarouselSlide(title: "WhatsApp Ticket", subtitle: "Book QR tickets via Chat", icon: Icons.qr_code_rounded, color: Colors.greenAccent, bgGradient: [Colors.green.withValues(alpha: 0.1), Colors.transparent]),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(2, (index) => _buildDot(index))),

                    const SizedBox(height: 30),

                    // --- EXPANDABLE OTHER SERVICES ---
                    _buildExpandableServicesSection(),

                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
          ),

          // 3. History Panel Overlay
          if (_isHistoryVisible)
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleHistoryPanel, 
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
            ),

          // 4. Animated History Panel
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

  // --- WIDGETS ---

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
                      activeThumbColor: Colors.blue,
                      onChanged: (val) {
                        AppHaptics.lightImpact(); // FEEL: Toggle
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
            child: _searchHistory.isEmpty
                ? Center(child: Text("No recent searches", style: TextStyle(color: Colors.grey[600])))
                : ListView.builder(
                    itemCount: _searchHistory.length,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (ctx, index) {
                      final item = _searchHistory[index];
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
                            AppHaptics.mediumImpact(); // FEEL: Item Select
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

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              height: 48, width: 48,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.1), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
              child: const Icon(Icons.train_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Good Evening", style: TextStyle(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                const Text("Traveler", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        Row(
          children: [
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

  Widget _buildSearchBox(MicService micService) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildCompactInput('From Station', Icons.train_outlined, Colors.greenAccent, _fromController, isMicActive: micService.isListening && _isMicActiveForFrom, onMicTap: () => _handleMicTap(true))),
              const SizedBox(width: 10),
              
              // Station Explorer Button (Opens Popup)
              _buildSquareButton(
                icon: Icons.grid_view_rounded,
                color: Colors.white.withValues(alpha: 0.1), 
                iconColor: Colors.white70, 
                onTap: () { 
                  AppHaptics.mediumImpact(); 

                  // ✅ FIX: Wait for data before opening
                  if (_metroService.allStations.isEmpty) {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Loading stations... Please wait."), backgroundColor: Colors.orange));
                     return;
                  }
                  
                  showGeneralDialog(
                    context: context,
                    barrierDismissible: true,
                    barrierLabel: "Select Station",
                    pageBuilder: (context, _, __) => StationListSheet(
                      onSelectionComplete: (from, to) {
                        setState(() {
                          _fromController.text = from;
                          _toController.text = to;
                        });
                      },
                    ),
                  );
                }
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildCompactInput('To Station', Icons.location_on_outlined, Colors.redAccent, _toController, isMicActive: micService.isListening && !_isMicActiveForFrom, onMicTap: () => _handleMicTap(false))),
              const SizedBox(width: 10),
              
              // ✅ GO BUTTON LOGIC
              _buildSquareButton(
                icon: Icons.arrow_forward_rounded, 
                color: Colors.blue.shade600, 
                iconColor: Colors.white, 
                onTap: () async { 
                  AppHaptics.heavyImpact(); 
                  _calculateAndNavigateRoute();
                }
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableServicesSection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () {
                AppHaptics.lightImpact(); // FEEL: Expand
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
            
            GestureDetector(
              onTap: () {
                AppHaptics.mediumImpact(); // FEEL: Map Open
                debugPrint("Digital Map Tapped");
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.map_rounded, color: Colors.blue, size: 16),
                    const SizedBox(width: 6),
                    Text("Digital Map", style: TextStyle(color: Colors.blue.shade200, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),

        AnimatedCrossFade(
          firstChild: _buildServiceGrid(limit: 4),
          secondChild: _buildServiceGrid(limit: _allServices.length),
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
          final service = _allServices[index];
          return _buildServiceIcon(service['icon'], service['label']);
        },
      ),
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
    return AnimatedContainer(duration: const Duration(milliseconds: 300), margin: const EdgeInsets.symmetric(horizontal: 4), height: 6, width: isActive ? 20 : 6, decoration: BoxDecoration(color: isActive ? Colors.blue : Colors.grey.shade800, borderRadius: BorderRadius.circular(3)));
  }

  Widget _buildServiceIcon(IconData icon, String label) {
    return GestureDetector(
      onTap: () { AppHaptics.lightImpact(); }, // FEEL: Service Tap
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

  Widget _buildCompactInput(String hint, IconData icon, Color iconColor, TextEditingController controller, {required bool isMicActive, required VoidCallback onMicTap}) {
    return Container(
      height: 50,
      decoration: BoxDecoration(color: const Color(0xFF0F0F0F), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          
          Expanded(
            child: Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<String>.empty();
                }
                // ✅ Using new Model-based list
                return _metroService.allStations
                    .where((Station s) => s.name.toLowerCase().contains(textEditingValue.text.toLowerCase()))
                    .map((Station s) => s.name); // Mapping Object -> Name String
              },
              onSelected: (String selection) {
                // ✅ FIX: Update controller text
                controller.text = selection;
                AppHaptics.lightImpact();
                
                // ✅ FIX: Clear focus to hide keyboard and close suggestions
                FocusScope.of(context).unfocus();
                
                // ✅ FIX: Auto-trigger route calculation if both fields are filled
                if (_fromController.text.isNotEmpty && _toController.text.isNotEmpty) {
                  // Small delay to ensure text is updated
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) {
                      _calculateAndNavigateRoute();
                    }
                  });
                }
              },
              fieldViewBuilder: (context, fieldController, fieldFocusNode, onFieldSubmitted) {
                if (controller.text != fieldController.text) {
                  fieldController.text = controller.text;
                }
                fieldController.addListener(() {
                   controller.text = fieldController.text;
                });

                return TextField(
                  controller: fieldController,
                  focusNode: fieldFocusNode,
                  onTap: () { AppHaptics.lightImpact(); },
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  cursorColor: Colors.blue,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero
                  ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                // ✅ Autocomplete widget handles overlay positioning automatically
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: Colors.transparent,
                    elevation: 8, // ✅ Ensure proper z-index
                    child: Container(
                      width: 250, 
                      margin: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 10))],
                      ),
                      constraints: const BoxConstraints(maxHeight: 250), 
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            separatorBuilder: (context, index) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
                            itemBuilder: (BuildContext context, int index) {
                              final String option = options.elementAt(index);
                              return ListTile(
                                dense: true,
                                title: Text(option, style: const TextStyle(color: Colors.white, fontSize: 14)),
                                leading: const Icon(Icons.train, color: Colors.grey, size: 18),
                                onTap: () {
                                  // ✅ FIX: Call onSelected which will trigger the onSelected callback above
                                  onSelected(option);
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          GestureDetector(onTap: onMicTap, child: AnimatedBuilder(animation: _micGlowController, builder: (context, child) { return Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.all(6), decoration: BoxDecoration(shape: BoxShape.circle, color: isMicActive ? Colors.blue.withValues(alpha: 0.2) : Colors.transparent, boxShadow: isMicActive ? [BoxShadow(color: Colors.blue.withValues(alpha: 0.5), blurRadius: 5 + (_micGlowController.value * 8))] : []), child: Icon(Icons.mic_rounded, color: isMicActive ? Colors.blue : Colors.grey.shade600, size: 20)); })),
        ],
      ),
    );
  }

  Widget _buildSquareButton({required IconData icon, required Color color, required Color iconColor, required VoidCallback onTap}) {
    return GestureDetector(onTap: onTap, child: Container(height: 50, width: 50, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: iconColor, size: 24)));
  }
}