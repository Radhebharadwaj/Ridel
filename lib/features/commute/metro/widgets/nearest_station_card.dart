import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart'; 
import 'package:ridel/core/widgets/ridel_glass_modal.dart';
import 'package:ridel/core/utils/app_haptics.dart';

import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/features/commute/metro/map/metro_data_provider.dart';
import 'package:ridel/core/services/notification_service.dart'; 
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/providers/app_navigation_provider.dart'; 

class NearestStationCard extends StatefulWidget {
  const NearestStationCard({super.key});

  @override
  State<NearestStationCard> createState() => _NearestStationCardState();
}

class _NearestStationCardState extends State<NearestStationCard> {
  bool _isPressed = false;

  void _openNearestStationsModal(BuildContext context) {
    AppHaptics.lightImpact(); 
    RidelGlassModal.show(
      context,
      child: const _NearestStationsModalContent(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final cardColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03); 
    const accentColor = Color(0xFF00E5FF); 

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        _openNearestStationsModal(context);
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0, // 🚀 Same iOS bouncy scale effect
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32), // 🚀 Capsule shape
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 90,
              height: 120, 
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), 
              decoration: BoxDecoration(
                color: cardColor, 
                borderRadius: BorderRadius.circular(32), 
                border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12), 
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.15), 
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.my_location_rounded, color: accentColor, size: 24), 
                  ),
                  const SizedBox(height: 12), 
                  Text(
                    "Nearest\nStation",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 11, 
                      fontWeight: FontWeight.w600,
                      color: textColor, 
                      height: 1.2
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================================
// 🚀 THE OFFLINE CALCULATION ENGINE
// ==========================================================
class _NearestStationsModalContent extends StatefulWidget {
  const _NearestStationsModalContent();

  @override
  State<_NearestStationsModalContent> createState() => _NearestStationsModalContentState();
}

class _NearestStationsModalContentState extends State<_NearestStationsModalContent> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _topStations = [];

  @override
  void initState() {
    super.initState();
    _calculateNearestStationsOffline();
  }

  Future<void> _calculateNearestStationsOffline() async {
    try {
      final locService = Provider.of<GlobalLocationService>(context, listen: false);
      if (!locService.hasValidLocation) {
        await locService.initializeEcoLocation();
      }

      final pos = locService.currentPosition;
      if (pos == null) {
        NotificationService.showError("Unable to get location. Please check GPS permissions.");
        if (mounted) Navigator.pop(context);
        return;
      }

      final metroProvider = Provider.of<MetroDataProvider>(context, listen: false);
      final mapData = metroProvider.mapData;
      
      if (mapData == null || mapData.stations.isEmpty) {
        NotificationService.showInfo("Offline database is still loading...");
        if (mounted) Navigator.pop(context);
        return;
      }

      List<Map<String, dynamic>> calculatedList = [];

      for (var station in mapData.stations) {
        double distanceInMeters = Geolocator.distanceBetween(
          pos.latitude, 
          pos.longitude,
          station.lat, 
          station.lng  
        );

        calculatedList.add({
          'station': station,
          'distance': distanceInMeters,
        });
      }

      calculatedList.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
      
      if (mounted) {
        setState(() {
          _topStations = calculatedList.take(3).toList();
          _isLoading = false;
        });
      }

    } catch (e) {
      debugPrint("Nearest Station Error: $e");
      NotificationService.showError("Something went wrong!");
      if (mounted) Navigator.pop(context);
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return "${meters.toInt()}m";
    } else {
      return "${(meters / 1000).toStringAsFixed(1)}km";
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            "Nearest Stations",
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            "Based on your current coordinates",
            style: GoogleFonts.inter(
              fontSize: 13,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ),
        const SizedBox(height: 24),

        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
          )
        else if (_topStations.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text("No stations found nearby.", style: GoogleFonts.inter(color: Colors.grey)),
            ),
          )
        else
          ...List.generate(_topStations.length, (index) {
            final data = _topStations[index];
            final station = data['station'];
            final distanceStr = _formatDistance(data['distance']);
            final bool isClosest = index == 0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _buildStationOption(
                context, 
                station, 
                distanceStr, 
                "Delhi Metro", 
                isClosest
              ),
            );
          }),

        const SizedBox(height: 12),
        
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? Colors.white : Colors.black,
              foregroundColor: isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15)),
          ),
        )
      ],
    );
  }

  Widget _buildStationOption(BuildContext context, dynamic station, String distance, String lines, bool isClosest) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accentColor = Color(0xFF00E5FF);
    
    return Material(
      color: Colors.transparent,
      child: InkWell( 
        onTap: () async {
          AppHaptics.selectionClick();
          
          // 🚀 THE FIX: Context close (pop) hone se PEHLE hi saari dependencies fetch karlo
          // Warna kabhi-kabhi 'context' lost ho jata tha jis wajah se error aati thi aur functions fail hote the
          final mapProvider = Provider.of<MapProvider>(context, listen: false);
          final locService = Provider.of<GlobalLocationService>(context, listen: false);
          final navProvider = Provider.of<AppNavigationProvider>(context, listen: false);
          
          Navigator.pop(context); // Ab context properly pop ho jayega
          
          final pos = locService.currentPosition;
          if (pos != null) {
            final currentLoc = LatLng(pos.latitude, pos.longitude);
            final stationLatLng = LatLng(station.lat, station.lng); 
            
            await mapProvider.startStationNavigation(currentLoc, stationLatLng, station.name);
          }

          navProvider.setTab(3); // Tab switch function
        },
        borderRadius: BorderRadius.circular(20), // List items ko bhi rounded (capsule shape) diya
        splashColor: accentColor.withOpacity(0.2),
        highlightColor: accentColor.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isClosest 
                ? accentColor.withOpacity(isDark ? 0.15 : 0.1)
                : (isDark ? const Color(0xFF222222) : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isClosest ? accentColor : Colors.transparent,
              width: isClosest ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.train_rounded, 
                color: isClosest ? accentColor : (isDark ? Colors.white54 : Colors.black54),
                size: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          station.name,
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isClosest) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle_rounded, color: accentColor, size: 14),
                        ]
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lines,
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                distance,
                style: GoogleFonts.inter(
                  color: isClosest ? accentColor : (isDark ? Colors.white54 : Colors.black54),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}