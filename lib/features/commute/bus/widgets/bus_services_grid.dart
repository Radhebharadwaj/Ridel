// lib/features/commute/bus/widgets/bus_services_grid.dart

import 'package:flutter/material.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/commute/shared/widgets/expandable_services_grid.dart';

// 🚀 REUSING METRO'S POWERFUL COMPONENTS
import '../../metro/widgets/nearest_station_sheet.dart';
import '../../shared/widgets/smart_ticketing_overlay.dart';

class BusServicesGrid extends StatelessWidget {
  // 🌟 Ye intent callback zaroori hai taaki home screen par card morph ho sake
  final Function(String)? onTicketingIntent;
  const BusServicesGrid({super.key, this.onTicketingIntent});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final List<Map<String, dynamic>> busServices = [
      {
        'id': 'check_fares',
        'name': 'Tickets & Passes',
        'description': 'Book via WhatsApp',
        'icon': Icons.local_activity_rounded,
      },
      {
        'id': 'nearest_station',
        'name': 'Nearest Stop',
        'description': 'Find closest bus stop',
        'icon': Icons.my_location_rounded,
      },
      // Agar future me aur cards add karne ho toh yahan add kar lena
      {
        'id': 'live_tracking',
        'name': 'Live Bus Tracking',
        'description': 'Real-time positions',
        'icon': Icons.directions_bus_rounded,
      },
      {
        'id': 'route_finder',
        'name': 'Route Directory',
        'description': 'All bus routes & stops',
        'icon': Icons.alt_route_rounded,
      },
    ];

    return ExpandableServicesGrid(
      title: "BUS SERVICES",
      services: busServices,
      isDark: isDark,
      onServiceTap: (String id) {
        switch (id) {
          case 'check_fares':
            AppHaptics.lightImpact();
            // 🚀 SAME METRO OVERLAY CALL (Intent pass karega parent ko)
            showSmartTicketingOverlay(context, isBus: true).then((result) {
              if (result != null) {
                if (result == 'whatsapp' ||
                    result == 'fare_calc' ||
                    result == 'paytm') {
                  onTicketingIntent?.call(result);
                }
              }
            });
            break;

          case 'nearest_station':
            AppHaptics.lightImpact();
            RidelSheet.show(
              context,
              title: "Nearest Bus Stops",
              showCloseButton: true,
              showFullScreenButton: false,
              // 🚀 MAGIC FIX: isBus ko true pass kiya! Ab ye bus stops dhoondhega.
              child: const NearestStationSheetContent(isBus: true),
            );
            break;

          case 'live_tracking':
            AppHaptics.lightImpact();
            // Future logic
            break;

          case 'route_finder':
            AppHaptics.lightImpact();
            // Future logic
            break;
        }
      },
    );
  }
}
