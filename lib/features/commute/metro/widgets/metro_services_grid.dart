// lib/features/commute/metro/widgets/metro_services_grid.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/commute/shared/widgets/expandable_services_grid.dart';

// 🚀 SAARI FILES YAHAN CONNECT HAIN
import '../map/metro_map_screen.dart';
import 'nearest_station_sheet.dart';
import '../../shared/widgets/smart_ticketing_overlay.dart';
import '../../shared/widgets/station_selector_sheet.dart';
import '../../shared/services/database_helper.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart';
import 'package:ridel/core/utils/app_shadows.dart';

class MetroServicesGrid extends StatelessWidget {
  final Function(String)? onTicketingIntent;
  const MetroServicesGrid({super.key, this.onTicketingIntent});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > 600;

    // 🌟 DATA: Yahan sirf Metro ke cards define ho rahe hain (ORDER UPDATED!)
    final List<Map<String, dynamic>> metroServices = [
      if (!isDesktop)
        {
          'id': 'network_map',
          'name': 'Network Map',
          'description': 'Route lines & interactive map',
          'icon': Icons.map_rounded,
        },
      // 🚀 UPDATED: Tickets & Fares is now the 2nd Card
      {
        'id': 'check_fares',
        'name': 'Tickets & Fares',
        'description': 'Book tickets & calculate cost',
        'icon': Icons.local_activity_rounded,
      },
      // 🚀 UPDATED: Nearest Station is now the 3rd Card
      {
        'id': 'nearest_station',
        'name': 'Nearest Station',
        'description': 'Find closest metro stop',
        'icon': Icons.my_location_rounded,
      },
      {
        'id': 'train_timings',
        'name': 'First/Last Train',
        'description': 'Station timings & schedule',
        'icon': Icons.train_rounded,
      },
    ];

    // 🚀 MASTER WIDGET CALL
    return ExpandableServicesGrid(
      title: "METRO SERVICES",
      services: metroServices,
      isDark: isDark,
      onServiceTap: (String id) {
        // 🌟 ACTION LOGIC: Kis card pe click karne se kya khulega
        switch (id) {
          case 'network_map':
            AppHaptics.lightImpact();
            RidelSheet.show(
              context,
              title: "Network Map",
              showBackButton: true,
              showFullScreenButton: true,
              sheetColor: const Color(0xFF0B0E17),
              child: const MetroMapScreen(showAppBar: false),
            );
            break;

          case 'check_fares': // Action mapping waise hi rahegi
            AppHaptics.lightImpact();
            showSmartTicketingOverlay(context).then((result) {
              if (result != null) {
                if (result == 'whatsapp' || result == 'fare_calc') {
                  onTicketingIntent?.call(result);
                }
              }
            });
            break;

          case 'nearest_station':
            AppHaptics.lightImpact();
            RidelSheet.show(
              context,
              title: "Nearest Stations",
              showCloseButton: true,
              showFullScreenButton: false,
              child: const NearestStationSheetContent(isBus: false),
            );
            break;

          case 'train_timings':
            AppHaptics.lightImpact();
            RidelSheet.show(
              context,
              title: "Select Station",
              showBackButton: true,
              customHeader: true,
              child: StationSelectorSheet(
                isSelectingSource: false,
                isBusMode: false,
                onStationSelected: (station, _) {
                  _showTimingsModal(context, station);
                },
              ),
            );
            break;
        }
      },
    );
  }

  void _showTimingsModal(BuildContext context, Map<String, dynamic> station) async {
    String firstTrain = '05:30 AM';
    String lastTrain = '11:15 PM';
    String frequency = '3-5 mins peak, 8-10 mins off-peak';
    
    // Bind directly to the model property injected from the StationSelectionSheet
    List<Color> lineColors = station['line_color'] != null 
        ? [station['line_color'] as Color] 
        : [Colors.grey];

    try {
      final db = await DatabaseHelper.instance.database;
      final stopId = station['stop_id'];

      // Extract all potential interchange lines
      final routesQuery = await db.rawQuery('''
        SELECT DISTINCT r.route_id, r.route_short_name, r.route_long_name, r.route_color
        FROM graph_edges g
        JOIN routes r ON g.route_id = r.route_id
        WHERE (g.from_node_id = ? OR g.to_node_id = ?) AND r.transport_type = 0
      ''', [stopId, stopId]);

      if (routesQuery.isNotEmpty) {
        lineColors = routesQuery.map((route) {
          var colorHex = route['route_color']?.toString() ?? '808080';
          colorHex = colorHex.replaceAll('#', '');
          try {
            return Color(int.parse('0xFF$colorHex'));
          } catch (e) {
            return station['line_color'] as Color? ?? Colors.grey;
          }
        }).toList();
      }
    } catch (e) {
      debugPrint("Timings Fetch Error: $e");
    }

    if (!context.mounted) return;

    String toTitleCase(String text) {
      if (text.isEmpty) return text;
      return text.toLowerCase().split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1);
      }).join(' ');
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final isLightMode = Theme.of(context).brightness == Brightness.light;
        final isDark = !isLightMode;
        final modalBgColor = isLightMode ? Colors.white : const Color(0xFF0B0E17);
        final borderColor = isLightMode ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.08);
        final primaryText = isLightMode ? Colors.black87 : Colors.white;
        final secondaryText = isLightMode ? Colors.black54 : Colors.white54;

        return Container(
          decoration: BoxDecoration(
            color: modalBgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag Handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: primaryText.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: lineColors.map((color) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        toTitleCase(station['stop_name'] ?? 'Unknown Station'),
                        style: GoogleFonts.inter(
                          color: primaryText,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                // Timing Rows — Profile-Matched Card
                Material(
                  color: isDark ? const Color(0xFF1C1F26) : Colors.white,
                  borderRadius: BorderRadius.circular(24.0),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.10)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                      boxShadow: AppShadows.buttonSoft,
                    ),
                    child: Column(
                      children: [
                        _buildTimingRow(
                          leading: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), shape: BoxShape.circle),
                            child: const Center(child: Icon(CupertinoIcons.sunrise_fill, color: Colors.orange, size: 18)),
                          ),
                          title: "First Train",
                          value: firstTrain,
                          mainTextColor: primaryText,
                          subTextColor: secondaryText,
                        ),
                        Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
                        _buildTimingRow(
                          leading: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: Colors.indigo.withValues(alpha: 0.15), shape: BoxShape.circle),
                            child: const Center(child: Icon(CupertinoIcons.moon_stars_fill, color: Colors.indigoAccent, size: 18)),
                          ),
                          title: "Last Train",
                          value: lastTrain,
                          mainTextColor: primaryText,
                          subTextColor: secondaryText,
                        ),
                        Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
                        _buildTimingRow(
                          leading: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: isLightMode ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: Center(child: Icon(CupertinoIcons.timer, color: isLightMode ? Colors.black54 : Colors.white70, size: 18)),
                          ),
                          title: "Frequency",
                          value: frequency,
                          mainTextColor: primaryText,
                          subTextColor: secondaryText,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Premium Done Button (from CommuteSearchCard)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: RidelLiquidButton(
                    enableStretch: true,
                    glassTint: const Color(0xFFFFFFFF).withValues(alpha: 0.75),
                    onTap: () {
                      AppHaptics.lightImpact();
                      Navigator.of(context).pop();
                    },
                    child: Center(
                      child: Text(
                        'Done',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: const Color(0xFF121419),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildTimingRow({
    required Widget leading,
    required String title,
    required String value,
    required Color mainTextColor,
    required Color subTextColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: subTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    color: mainTextColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
}
}
