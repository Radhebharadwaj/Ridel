// lib/features/commute/metro/widgets/facilities_card.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/commute/shared/models/route_models.dart';
import 'package:ridel/features/commute/metro/services/metro_service.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';

class FacilitiesSheetContent extends StatefulWidget {
  final RouteResult routeData;
  final String? initialStationId;

  const FacilitiesSheetContent({super.key, required this.routeData, this.initialStationId});

  @override
  State<FacilitiesSheetContent> createState() => _FacilitiesSheetContentState();
}

class _FacilitiesSheetContentState extends State<FacilitiesSheetContent>
    with TickerProviderStateMixin {
  late List<dynamic> _keyStations;
  late String _selectedStationId;
  final Map<String, Map<String, dynamic>> _stationDataCache = {};
  bool _isLoading = true;
  late AnimationController _pulseController;

  int _activeCategoryIndex = 0;
  final List<Map<String, dynamic>> _availableCategories = [];

  @override
  void initState() {
    super.initState();
    _extractKeyStations();
    
    if (widget.initialStationId != null) {
      _selectedStationId = widget.initialStationId!;
    }
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _loadDataForStation(_selectedStationId);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return word;
      return '${word[0].toUpperCase()}${word.substring(1)}';
    }).join(' ');
  }

  String _mapStationCodeToName(String code) {
    final map = {
      'KG': 'Kashmere Gate',
      'JAMD': 'Jama Masjid',
      'HUCC': 'Huda City Centre',
      'NDLS': 'New Delhi',
      'DWKA': 'Dwarka',
      'RITH': 'Rithala',
      'SVB': 'Samaypur Badli',
      'MJP': 'Majlis Park',
      'SPS': 'Shiv Vihar',
      'BOT': 'Botanical Garden',
      'NOCC': 'Noida City Centre',
      'KDB': 'Kirti Nagar',
      'VAL': 'Vaishali',
    };
    final upperCode = code.toUpperCase();
    if (map.containsKey(upperCode)) return map[upperCode]!;

    try {
      final node = widget.routeData.path.firstWhere((n) =>
          n.id.toUpperCase() == upperCode || n.name.toUpperCase() == upperCode);
      return _toTitleCase(node.name);
    } catch (_) {
      return _toTitleCase(code);
    }
  }

  void _extractKeyStations() {
    final path = widget.routeData.path;
    _keyStations = [];
    _keyStations.add({
      'id': path.first.id,
      'name': _toTitleCase(path.first.name),
      'type': 'Start'
    });
    if (path.length > 1) {
      _keyStations.add({
        'id': path.last.id,
        'name': _toTitleCase(path.last.name),
        'type': 'End'
      });
    }
    _selectedStationId = _keyStations.first['id'];
  }

  Future<void> _loadDataForStation(String stationId) async {
    setState(() => _isLoading = true);

    Map<String, dynamic> data;
    if (_stationDataCache.containsKey(stationId)) {
      data = _stationDataCache[stationId]!;
    } else {
      data = await MetroService().getStationFullDetails(stationId);
      _stationDataCache[stationId] = data;
    }

    if (mounted) {
      _buildAvailableCategories(data);
      setState(() {
        _selectedStationId = stationId;
        _isLoading = false;
        _activeCategoryIndex = 0;
      });
    }
  }

  void _buildAvailableCategories(Map<String, dynamic> data) {
    _availableCategories.clear();

    if (data['gates'] != null && (data['gates'] as List).isNotEmpty) {
      _availableCategories.add({'title': 'Gates & Exits', 'type': 'gates'});
    }
    if (data['platforms'] != null && (data['platforms'] as List).isNotEmpty) {
      _availableCategories.add({'title': 'Platforms', 'type': 'platforms'});
    }

    final facilities = data['facilities'] as List?;
    if (facilities != null) {
      final hasAmenities = facilities.any((f) =>
          ['LIFT', 'TOILET', 'ATM', 'WATER'].contains(f['facility_code']));
      if (hasAmenities) {
        _availableCategories.add({'title': 'Amenities', 'type': 'amenities'});
      }
    }

    if (data['parking'] != null) {
      _availableCategories.add({'title': 'Parking', 'type': 'parking'});
    }

    if (data['nearby_places'] != null &&
        (data['nearby_places'] as List).isNotEmpty) {
      _availableCategories.add({'title': 'Explore Nearby', 'type': 'explore'});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 85), // Header Overlap Fix - matched RidelSheet header height
          _buildCategoryTabs(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isLoading ? _buildPremiumSkeleton() : _buildContentList(),
          ),
        ],
      ),
    );
  }

  Widget _buildContentList() {
    if (_availableCategories.isEmpty) return _buildGlobalEmptyState();

    final activeType = _availableCategories[_activeCategoryIndex]['type'];
    final data = _stationDataCache[_selectedStationId]!;

    return Padding(
      key: ValueKey(activeType),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: _getCategoryWidget(activeType, data),
    );
  }

  Widget _getCategoryWidget(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'gates':
        return _buildGatesList(data['gates']);
      case 'platforms':
        return _buildPlatformsList(data['platforms']);
      case 'amenities':
        return _buildFacilitiesList(
            data['facilities'], ['LIFT', 'TOILET', 'ATM', 'WATER']);
      case 'parking':
        return _buildParkingInfo(data['parking']);
      case 'explore':
        return _buildExploreNearbyCards();
      default:
        return const SizedBox.shrink();
    }
  }


  Widget _buildCategoryTabs() {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              if (_availableCategories.isEmpty) return;
              AppHaptics.lightImpact();
              // Adjust dx based on the Container width, but since it takes full width of LayoutBuilder, dx is fine
              final tabWidth = constraints.maxWidth / _availableCategories.length;
              final index = (details.localPosition.dx / tabWidth).floor().clamp(0, _availableCategories.length - 1);
              setState(() => _activeCategoryIndex = index);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0), // Inflate hit area
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: isLightMode ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: _availableCategories.asMap().entries.map((entry) {
                    final index = entry.key;
                    final category = entry.value;
                    final isSelected = _activeCategoryIndex == index;

                    return Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? (isLightMode ? Colors.white : Colors.white.withValues(alpha: 0.15))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: isSelected && isLightMode
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
                              : null,
                        ),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          style: GoogleFonts.inter(
                            color: isSelected
                                ? (isLightMode ? Colors.black87 : Colors.white)
                                : (isLightMode ? Colors.black54 : Colors.white54),
                            fontSize: isSelected ? 14 : 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                          child: Text(
                            _toTitleCase(category['title']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildGatesList(List<dynamic>? gates) {
    if (gates == null) return const SizedBox.shrink();
    return Column(
      children: gates.map((g) {
        final isOpen = (g['is_open'] == 1);
        final gateName =
            g['gate_name'] != null ? g['gate_name'].toString() : "Gate";
        final locDesc =
            g['location_desc'] != null ? g['location_desc'].toString() : "";
        return _infoRow(_toTitleCase(gateName), _toTitleCase(locDesc), isOpen);
      }).toList(),
    );
  }

  Widget _buildPlatformsList(List<dynamic>? platforms) {
    if (platforms == null) return const SizedBox.shrink();
    return Column(
      children: platforms.map((p) {
        final platName = p['platform_name'] != null
            ? p['platform_name'].toString()
            : "Platform";
        final towards = p['towards_station_code'] != null
            ? _mapStationCodeToName(p['towards_station_code'].toString())
            : "Destination";
        return _simpleRow(_toTitleCase(platName), "Towards $towards");
      }).toList(),
    );
  }

  Widget _buildFacilitiesList(List<dynamic>? facilities, List<String> codes) {
    if (facilities == null) return const SizedBox.shrink();
    final filtered =
        facilities.where((f) => codes.contains(f['facility_code'])).toList();
    return Column(
      children: filtered.map((f) {
        final locDesc =
            f['location_desc'] != null ? f['location_desc'].toString() : "";
        return _simpleRow(
            _formatFacilityCode(f['facility_code']), _toTitleCase(locDesc));
      }).toList(),
    );
  }

  Widget _buildParkingInfo(Map<String, dynamic>? parking) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    if (parking == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: isLightMode ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _parkingIcon(Icons.directions_car_rounded,
              parking['car_capacity']?.toString() ?? "0"),
          Container(width: 1, height: 40, color: isLightMode ? Colors.black12 : Colors.white10),
          _parkingIcon(Icons.two_wheeler_rounded,
              parking['bike_capacity']?.toString() ?? "0"),
          Container(width: 1, height: 40, color: isLightMode ? Colors.black12 : Colors.white10),
          _parkingIcon(Icons.pedal_bike_rounded,
              parking['cycle_capacity']?.toString() ?? "0"),
        ],
      ),
    );
  }

  Widget _buildExploreNearbyCards() {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final data = _stationDataCache[_selectedStationId];
    if (data == null || data['nearby_places'] == null) {
      return const SizedBox.shrink();
    }

    final List<dynamic> nearbyPlaces = data['nearby_places'];
    if (nearbyPlaces.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 140,
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return const LinearGradient(
            colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
            stops: [0.0, 0.05, 0.95, 1.0],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
          clipBehavior: Clip.none,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: nearbyPlaces.length,
          separatorBuilder: (_, __) => const SizedBox(width: 16),
          itemBuilder: (context, index) {
            final place = nearbyPlaces[index] as Map<String, dynamic>;
            final name = place['name']?.toString() ?? 'Nearby Place';
            final type = place['type']?.toString() ?? 'Point of Interest';
            final rating = place['rating']?.toString() ?? '4.0';

            return RidelBounceButton(
              scaleFactor: 0.95,
              onTap: () => AppHaptics.lightImpact(),
              child: Container(
                width: 240,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isLightMode ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: Colors.purpleAccent.withValues(alpha: 0.1),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.place_rounded,
                              color: Colors.purpleAccent, size: 20),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: isLightMode ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(100)),
                          child: Row(
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                              const SizedBox(width: 4),
                              Text(rating,
                                  style: GoogleFonts.inter(
                                      color: isLightMode ? Colors.black87 : Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_toTitleCase(name),
                            style: GoogleFonts.inter(
                                color: isLightMode ? Colors.black87 : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(_toTitleCase(type),
                            style: GoogleFonts.inter(
                                color: isLightMode ? Colors.black54 : Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w400),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _infoRow(String label, String sub, bool isOpen) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              margin: const EdgeInsets.only(top: 6),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: isOpen ? const Color(0xFF25D366) : Colors.redAccent,
                  shape: BoxShape.circle)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.inter(
                        color: isLightMode ? Colors.black87 : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(sub,
                      style: GoogleFonts.inter(
                          color: isLightMode ? Colors.black54 : Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.4)),
                ]
              ],
            ),
          ),
          if (isOpen)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4)),
              child: Text("OPEN",
                  style: GoogleFonts.inter(
                      color: const Color(0xFF25D366),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5)),
            )
        ],
      ),
    );
  }

  Widget _simpleRow(String title, String sub) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isLightMode ? Colors.black26 : Colors.white24,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        color: isLightMode ? Colors.black87 : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(sub,
                      style: GoogleFonts.inter(
                          color: isLightMode ? Colors.black54 : Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.4)),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _parkingIcon(IconData icon, String count) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return Column(
      children: [
        Icon(icon, color: isLightMode ? Colors.black54 : Colors.white54, size: 26),
        const SizedBox(height: 10),
        Text(count,
            style: GoogleFonts.inter(
                color: isLightMode ? Colors.black87 : Colors.white, fontWeight: FontWeight.w800, fontSize: 16))
      ],
    );
  }

  Widget _buildPremiumSkeleton() {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Opacity(
            opacity: 0.5 + (_pulseController.value * 0.5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(
                    4,
                    (index) => Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Row(
                            children: [
                              Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: isLightMode ? Colors.black12 : Colors.white10,
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                        height: 14,
                                        width: 150,
                                        decoration: BoxDecoration(
                                            color: isLightMode ? Colors.black12 : Colors.white10,
                                            borderRadius:
                                                BorderRadius.circular(4))),
                                    const SizedBox(height: 8),
                                    Container(
                                        height: 10,
                                        width: 200,
                                        decoration: BoxDecoration(
                                            color: isLightMode ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.05),
                                            borderRadius:
                                                BorderRadius.circular(4))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )),
              ),
            ),
          );
        });
  }

  Widget _buildGlobalEmptyState() {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.blur_on_rounded,
              size: 48, color: isLightMode ? Colors.black26 : Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text("No Details Available",
              style: GoogleFonts.inter(
                  color: isLightMode ? Colors.black54 : Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _formatFacilityCode(String code) {
    return _toTitleCase(code.replaceAll('_', ' '));
  }
}
