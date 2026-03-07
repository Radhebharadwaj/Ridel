import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/commute/shared/models/route_models.dart';
import 'package:ridel/features/commute/metro/services/metro_service.dart';

class FacilitiesCard extends StatefulWidget {
  final RouteResult routeData;
  const FacilitiesCard({super.key, required this.routeData});

  @override
  State<FacilitiesCard> createState() => _FacilitiesCardState();
}

class _FacilitiesCardState extends State<FacilitiesCard> {
  bool _isMainCardExpanded = false;
  int _selectedStationIndex = 0; // 0 = Start, 1 = End
  int _expandedCategoryIndex = -1;

  // Cache for loaded data
  Map<String, dynamic>? _startStationData;
  Map<String, dynamic>? _endStationData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStationData();
  }

  Future<void> _loadStationData() async {
    final startId = widget.routeData.path.first.id;
    final endId = widget.routeData.path.last.id;

    final startData = await MetroService().getStationFullDetails(startId);
    final endData = await MetroService().getStationFullDetails(endId);

    if (mounted) {
      setState(() {
        _startStationData = startData;
        _endStationData = endData;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine active data based on selection
    final activeData = _selectedStationIndex == 0 ? _startStationData : _endStationData;
    
    // Names for Toggle
    final startName = widget.routeData.path.first.name;
    final endName = widget.routeData.path.last.name;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: _isMainCardExpanded 
          ? const EdgeInsets.all(20) 
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(_isMainCardExpanded ? 32 : 100),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          // --- HEADER ---
          GestureDetector(
            onTap: () {
              AppHaptics.lightImpact();
              setState(() => _isMainCardExpanded = !_isMainCardExpanded);
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Station Facilities", style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                Icon(_isMainCardExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.6), size: 24),
              ],
            ),
          ),

          // --- EXPANDED CONTENT ---
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _isLoading 
              ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.white24))
              : Column(
                  children: [
                    const SizedBox(height: 20),
                    
                    // 1. STATION TOGGLE (Shows Actual Names)
                    _buildStationToggle(startName, endName),
                    
                    const SizedBox(height: 20),
                    
                    // 2. DATA CATEGORIES
                    if (activeData != null) ...[
                      _buildCategoryCapsule(0, Icons.door_sliding_rounded, "Gates & Directions", 
                        _buildGatesList(activeData['gates'])),
                      const SizedBox(height: 10),
                      
                      _buildCategoryCapsule(1, Icons.layers_rounded, "Platforms", 
                        _buildPlatformsList(activeData['platforms'])),
                      const SizedBox(height: 10),
                      
                      _buildCategoryCapsule(2, Icons.elevator_rounded, "Lifts & Amenities", 
                        _buildFacilitiesList(activeData['facilities'], ['LIFT', 'TOILET', 'ATM', 'WATER'])),
                      const SizedBox(height: 10),
                      
                      _buildCategoryCapsule(3, Icons.local_parking_rounded, "Parking Capacity", 
                        _buildParkingInfo(activeData['parking'])),
                      const SizedBox(height: 10),
                      
                      _buildCategoryCapsule(4, Icons.storefront_rounded, "Nearby Places", 
                         _buildFacilitiesList(activeData['facilities'], ['MALLS_&_MARKET', 'TOURIST_SPOT', 'OTHER_PUBLIC_SERVICES'])),
                    ]
                  ],
                ),
            crossFadeState: _isMainCardExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.fastOutSlowIn,
          ),
        ],
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildStationToggle(String startName, String endName) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(100),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / 2;
          return Stack(
            children: [
              AnimatedAlign(
                alignment: _selectedStationIndex == 0 ? Alignment.centerLeft : Alignment.centerRight,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: Container(
                  width: width,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF006C75),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              Row(
                children: [
                  _buildToggleItem(startName, 0),
                  _buildToggleItem(endName, 1),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToggleItem(String text, int index) {
    final isSelected = _selectedStationIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          AppHaptics.lightImpact();
          setState(() {
            _selectedStationIndex = index;
            _expandedCategoryIndex = -1;
          });
        },
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: isSelected ? Colors.white : Colors.white54,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCapsule(int index, IconData icon, String title, Widget content) {
    final isExpanded = _expandedCategoryIndex == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(isExpanded ? 24 : 100),
        border: Border.all(color: isExpanded ? Colors.white.withOpacity(0.1) : Colors.transparent),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              AppHaptics.selectionClick();
              setState(() => _expandedCategoryIndex = isExpanded ? -1 : index);
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, color: isExpanded ? const Color(0xFF00E5FF) : Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: GoogleFonts.inter(color: isExpanded ? Colors.white : Colors.white70, fontSize: 14, fontWeight: isExpanded ? FontWeight.w600 : FontWeight.w500)),
                  ),
                  Icon(isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: Colors.white38, size: 20),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            child: Container(
              width: double.infinity,
              padding: isExpanded ? const EdgeInsets.fromLTRB(20, 0, 20, 20) : EdgeInsets.zero,
              child: isExpanded ? content : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  // --- DATA BUILDERS (MAPPING DATABASE TO UI) ---

  Widget _buildGatesList(List<Map<String, dynamic>>? gates) {
    if (gates == null || gates.isEmpty) return _emptyState("No gate info available");
    
    return Column(
      children: [
        const Divider(color: Colors.white10),
        const SizedBox(height: 10),
        ...gates.map((g) {
          final isOpen = (g['is_open'] == 1);
          return _infoRow(
            g['gate_name'] ?? "Gate", 
            g['location_desc'] ?? "", 
            isOpen
          );
        }).toList(),
      ],
    );
  }

  Widget _buildPlatformsList(List<Map<String, dynamic>>? platforms) {
    if (platforms == null || platforms.isEmpty) return _emptyState("No platform details");

    return Column(
      children: [
        const Divider(color: Colors.white10),
        const SizedBox(height: 10),
        ...platforms.map((p) => _simpleRow(
          p['platform_name'] ?? "Platform", 
          "Towards ${p['towards_station_code']}"
        )).toList(),
      ],
    );
  }

  Widget _buildFacilitiesList(List<Map<String, dynamic>>? facilities, List<String> codes) {
    if (facilities == null) return _emptyState("Not available");
    
    // Filter the facilities list based on the requested codes
    final filtered = facilities.where((f) => codes.contains(f['facility_code'])).toList();
    
    if (filtered.isEmpty) return _emptyState("None found");

    return Column(
      children: [
        const Divider(color: Colors.white10),
        const SizedBox(height: 10),
        ...filtered.map((f) => _simpleRow(
          _formatFacilityCode(f['facility_code']), 
          f['location_desc'] ?? ""
        )).toList(),
      ],
    );
  }

  Widget _buildParkingInfo(Map<String, dynamic>? parking) {
    if (parking == null) return _emptyState("No Parking Available");

    return Column(
      children: [
        const Divider(color: Colors.white10),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _parkingIcon(Icons.directions_car_rounded, parking['car_capacity']?.toString() ?? "0"),
            _parkingIcon(Icons.two_wheeler_rounded, parking['bike_capacity']?.toString() ?? "0"),
            _parkingIcon(Icons.pedal_bike_rounded, parking['cycle_capacity']?.toString() ?? "0"),
          ],
        ),
      ],
    );
  }

  // --- HELPER ROWS ---

  Widget _infoRow(String label, String sub, bool isOpen) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 8, height: 8, 
            decoration: BoxDecoration(
              color: isOpen ? const Color(0xFF25D366) : Colors.redAccent, 
              shape: BoxShape.circle
            )
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty)
                  Text(sub, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          if(isOpen) 
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: const Text("Open", style: TextStyle(color: Color(0xFF25D366), fontSize: 10)),
            )
        ],
      ),
    );
  }

  Widget _simpleRow(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.circle, color: Colors.white24, size: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty)
                  Text(sub, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _parkingIcon(IconData icon, String count) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 24),
        const SizedBox(height: 4),
        Text(count, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
      ],
    );
  }

  Widget _emptyState(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Center(child: Text(text, style: const TextStyle(color: Colors.white30, fontSize: 12, fontStyle: FontStyle.italic))),
    );
  }

  String _formatFacilityCode(String code) {
    return code.replaceAll('_', ' ').toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }
}