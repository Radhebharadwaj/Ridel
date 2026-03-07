import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart'; 
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/services/universal_mic_button.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';

class StationSelectorSheet extends StatefulWidget {
  final Function(Map<String, dynamic> station, bool isSource) onStationSelected;
  final Map<String, dynamic>? currentFromStation;
  final Map<String, dynamic>? currentToStation;
  final bool isSelectingSource;
  final bool isBusMode;

  const StationSelectorSheet({
    super.key, 
    required this.onStationSelected,
    this.currentFromStation,
    this.currentToStation,
    this.isSelectingSource = true,
    this.isBusMode = false,
  });

  @override
  State<StationSelectorSheet> createState() => _StationSelectorSheetState();
}

class _StationSelectorSheetState extends State<StationSelectorSheet> {
  late Future<List<Map<String, dynamic>>> _dataFuture;
  
  // Metro Variables
  List<String>? _selectedLineIds; 
  Color? _selectedLineColor; 
  
  // Bus & Common Variables
  List<Map<String, dynamic>> _stations = [];
  List<Map<String, dynamic>> _nearbyStops = [];
  bool _isLoadingStations = false;
  late bool _isCurrentlySelectingSource;
  
  // 🔥 NEW STATE: For floating bottom toggle
  bool _showNearbyStops = true; 

  String get _locationTerm => widget.isBusMode ? "Stop" : "Station";

  @override
  void initState() {
    super.initState();
    _isCurrentlySelectingSource = widget.isSelectingSource;
    _loadData();
    
    if (widget.isBusMode) {
      _fetchNearbyStops();
    }
  }

  Future<void> _fetchNearbyStops() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition();
        final allStops = await DatabaseHelper().getStationsByMode(1); // 1 = Bus
        
        final nearby = allStops.where((s) {
          double dist = Geolocator.distanceBetween(
            position.latitude, position.longitude, 
            (s['lat'] as num).toDouble(), (s['lon'] as num).toDouble()
          );
          return dist < 2000; // Stops within 2km
        }).toList();

        nearby.sort((a, b) {
          double distA = Geolocator.distanceBetween(position.latitude, position.longitude, (a['lat'] as num).toDouble(), (a['lon'] as num).toDouble());
          double distB = Geolocator.distanceBetween(position.latitude, position.longitude, (b['lat'] as num).toDouble(), (b['lon'] as num).toDouble());
          return distA.compareTo(distB);
        });

        if (mounted) {
          setState(() {
            _nearbyStops = nearby.take(10).toList();
          });
        }
      }
    } catch (e) {
      debugPrint("Location Error: $e");
    }
  }

  Future<void> _handleVoiceSearch(String query) async {
    if (query.isEmpty) return;
    
    final allStations = await DatabaseHelper().getAllStations();
    final lowerQuery = query.toLowerCase();
    
    try {
      final match = allStations.firstWhere((s) => 
        s['stop_name'].toString().toLowerCase().contains(lowerQuery)
      );
      _onStationTap(match);
      ToastService.showSuccess(context, "Selected: ${match['stop_name']}");
    } catch (e) {
      ToastService.showError(context, "$_locationTerm not found: $query");
    }
  }

  void _loadData() {
    if (widget.isBusMode) {
      _dataFuture = DatabaseHelper().getStationsByMode(1); 
    } else {
      _dataFuture = DatabaseHelper().getAllLines();
    }
  }

  void _onLineSelected(List<String> lineIds, Color lineColor) async {
    AppHaptics.selectionClick();
    setState(() {
      _selectedLineIds = lineIds;
      _selectedLineColor = lineColor;
      _isLoadingStations = true; 
      _stations = [];
    }); 
    
    if (!widget.isBusMode) {
      final stations = await DatabaseHelper().getStationsByLineIds(lineIds);
      if (mounted) {
        setState(() {
          _stations = stations;
          _isLoadingStations = false;
        });
      }
    }
  }

  void _onStationTap(Map<String, dynamic> station) {
    AppHaptics.heavyImpact();

    final otherStation = _isCurrentlySelectingSource ? widget.currentToStation : widget.currentFromStation;
    if (otherStation != null && otherStation['stop_name'] == station['stop_name']) {
      ToastService.showInfo(context, "Source & Destination cannot be same");
      return;
    }

    widget.onStationSelected(station, _isCurrentlySelectingSource);
    
    bool isDestinationEmpty = widget.currentToStation == null;

    if (_isCurrentlySelectingSource && isDestinationEmpty) {
      ToastService.showSuccess(context, "Now Select Destination");
      setState(() {
        _isCurrentlySelectingSource = false; 
        _selectedLineIds = null; 
        _stations = [];
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = const Color(0xFF121212); 
    final cardColor = const Color(0xFF1C1C1E); 
    final textColor = Colors.white;
    final subTextColor = Colors.grey;

    return Stack(
      children: [
        // 1. BASE LAYER: Scrollable Content
        Positioned.fill(
          child: Container(
            color: bgColor,
            child: widget.isBusMode 
              ? _buildBusContent(textColor, bgColor) // Changed to content only
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _selectedLineIds == null 
                    ? _buildLinesView(textColor, subTextColor, cardColor) 
                    : _buildStationsView(textColor, bgColor, _stations),
                ),
          ),
        ),
        
        // 2. HEADER FADE: Glassy effect at top
        Positioned(
          top: 0, left: 0, right: 0, height: 100,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [bgColor, bgColor.withOpacity(0.9), bgColor.withOpacity(0.0)],
                stops: const [0.0, 0.6, 1.0]
              ),
            ),
          ),
        ),
        
        // 3. ACTUAL HEADER
        Positioned(top: 0, left: 0, right: 0, child: _buildTransparentHeader(cardColor)),

        if (widget.isBusMode)
          Positioned(
            bottom: 0, left: 0, right: 0, height: 120, // Height thodi zyada rakhi hai toggle ko cover karne ke liye
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter, end: Alignment.topCenter, // Niche se upar
                  colors: [bgColor, bgColor.withOpacity(0.9), bgColor.withOpacity(0.0)],
                  stops: const [0.0, 0.5, 1.0]
                ),
              ),
            ),
          ),

        // 4. 🔥 FLOATING BOTTOM TOGGLE (Only for Bus Mode)
        if (widget.isBusMode)
          Positioned(
            bottom: 30, 
            left: 20, 
            right: 20,
            child: _buildFloatingToggle(), // Is widget ko abhi next step me update karenge
          )
      ],
    );
  }

  Widget _buildTransparentHeader(Color cardColor) {
    final String title = _isCurrentlySelectingSource 
        ? "Select Start $_locationTerm..." 
        : "Select Destination...";
        
    final IconData inputIcon = _isCurrentlySelectingSource ? Icons.my_location_rounded : Icons.location_on_rounded;
    final Color iconColor = _isCurrentlySelectingSource ? const Color(0xFF00E5FF) : Colors.redAccent;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      color: Colors.transparent, 
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (_selectedLineIds != null) {
                setState(() => _selectedLineIds = null);
              } else {
                Navigator.pop(context);
              }
            },
            child: Container(
              width: 45, height: 45,
              decoration: BoxDecoration(color: cardColor, shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.1))),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.only(left: 15, right: 5),
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(100), border: Border.all(color: Colors.white.withOpacity(0.1))),
              child: Row(
                children: [
                  Icon(inputIcon, size: 20, color: iconColor),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title, style: GoogleFonts.inter(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w500))),
                  UniversalMicButton(
                    isDark: isDark,
                    activeColor: iconColor,
                    onTextRecognized: (text) {
                       _handleVoiceSearch(text); 
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 NEW: Bus Content (Switches automatically based on bottom toggle)
  Widget _buildBusContent(Color textColor, Color bgColor) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _showNearbyStops
        ? (_nearbyStops.isEmpty 
            ? _buildEmptyLocationState()
            : _buildStationsView(textColor, bgColor, _nearbyStops, isNearby: true))
        : FutureBuilder<List<Map<String, dynamic>>>(
            future: _dataFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFFF9F0A)));
              return _buildStationsView(textColor, bgColor, snapshot.data!);
            },
          ),
    );
  }

  // Glassy Floating Bottom Toggle
  Widget _buildFloatingToggle() {
    return ClipRRect( 
      borderRadius: BorderRadius.circular(100),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), 
        child: Container(
          height: 54, 
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4), 
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
            ]
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth / 2;
              return Stack(
                children: [
                  // Animated Background Pill (Smoother transition)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 350), 
                    curve: Curves.fastOutSlowIn, 
                    left: _showNearbyStops ? 0 : width, 
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: width,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9F0A), // Bus Orange
                        borderRadius: BorderRadius.circular(100),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFFFF9F0A).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 2))
                        ]
                      ),
                    ),
                  ),
                  // Text Labels
                  Row(
                    children: [
                      _buildToggleItem("Nearby Stops 📍", true),
                      _buildToggleItem("All Stops 🚏", false),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildToggleItem(String text, bool isNearby) {
    final isSelected = _showNearbyStops == isNearby;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_showNearbyStops != isNearby) {
            AppHaptics.selectionClick();
            setState(() => _showNearbyStops = isNearby);
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: GoogleFonts.inter(
              color: isSelected ? Colors.black : Colors.white54, 
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
            ),
            child: Text(text),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyLocationState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_disabled_rounded, color: Colors.grey.shade800, size: 48),
          const SizedBox(height: 12),
          Text("No nearby stops found", style: GoogleFonts.inter(color: Colors.grey, fontSize: 14)),
          TextButton(
            onPressed: _fetchNearbyStops,
            child: Text("Retry Location", style: GoogleFonts.inter(color: const Color(0xFFFF9F0A))),
          )
        ],
      ),
    );
  }

  Widget _buildLinesView(Color textColor, Color subTextColor, Color cardColor) {
    if (widget.isBusMode) return const SizedBox();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: TextStyle(color: Colors.red)));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final lines = snapshot.data!;
        if (lines.isEmpty) return Center(child: Text("No lines found", style: TextStyle(color: textColor)));

        final Map<String, Map<String, dynamic>> groupedLines = {}; 
        final Map<String, List<String>> mergedIds = {}; 

        for (var line in lines) {
          String rawColor = line['route_color']?.toString() ?? "808080";
          rawColor = rawColor.replaceAll("#", ""); 
          
          if (!groupedLines.containsKey(rawColor)) {
            groupedLines[rawColor] = line;
            mergedIds[rawColor] = [];
          }
          mergedIds[rawColor]!.add(line['route_id'].toString());
        }
        final uniqueList = groupedLines.values.toList();

        return ListView.builder(
          key: const ValueKey("LinesView"), 
          // padding top 100 for header, no bottom padding needed here since it's just lines
          padding: const EdgeInsets.fromLTRB(20, 100, 20, 40), 
          itemCount: uniqueList.length,
          itemBuilder: (context, index) {
            final line = uniqueList[index];
            final isLast = index == uniqueList.length - 1;
            
            String colorHex = line['route_color']?.toString() ?? "808080";
            colorHex = colorHex.replaceAll("#", "");
            Color color;
            try { color = Color(int.parse("0xFF$colorHex")); } catch (e) { color = Colors.grey; }
            final colorKey = colorHex;
            
            String rawName = line['route_short_name'] ?? "Metro";
            String displayName;
            if (rawName.contains("RMGL")) displayName = "Rapid Line";
            else if (rawName.contains("FOB")) displayName = "Grey Line";
            else if (rawName.contains("Orange")) displayName = "Airport Line";
            else if (!rawName.toLowerCase().contains("line")) displayName = "$rawName Line";
            else displayName = rawName;

            return InkWell( 
              onTap: () => _onLineSelected(mergedIds[colorKey]!, color),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 30,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (!isLast)
                          Positioned(top: 25, bottom: -25, child: Container(width: 2, color: Colors.white12)),
                          Container(
                            width: 12, height: 12,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
                        child: Row(
                          children: [
                            Expanded(child: Text(displayName, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16, color: textColor))),
                            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white24),
                          ],
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
    );
  }

  Widget _buildStationsView(Color textColor, Color bgColor, List<Map<String, dynamic>> stations, {bool isNearby = false}) {
    if (_isLoadingStations) return Center(key: const ValueKey("Loader"), child: CircularProgressIndicator(color: _selectedLineColor ?? Colors.grey));
    
    if (stations.isEmpty) {
        return Center(child: Text("No stops found", style: GoogleFonts.inter(color: Colors.grey)));
    }
    
    final lineColor = _selectedLineColor ?? Colors.grey;
    
    return ListView.builder(
      key: const ValueKey("StationsList"),
      // 🔥 PADDING: Top 100 for Header, Bottom 100 for Floating Toggle
      padding: EdgeInsets.only(top: 100, bottom: 100, left: 20, right: 20),
      itemCount: stations.length,
      itemBuilder: (context, index) {
        final isLast = index == stations.length - 1;
        final station = stations[index];
        final otherStation = _isCurrentlySelectingSource ? widget.currentToStation : widget.currentFromStation;
        final bool isDisabled = otherStation != null && otherStation['stop_name'] == station['stop_name'];

        return InkWell(
          onTap: isDisabled ? null : () => _onStationTap(station),
          child: widget.isBusMode 
            ? _buildBusStopRow(station, isDisabled, textColor, isNearby)
            : _buildMetroStationRow(station, isDisabled, textColor, bgColor, lineColor, isLast),
        );
      },
    );
  }

  Widget _buildBusStopRow(Map<String, dynamic> station, bool isDisabled, Color textColor, bool isNearby) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: isNearby ? const Color(0xFFFF9F0A).withOpacity(0.1) : Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isNearby ? Icons.my_location_rounded : Icons.directions_bus_rounded,
              color: isNearby ? const Color(0xFFFF9F0A) : Colors.grey,
              size: 16
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              station['stop_name'], 
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600, 
                color: isDisabled ? Colors.grey.withOpacity(0.5) : textColor,
                fontSize: 15
              )
            ),
          ),
          if (isNearby)
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
               decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
               child: Text("NEARBY", style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFFF9F0A), fontWeight: FontWeight.bold)),
             )
        ],
      ),
    );
  }

  Widget _buildMetroStationRow(Map<String, dynamic> station, bool isDisabled, Color textColor, Color bgColor, Color lineColor, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!isLast)
                Positioned(top: 25, bottom: -25, child: Container(width: 2, color: Colors.white12)),
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    color: isDisabled ? Colors.grey : bgColor,
                    shape: BoxShape.circle, 
                    border: Border.all(color: isDisabled ? Colors.grey : lineColor, width: 2.5)
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
              child: Text(
                station['stop_name'], 
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600, 
                  color: isDisabled ? Colors.grey.withOpacity(0.5) : textColor,
                  fontSize: 15
                )
              ),
            ),
          ),
        ],
      ),
    );
  }
}