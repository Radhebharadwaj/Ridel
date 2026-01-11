import 'package:flutter/material.dart';
import 'dart:ui';
import '../services/metro_services.dart';
import '../models/metro_models.dart'; // ✅ Import Models (Zaruri hai)
import '../../../core/utils/app_haptics.dart';

class StationListSheet extends StatefulWidget {
  final Function(String, String) onSelectionComplete;

  const StationListSheet({super.key, required this.onSelectionComplete});

  @override
  State<StationListSheet> createState() => _StationListSheetState();
}

class _StationListSheetState extends State<StationListSheet> {
  final MetroService _metroService = MetroService();
  final TextEditingController _searchController = TextEditingController();
  
  // ✅ FIX 1: Type change kiya String se Station Object par
  List<Station> _filteredStations = [];
  
  // Selection Logic
  String? _fromStation; // Start
  String? _selectedLineCode; // Filter Code

  // (UI Colors same rahenge)
  final List<Map<String, dynamic>> _lineData = [
    {'code': 'LINE_1', 'name': 'Red', 'color': const Color(0xFFFF1744)}, 
    {'code': 'LINE_2', 'name': 'Yellow', 'color': const Color(0xFFFFEA00)}, 
    {'code': 'LINE_3', 'name': 'Blue', 'color': const Color(0xFF2979FF)}, 
    {'code': 'LINE_4', 'name': 'Blue', 'color': const Color(0xFF2979FF)}, 
    {'code': 'LINE_5', 'name': 'Green', 'color': const Color(0xFF00E676)}, 
    {'code': 'LINE_6', 'name': 'Violet', 'color': const Color(0xFFD500F9)}, 
    {'code': 'LINE_7', 'name': 'Pink', 'color': const Color(0xFFFF4081)}, 
    {'code': 'LINE_8', 'name': 'Magenta', 'color': const Color(0xFFE040FB)}, 
    {'code': 'LINE_9', 'name': 'Grey', 'color': const Color(0xFFB0BEC5)}, 
    {'code': 'LINE_10', 'name': 'Airport', 'color': const Color(0xFFFF6D00)}, 
    {'code': 'LINE_11', 'name': 'Rapid', 'color': const Color(0xFF00E5FF)}, 
    {'code': 'LINE_12', 'name': 'Rapid', 'color': const Color(0xFF00E5FF)}, 
    {'code': 'RMGL', 'name': 'Rapid', 'color': const Color(0xFF00E5FF)}, 
  ];

  @override
  void initState() {
    super.initState();
    // ✅ Always fetch fresh list (Agar service load ho chuki hai)
    _filteredStations = List.from(_metroService.allStations); 
  }

  void _filterStations() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStations = _metroService.allStations.where((station) {
        // ✅ FIX 2: Station Object ke andar se 'name' nikala
        final nameMatches = station.name.toLowerCase().contains(query);
        
        bool lineMatches = true;
        if (_selectedLineCode != null) {
          // ✅ FIX 3: Station Object ke andar se 'lineCodes' nikala
          final stationLines = station.lineCodes;
          
          if (_selectedLineCode == 'LINE_3') {
             // Merge Blue Line logic
             lineMatches = stationLines.any((line) => line.contains('LINE_3') || line.contains('LINE_4'));
          } else if (_selectedLineCode == 'LINE_11') {
             // Merge Rapid Metro logic
             lineMatches = stationLines.any((line) => line.contains('LINE_11') || line.contains('RMGL'));
          } else {
             lineMatches = stationLines.any((line) => line.contains(_selectedLineCode!));
          }
        }
        return nameMatches && lineMatches;
      }).toList();
    });
  }

  void _handleStationTap(String stationName) {
    AppHaptics.mediumImpact();

    if (_fromStation == null) {
      // Step 1: From set karo
      setState(() {
        _fromStation = stationName;
        _searchController.clear();
        _filterStations();
      });
    } else {
      // Step 2: To set karo aur bhej do
      if (_fromStation == stationName) return; 
      widget.onSelectionComplete(_fromStation!, stationName);
      Navigator.pop(context);
    }
  }

  void _resetSelection() {
    AppHaptics.lightImpact();
    setState(() {
      _fromStation = null;
      _searchController.clear();
      _filterStations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, 
      body: Stack(
        children: [
          // 1. Blur Background
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: Colors.black.withValues(alpha: 0.6)),
            ),
          ),

          // 2. Centered Popup
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.92,
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F).withValues(alpha: 0.9), // Glassy Dark
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 50, spreadRadius: 5)
                ]
              ),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  
                  // --- HEADER ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Plan Journey", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                          ),
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // --- VISIBLE SELECTION STATUS (From -> To) ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        // FROM BOX
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            decoration: BoxDecoration(
                              color: _fromStation != null ? Colors.green.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _fromStation != null ? Colors.green.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1)
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.trip_origin, color: _fromStation != null ? Colors.green : Colors.grey, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _fromStation ?? "Start",
                                    style: TextStyle(
                                      color: _fromStation != null ? Colors.white : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14
                                    ),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_fromStation != null)
                                  GestureDetector(
                                    onTap: _resetSelection,
                                    child: const Icon(Icons.cancel, color: Colors.grey, size: 18),
                                  )
                              ],
                            ),
                          ),
                        ),
                        
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Icon(Icons.arrow_forward_rounded, color: Colors.grey, size: 18),
                        ),

                        // TO BOX
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            decoration: BoxDecoration(
                              color: _fromStation == null 
                                  ? Colors.white.withValues(alpha: 0.02) // Dimmed
                                  : Colors.blue.withValues(alpha: 0.15), // Active
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _fromStation == null 
                                  ? Colors.transparent 
                                  : Colors.blue.withValues(alpha: 0.5)
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.location_on, color: _fromStation == null ? Colors.grey.withValues(alpha: 0.3) : Colors.blue, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  "Destination",
                                  style: TextStyle(
                                    color: _fromStation == null ? Colors.grey.withValues(alpha: 0.3) : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 15),

                  // --- FILTERS (Gradient Glass) ---
                  SizedBox(
                    height: 50, 
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: _lineData.length,
                      itemBuilder: (context, index) {
                        if (index > 0 && _lineData[index]['name'] == _lineData[index-1]['name']) {
                          return const SizedBox.shrink(); 
                        }

                        final line = _lineData[index];
                        final isSelected = _selectedLineCode == line['code'];
                        
                        return GestureDetector(
                          onTap: () {
                             AppHaptics.lightImpact();
                             setState(() {
                               _selectedLineCode = isSelected ? null : line['code'];
                               _filterStations();
                             });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 10, top: 5, bottom: 5),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isSelected 
                                  ? [line['color'].withValues(alpha: 0.9), line['color'].withValues(alpha: 0.6)]
                                  : [line['color'].withValues(alpha: 0.25), line['color'].withValues(alpha: 0.05)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected 
                                  ? Colors.white.withValues(alpha: 0.8) 
                                  : line['color'].withValues(alpha: 0.3),
                                width: 1
                              ),
                              boxShadow: isSelected 
                                ? [BoxShadow(color: line['color'].withValues(alpha: 0.5), blurRadius: 15, offset: const Offset(0, 4))] 
                                : [],
                            ),
                            child: Text(
                              line['name'],
                              style: TextStyle(
                                color: isSelected 
                                  ? (line['name'] == 'Yellow' ? Colors.black : Colors.white) 
                                  : Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 0.5
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // --- SEARCH BAR ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05))
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => _filterStations(),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                          hintText: "Search station name...",
                          hintStyle: TextStyle(color: Colors.grey[700]),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14)
                        ),
                      ),
                    ),
                  ),

                  // --- STATION LIST ---
                  Expanded(
                    child: _filteredStations.isEmpty 
                    ? Center(child: Text("No station found", style: TextStyle(color: Colors.grey[700])))
                    : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      physics: const BouncingScrollPhysics(),
                      itemCount: _filteredStations.length,
                      itemBuilder: (context, index) {
                        final station = _filteredStations[index]; // ✅ Station Object
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: _fromStation == station.name ? Colors.green.withValues(alpha: 0.1) : Colors.transparent, // ✅ Used station.name
                            borderRadius: BorderRadius.circular(16),
                            border: _fromStation == station.name ? Border.all(color: Colors.green.withValues(alpha: 0.3)) : null,
                          ),
                          child: ListTile(
                            onTap: () => _handleStationTap(station.name), // ✅ Used station.name
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            title: Text(station.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                            trailing: _buildBigGlassBadges(station), // ✅ Passed full object
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ FIX 4: Updated to accept Station Object
  Widget _buildBigGlassBadges(Station station) {
    final lines = station.lineCodes; // ✅ Access directly
    Set<String> displayedLines = {}; 
    List<Widget> badges = [];

    for (var lineCode in lines) {
      String displayCode = lineCode;
      if (lineCode == 'LINE_3' || lineCode == 'LINE_4') displayCode = 'LINE_3'; 
      if (lineCode == 'LINE_11' || lineCode == 'LINE_12') displayCode = 'LINE_11'; 

      if (displayedLines.contains(displayCode)) continue;
      displayedLines.add(displayCode);

      var lineProp = _lineData.firstWhere(
        (e) => e['code'] == displayCode, 
        orElse: () => {'name': 'Line', 'color': Colors.grey}
      );

      badges.add(
        Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                lineProp['color'].withValues(alpha: 0.25),
                lineProp['color'].withValues(alpha: 0.05)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: lineProp['color'].withValues(alpha: 0.4), width: 1),
          ),
          child: Text(
            lineProp['name'], 
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9), 
              fontSize: 11, 
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3
            ),
          ),
        )
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: badges);
  }
}