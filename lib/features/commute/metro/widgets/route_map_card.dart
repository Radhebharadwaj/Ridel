import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/features/commute/metro/map/metro_data_provider.dart';
import 'package:ridel/features/commute/metro/map/metro_painter.dart';
import 'package:ridel/features/commute/metro/map/map_models.dart'; 
import 'package:ridel/features/commute/shared/models/route_models.dart';
// 🔥 YE NAYA IMPORT HAI ASLI MAP SCREEN KE LIYE!
import 'package:ridel/features/commute/metro/map/metro_map_screen.dart';

class RouteMapCard extends StatelessWidget {
  final RouteResult? routeResult;
  final MapStation? targetNearestStation; 

  const RouteMapCard({
    super.key, 
    this.routeResult,
    this.targetNearestStation, 
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AppHaptics.mediumImpact();
        
        // 🔥 ASLI 11K MAP YAHAN SE KHULEGA FULL SCREEN MEIN!
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MetroMapScreen(
              // Agar user ne koi route search kiya hai, to sirf wo line map me highlight hogi
              highlightedLineIds: routeResult?.pathLineIds ?? [],
            ),
          ),
        );
      },
      child: Container(
        height: 180,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Consumer<MetroDataProvider>(
          builder: (context, provider, child) {
            if (provider.mapData == null) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
            }

            // 🚀 Active lines aur stations nikalna
            List<String> activeLines = routeResult?.pathLineIds ?? [];
            List<MapStation> routeStations = [];
            
            if (routeResult != null) {
              final routeStationIds = routeResult!.path.map((s) => s.id).toSet();
              routeStations = provider.mapData!.stations.where((s) => routeStationIds.contains(s.id)).toList();
            }

            return Stack(
              children: [
                // Dim Background
                Container(color: const Color(0xFF0B0E17).withOpacity(0.95)),

                // Map Painter (Scaled down for card view preview)
                Positioned.fill(
                  child: Transform.scale(
                    scale: 0.2, // Card ke hisab se preview ko chota kiya hai
                    child: CustomPaint(
                      painter: MetroMapPainter(
                        allLines: provider.mapData!.lines,
                        activeLineIds: activeLines,
                        routeStations: targetNearestStation != null ? [targetNearestStation!] : routeStations,
                      ),
                    ),
                  ),
                ),

                // Overlay Text/Icon
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(targetNearestStation != null ? Icons.location_on_rounded : Icons.map_rounded, color: const Color(0xFF00E5FF)),
                          const SizedBox(width: 10),
                          Text(targetNearestStation != null ? "View Nearest Station" : "View Route Map", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}