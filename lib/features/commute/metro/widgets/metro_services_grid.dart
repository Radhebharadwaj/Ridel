// lib/features/commute/metro/widgets/metro_services_grid.dart

import 'package:flutter/material.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/commute/shared/widgets/expandable_services_grid.dart';

// 🚀 SAARI FILES YAHAN CONNECT HAIN
import '../map/metro_map_screen.dart';
import 'first_last_train_sheet.dart';
import 'nearest_station_sheet.dart'; // 🚀 FIX: Ye import miss ho gaya tha!
import '../../shared/widgets/smart_ticketing_overlay.dart';

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
              title: "Train Timings",
              showBackButton: true,
              customHeader: false,
              child: const FirstLastTrainSheet(),
            );
            break;
        }
      },
    );
  }
}
