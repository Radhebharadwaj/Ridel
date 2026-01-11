import 'package:flutter/material.dart';
import 'dart:ui'; // Required for ImageFilter (Blur)
// IMPORT HAPTICS & MODELS
import '../../../core/utils/app_haptics.dart';
import '../models/metro_models.dart';
import '../services/metro_services.dart';

class RouteScreen extends StatefulWidget {
  final RouteResult routeData;

  const RouteScreen({
    super.key,
    required this.routeData,
  });

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> with TickerProviderStateMixin {
  // State to track which line segments are expanded
  final Set<int> _expandedSegments = {};

  // State for collapsible sections
  bool _isJourneyExpanded = true; // Default open
  bool _isStepsExpanded = false;  // Default closed
  bool _isFacilitiesExpanded = false; // Default closed (New Section)

  final MetroService _service = MetroService();
  
  // Scroll Controller for Auto-Scroll & Header Animation
  late ScrollController _scrollController;
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    
    // Listener to update Header UI based on scroll position
    _scrollController.addListener(() {
      if (_scrollController.offset > 50 && !_isScrolled) {
        setState(() => _isScrolled = true);
      } else if (_scrollController.offset <= 50 && _isScrolled) {
        setState(() => _isScrolled = false);
      }
    });

    // AUTOMATIC SCROLL ANIMATION
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            180.0, // Height of summary card roughly
            duration: const Duration(milliseconds: 1000),
            curve: Curves.fastOutSlowIn,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final data = widget.routeData;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Glow Background
          Positioned(
            top: -100, right: -50,
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

          // 2. Main Scrollable Content
          SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: topPadding + 80), 

                // Summary Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildCompactRouteCard(data),
                ),
                
                const SizedBox(height: 25),

                // Map Card (Size Increased)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildMapCard(context),
                ),

                const SizedBox(height: 30),

                // --- 1. JOURNEY OVERVIEW ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildSectionHeader(
                        title: "Journey Overview",
                        isExpanded: _isJourneyExpanded,
                        onTap: () {
                          AppHaptics.lightImpact();
                          setState(() => _isJourneyExpanded = !_isJourneyExpanded);
                        }
                      ),
                      AnimatedCrossFade(
                        firstChild: const SizedBox(width: double.infinity), 
                        secondChild: Padding(
                          padding: const EdgeInsets.only(top: 15),
                          child: _buildSmartJourney(data),
                        ), 
                        crossFadeState: _isJourneyExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 300), 
                        sizeCurve: Curves.fastOutSlowIn,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // --- 2. SMART STEP GUIDANCE ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildSectionHeader(
                        title: "Step-by-Step Guidance",
                        isExpanded: _isStepsExpanded,
                        onTap: () {
                          AppHaptics.lightImpact();
                          setState(() => _isStepsExpanded = !_isStepsExpanded);
                        }
                      ),
                      AnimatedCrossFade(
                        firstChild: const SizedBox(width: double.infinity), 
                        secondChild: _buildSmartStepGuide(data),
                        crossFadeState: _isStepsExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 350), 
                        sizeCurve: Curves.fastOutSlowIn,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // --- 3. STATION FACILITIES (New) ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildSectionHeader(
                        title: "Station Facilities",
                        isExpanded: _isFacilitiesExpanded,
                        onTap: () {
                          AppHaptics.lightImpact();
                          setState(() => _isFacilitiesExpanded = !_isFacilitiesExpanded);
                        }
                      ),
                      AnimatedCrossFade(
                        firstChild: const SizedBox(width: double.infinity), 
                        secondChild: _buildFacilitiesSection(data),
                        crossFadeState: _isFacilitiesExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 350), 
                        sizeCurve: Curves.fastOutSlowIn,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 100),
              ],
            ),
          ),

          // 3. Header
          Positioned(
            top: 0, left: 0, right: 0,
            child: _buildAnimatedHeader(topPadding),
          ),
        ],
      ),
    );
  }

  // --- REUSABLE HEADER WIDGET (For Uniform Look) ---
  Widget _buildSectionHeader({required String title, required bool isExpanded, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque, // Ensures whole row is clickable
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1))
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title, 
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.3)
            ),
            AnimatedRotation(
              turns: isExpanded ? 0.0 : -0.25, // 0 = Up (Open), -0.25 = Right (Closed)
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_up_rounded, // Using Up arrow as base
                color: Colors.white.withValues(alpha: 0.6),
                size: 24
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- MAIN WIDGETS ---

  Widget _buildAnimatedHeader(double topPadding) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      height: _isScrolled ? topPadding + 60 : topPadding + 70,
      padding: EdgeInsets.only(top: topPadding, left: 20, right: 20, bottom: 10),
      decoration: BoxDecoration(
        color: _isScrolled ? Colors.transparent : const Color(0xFF151515).withValues(alpha: 0.95),
        border: _isScrolled ? null : Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () {
               AppHaptics.lightImpact(); 
               Navigator.pop(context);
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, 
                    color: _isScrolled ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05)
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _isScrolled ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: const Text("Route Details", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ),
          AnimatedOpacity(
            opacity: _isScrolled ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: _isScrolled,
              child: GestureDetector(
                onTap: () { AppHaptics.mediumImpact(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.grey.shade900, Colors.black],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)), 
                  ),
                  child: const Row(
                    children: [
                      Text("Pay Now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      SizedBox(width: 6),
                      Icon(Icons.payment, color: Colors.white70, size: 14)
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

  // ✅ UPDATED: Map Card Size (Height Increased)
  Widget _buildMapCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AppHaptics.mediumImpact(); 
        Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 500),
            reverseTransitionDuration: const Duration(milliseconds: 400),
            pageBuilder: (_, __, ___) => const FullScreenMap(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
      child: Hero(
        tag: 'mapHero', 
        child: Container(
          // ✨ CHANGED: Height increased from 130 to 240 for visibility
          height: 240, 
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            image: const DecorationImage(
              image: NetworkImage('https://api.mapbox.com/styles/v1/mapbox/dark-v10/static/77.2090,28.6139,11,0/600x300?access_token=YOUR_TOKEN'), 
              fit: BoxFit.cover,
              opacity: 0.7, 
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 15, offset: const Offset(0, 5))
            ]
          ),
          child: Stack(
            children: [
              // Center "Tap to view" hint
              Center(
                 child: Container(
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(
                     color: Colors.black.withValues(alpha: 0.4),
                     shape: BoxShape.circle,
                     border: Border.all(color: Colors.white24)
                   ),
                   child: const Icon(Icons.map_outlined, color: Colors.white, size: 24),
                 ),
              ),
              Positioned(
                bottom: 15, right: 15,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12)
                  ),
                  child: const Row(
                    children: [
                       Text("Tap to Expand", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                       SizedBox(width: 4),
                       Icon(Icons.open_in_full_rounded, color: Colors.white, size: 10),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // ✅ NEW: Facilities Section Logic
  Widget _buildFacilitiesSection(RouteResult data) {
    // NOTE: In real app, get facilities from data.path stations. 
    // Creating a mock list for UI demonstration.
    
    // Key stations to show (Start, End, Interchanges)
    List<Station> keyStations = [data.path.first];
    // Add interchanges
    for(int i=0; i<data.path.length-1; i++) {
        String line1 = _getCommonLine(data.path[i], data.path[i+1]);
        if (i+1 < data.path.length-1) {
            String line2 = _getCommonLine(data.path[i+1], data.path[i+2]);
            if(line1 != line2) keyStations.add(data.path[i+1]);
        }
    }
    keyStations.add(data.path.last);

    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: keyStations.map((station) {
           return Padding(
             padding: const EdgeInsets.only(bottom: 20),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(station.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                 const SizedBox(height: 8),
                 Wrap(
                   spacing: 8,
                   runSpacing: 8,
                   children: [
                     _buildFacilityChip(Icons.elevator_rounded, "Lift"),
                     _buildFacilityChip(Icons.accessible_rounded, "Ramp"),
                     _buildFacilityChip(Icons.local_parking_rounded, "Parking"),
                     if(station == data.path.first) _buildFacilityChip(Icons.wc_rounded, "Washroom"),
                     if(station == data.path.last) _buildFacilityChip(Icons.atm_rounded, "ATM"),
                   ],
                 )
               ],
             ),
           );
        }).toList(),
      ),
    );
  }

  Widget _buildFacilityChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1))
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.grey.shade400, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: Colors.grey.shade300, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSmartJourney(RouteResult data) {
    List<Widget> widgets = [];
    List<Station> path = data.path;

    if (path.isEmpty) return const SizedBox();

    String startLine = _getCommonLine(path[0], path[1]);
    MetroLine? startLineObj = _service.getLine(startLine);
    var startInfo = _service.getPlatformInfo(path[0], startLine, path[1].name);
    Color startColor = startLineObj?.color ?? Colors.green;

    widgets.add(_buildNode(
      title: path.first.name, 
      sub: "Start Journey", 
      color: startColor, 
      icon: Icons.trip_origin,
      trailingWidget: _buildPlatformBadge("Platform ${startInfo['number']}", startColor)
    ));

    int i = 0;
    int segmentIndex = 0; 

    while (i < path.length - 1) {
      String currentLineCode = _getCommonLine(path[i], path[i+1]);
      
      int j = i + 1;
      while (j < path.length - 1) {
        if (_getCommonLine(path[j], path[j+1]) != currentLineCode) break;
        j++;
      }
      
      int stops = j - i;
      MetroLine? line = _service.getLine(currentLineCode);
      Color lineColor = line?.color ?? Colors.grey;
      String lineName = line?.name ?? "Metro Line";
      var lineInfo = _service.getPlatformInfo(path[i], currentLineCode, path[i+1].name);

      List<Station> intermediateStations = [];
      if (stops > 1) {
        for (int k = i + 1; k < j; k++) {
          intermediateStations.add(path[k]);
        }
      }

      int currentSegmentId = segmentIndex++;
      bool isExpanded = _expandedSegments.contains(currentSegmentId);

      widgets.add(_buildLineCard(
        color: lineColor, 
        name: lineName, 
        stops: "$stops Stops", 
        time: "${stops * 2} Min",
        towards: "Towards ${lineInfo['towards']}",
        intermediateStations: intermediateStations,
        isExpanded: isExpanded,
        onTap: () {
          AppHaptics.lightImpact();
          setState(() {
            if (isExpanded) {
              _expandedSegments.remove(currentSegmentId);
            } else {
              _expandedSegments.add(currentSegmentId);
            }
          });
        }
      ));

      if (j < path.length - 1) {
        String nextLineCode = _getCommonLine(path[j], path[j+1]);
        MetroLine? nextLineObj = _service.getLine(nextLineCode);
        Color nextLineColor = nextLineObj?.color ?? Colors.orange;
        var nextPlatInfo = _service.getPlatformInfo(path[j], nextLineCode, path[j+1].name);

        widgets.add(_buildInterchangeNode(
          title: path[j].name, 
          platformWidget: _buildPlatformBadge("Platform ${nextPlatInfo['number']}", nextLineColor)
        ));
      } else {
        String exitGate = _service.getBestGate(path.last);
        widgets.add(_buildNode(
          title: path.last.name, 
          sub: "Destination • Use $exitGate", 
          color: Colors.redAccent, 
          icon: Icons.location_on,
          trailingWidget: null 
        ));
      }
      i = j;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(children: widgets),
    );
  }

  Widget _buildSmartStepGuide(RouteResult data) {
    List<Widget> stepWidgets = [];
    List<Station> path = data.path;
    int stepCount = 1;

    String startLine = _getCommonLine(path[0], path[1]);
    var startInfo = _service.getPlatformInfo(path[0], startLine, path[1].name);
    
    stepWidgets.add(_buildStepItem(
      "${stepCount++}", 
      "Start at ${path.first.name}", 
      "Go to Platform ${startInfo['number']}. Train is towards ${startInfo['towards']}.", 
      isFirst: true
    ));

    int i = 0;
    while (i < path.length - 1) {
      String currentLineCode = _getCommonLine(path[i], path[i+1]);
      int j = i + 1;
      while (j < path.length - 1) {
        if (_getCommonLine(path[j], path[j+1]) != currentLineCode) break;
        j++;
      }
      int stops = j - i;
      MetroLine? line = _service.getLine(currentLineCode);
      
      stepWidgets.add(_buildStepItem(
        "${stepCount++}", 
        "Ride $stops Stations (${line?.name})", 
        "Approx travel time ${stops*2} mins. Keep left."
      ));

      if (j < path.length - 1) {
        String nextLineCode = _getCommonLine(path[j], path[j+1]);
        MetroLine? nextLine = _service.getLine(nextLineCode);
        var platInfo = _service.getPlatformInfo(path[j], nextLineCode, path[j+1].name);

        stepWidgets.add(_buildStepItem(
          "${stepCount++}", 
          "Interchange at ${path[j].name}", 
          "Exit train. Follow ${nextLine?.name} marks. Go to Platform ${platInfo['number']}."
        ));
      }
      i = j;
    }

    String exitGate = _service.getBestGate(path.last);
    stepWidgets.add(_buildStepItem(
      "${stepCount++}", 
      "Exit at ${path.last.name}", 
      "Use $exitGate.", 
      isLast: true
    ));

    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(children: stepWidgets),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildPlatformBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15), 
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        text, 
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)
      ),
    );
  }

  Widget _buildNode({required String title, required String sub, required Color color, required IconData icon, Widget? trailingWidget}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28, height: 28, 
          margin: const EdgeInsets.only(top: 2), 
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Row(
                 children: [
                   Flexible(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                 ],
               ),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
            ],
          ),
        ),
        if (trailingWidget != null) ...[
          const SizedBox(width: 10),
          trailingWidget,
        ]
      ],
    );
  }

  Widget _buildInterchangeNode({required String title, required Widget platformWidget}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28, height: 28, 
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: const Icon(Icons.sync_alt, color: Colors.white, size: 14),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                 children: [
                   Flexible(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                 ],
               ),
              const SizedBox(height: 2),
              const Text("Interchange Station", style: TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        platformWidget, 
      ],
    );
  }

  Widget _buildLineCard({
    required Color color, 
    required String name, 
    required String stops, 
    required String time, 
    required String towards,
    required List<Station> intermediateStations,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    return IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Center(
              child: Container(
                width: 2,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border(left: BorderSide(color: color, width: 4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(towards, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.access_time_filled, color: Colors.white.withValues(alpha: 0.5), size: 12),
                            const SizedBox(width: 4),
                            Text("$time • $stops", style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: color, size: 16)
                          ],
                        )
                      ],
                    ),
                    if (isExpanded && intermediateStations.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Colors.white10),
                      const SizedBox(height: 8),
                      ...intermediateStations.map((s) => Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 8),
                        child: Row(
                          children: [
                            Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.6))),
                            const SizedBox(width: 10),
                            Text(s.name, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                          ],
                        ),
                      )),
                    ]
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(String step, String title, String desc, {bool isFirst = false, bool isLast = false}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 24, height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isFirst ? Colors.green : (isLast ? Colors.red : Colors.blueGrey.shade800),
                  shape: BoxShape.circle,
                ),
                child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              if (!isLast)
                Expanded(child: Container(width: 1, color: Colors.white.withValues(alpha: 0.1))),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(desc, style: TextStyle(color: Colors.grey.shade500, fontSize: 12, height: 1.3)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCompactRouteCard(RouteResult data) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF151515).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30, offset: const Offset(0, 10))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildStationName("From", data.path.first.name, CrossAxisAlignment.start)),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: Icon(Icons.arrow_forward_rounded, color: Colors.blue.shade400, size: 18)),
                      Expanded(child: _buildStationName("To", data.path.last.name, CrossAxisAlignment.end)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(height: 30, width: 1, color: Colors.white.withValues(alpha: 0.1)),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFF25D366).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3))),
                  child: Text("₹${data.fare}", style: const TextStyle(color: Color(0xFF25D366), fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMiniStat(Icons.schedule_rounded, "${data.totalTime} min", Colors.orange),
                _buildMiniStat(Icons.train_outlined, "${data.stationsCount} Stations", Colors.blue),
                _buildMiniStat(Icons.straighten_rounded, "${data.totalDistance} km", Colors.cyan),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStationName(String label, String name, CrossAxisAlignment alignment) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
      ],
    );
  }

  Widget _buildMiniStat(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  String _getCommonLine(Station a, Station b) {
    for (var l in a.lineCodes) {
      if (b.lineCodes.contains(l)) return l;
    }
    return a.lineCodes.isNotEmpty ? a.lineCodes.first : "LINE_1";
  }
}

class FullScreenMap extends StatelessWidget {
  const FullScreenMap({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Hero(
            tag: 'mapHero',
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage('https://api.mapbox.com/styles/v1/mapbox/dark-v10/static/77.2090,28.6139,11,0/600x300?access_token=YOUR_TOKEN'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            right: 20,
            child: GestureDetector(
              onTap: () {
                 AppHaptics.lightImpact(); 
                 Navigator.pop(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close_fullscreen_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text("Minimize", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}