import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/utils/app_haptics.dart'; // Ensure this is imported

import 'package:ridel/features/commute/shared/models/route_models.dart';
import 'package:ridel/features/commute/metro/services/metro_service.dart';
import 'package:ridel/features/commute/bus/services/bus_service.dart'; 
import 'package:ridel/features/commute/metro/map/metro_map_screen.dart';
import 'package:ridel/features/commute/shared/widgets/route_header.dart';
import 'package:ridel/features/commute/shared/widgets/journey_timeline_card.dart';
import 'package:ridel/features/commute/metro/widgets/facilities_card.dart';
import 'package:ridel/features/commute/metro/widgets/route_map_card.dart';

class RouteResultScreen extends StatefulWidget {
  final String fromStation;
  final String toStation;
  final RouteResult? routeData;
  final bool isMetro; 

  const RouteResultScreen({
    super.key,
    required this.fromStation,
    required this.toStation,
    this.routeData,
    this.isMetro = true,
  });

  @override
  State<RouteResultScreen> createState() => _RouteResultScreenState();
}

class _RouteResultScreenState extends State<RouteResultScreen> {
  late RouteResult? _currentRouteData;
  late String _currentFrom;
  late String _currentTo;
  
  // 🔥 NEW STATE: Preference Tracker
  BusRoutePreference _busPreference = BusRoutePreference.fastest;
  
  late ScrollController _scrollController;
  bool _isScrolled = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentFrom = widget.fromStation;
    _currentTo = widget.toStation;
    _currentRouteData = widget.routeData;

    _scrollController = ScrollController();
    _scrollController.addListener(() {
      if (_scrollController.offset > 20 && !_isScrolled) {
        setState(() => _isScrolled = true);
      } else if (_scrollController.offset <= 20 && _isScrolled) {
        setState(() => _isScrolled = false);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // 🔥 NEW FUNCTION: Handle Toggle Switch
  Future<void> _onPreferenceChanged(BusRoutePreference newPref) async {
    if (_busPreference == newPref) return; // No change
    
    setState(() {
      _busPreference = newPref;
      _isLoading = true;
    });
    
    // Re-calculate route with new preference
    try {
      final newResult = await BusService().findBusRoute(
        _currentFrom, 
        _currentTo, 
        preference: _busPreference
      );
      
      if (mounted) {
        setState(() {
          _currentRouteData = newResult;
          _isLoading = false;
        });
        
        if (newResult == null) {
          ToastService.showError(context, "No route found for this preference.");
        } else {
          AppHaptics.selectionClick();
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSwap(String newFrom, String newTo) async {
    setState(() {
      _isLoading = true;
      _currentFrom = newFrom;
      _currentTo = newTo;
    });

    try {
      RouteResult? newResult;
      
      if (widget.isMetro) {
        newResult = await MetroService().findBestRoute(newFrom, newTo);
      } else {
        // 🔥 Updated to use preference
        newResult = await BusService().findBusRoute(newFrom, newTo, preference: _busPreference);
      }

      if (mounted) {
        setState(() {
          _currentRouteData = newResult;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ... (Map Bottom Sheet logic same as before) ...
  void _showMapBottomSheet() {
    if (!widget.isMetro) {
      ToastService.showInfo(context, "Live Bus Tracking Coming Soon!");
      return;
    }
    final activeLines = _currentRouteData?.path
            .map((step) => step.lineCode)
            .whereType<String>()
            .toSet()
            .toList() ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.95,
        decoration: const BoxDecoration(
          color: Color(0xFF0B0E17),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Colors.white10, width: 1)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Stack(
            children: [
              MetroMapScreen(highlightedLineIds: activeLines),
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [const Color(0xFF0B0E17).withOpacity(0.9), const Color(0xFF0B0E17).withOpacity(0.0)],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Network Map", style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E17),
      body: Stack(
        children: [
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  SizedBox(height: topPadding + 100),

                  GestureDetector(
                    onTap: _showMapBottomSheet,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: widget.isMetro 
                        ? RouteMapCard(routeResult: _currentRouteData) 
                        : _buildBusMapPlaceholder(),
                    ),
                  ),
                  
                  const SizedBox(height: 25),

                  // 🔥 NEW: Preference Toggle (Only visible for Bus)
                  if (!widget.isMetro) 
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
                      child: _buildPreferenceToggle(),
                    ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _isLoading
                        ? _buildLoadingState()
                        : _currentRouteData != null
                            ? JourneyTimelineCard(routeData: _currentRouteData!)
                            : _buildErrorState(),
                  ),
                  const SizedBox(height: 20),

                  if (!_isLoading && _currentRouteData != null && widget.isMetro)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: FacilitiesCard(routeData: _currentRouteData!),
                    ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),

          Positioned(
            top: 0, left: 0, right: 0,
            child: RouteHeader(
              fromStation: _currentFrom,
              toStation: _currentTo,
              topPadding: topPadding,
              isScrolled: _isScrolled,
              onBack: () => Navigator.pop(context),
              onSwap: _handleSwap,
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 WIDGET DESIGN: Similar to Station Facilities Toggle
  Widget _buildPreferenceToggle() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF151515), // Dark card background
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / 2;
          return Stack(
            children: [
              // Animated Background Pill
              AnimatedAlign(
                alignment: _busPreference == BusRoutePreference.fastest 
                    ? Alignment.centerLeft 
                    : Alignment.centerRight,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: Container(
                  width: width,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F0A), // Bus Orange
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFFF9F0A).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))
                    ]
                  ),
                ),
              ),
              // Text Labels
              Row(
                children: [
                  _buildToggleItem("Time Saver ⚡", BusRoutePreference.fastest),
                  _buildToggleItem("Less Interchange 🔄", BusRoutePreference.lessInterchange),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToggleItem(String text, BusRoutePreference value) {
    final isSelected = _busPreference == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onPreferenceChanged(value),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: GoogleFonts.inter(
              color: isSelected ? Colors.black : Colors.white54, // Black text on Orange, White on Dark
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
            ),
            child: Text(text),
          ),
        ),
      ),
    );
  }

  Widget _buildBusMapPlaceholder() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        image: const DecorationImage(
          image: NetworkImage("https://docs.mapbox.com/help/img/screenshots/static-images-api.png"),
          fit: BoxFit.cover,
          opacity: 0.4
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined, color: Color(0xFFFF9F0A)),
              const SizedBox(width: 10),
              Text("View Route on Map", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Center(
        child: CircularProgressIndicator(
          color: widget.isMetro ? const Color(0xFF00E5FF) : const Color(0xFFFF9F0A)
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          SizedBox(width: 12),
          Flexible(child: Text("Route unavailable. Try changing preferences or checking network.", style: TextStyle(color: Colors.white70))),
        ],
      ),
    );
  }
}