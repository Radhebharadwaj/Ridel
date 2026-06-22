import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/features/commute/shared/widgets/station_selector_sheet.dart';
import 'package:ridel/features/commute/metro/services/metro_service.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';
import 'package:ridel/core/widgets/branded_loader.dart';

class FareCalculatorSheet extends StatefulWidget {
  const FareCalculatorSheet({super.key});

  @override
  State<FareCalculatorSheet> createState() => _FareCalculatorSheetState();
}

class _FareCalculatorSheetState extends State<FareCalculatorSheet> {
  String? fromStation;
  String? toStation;

  bool _isLoading = false;
  int? _normalFare;
  int? _specialFare;
  double? _routeDistance;
  int? _timeMinutes;

  Future<void> _calculateFare() async {
    if (fromStation == null || toStation == null) return;

    setState(() {
      _isLoading = true;
      _normalFare = null;
    });
    AppHaptics.lightImpact();

    try {
      final route =
          await MetroService().findBestRoute(fromStation!, toStation!);

      if (route != null && route.path.isNotEmpty) {
        _routeDistance = route.totalDistance;
        _timeMinutes = route
            .totalTimeMin; // 🚀 Yahan model ka correct variable use kiya hai

        final fareConfigs = await DatabaseHelper.instance.getFareConfig(0);

        for (var config in fareConfigs) {
          double minKm = config['min_km'] is num ? (config['min_km'] as num).toDouble() : double.tryParse(config['min_km']?.toString() ?? '0.0') ?? 0.0;
          double maxKm = config['max_km'] is num ? (config['max_km'] as num).toDouble() : double.tryParse(config['max_km']?.toString() ?? '0.0') ?? 0.0;

          if (_routeDistance! >= minKm && _routeDistance! <= maxKm) {
            _normalFare = config['price_normal'] is int ? config['price_normal'] : int.tryParse(config['price_normal']?.toString() ?? '0') ?? 0;
            _specialFare = config['price_special'] is int ? config['price_special'] : int.tryParse(config['price_special']?.toString() ?? '0') ?? 0;
            break;
          }
        }

        if (_normalFare == null && fareConfigs.isNotEmpty) {
          _normalFare = fareConfigs.last['price_normal'] is int ? fareConfigs.last['price_normal'] : int.tryParse(fareConfigs.last['price_normal']?.toString() ?? '0') ?? 0;
          _specialFare = fareConfigs.last['price_special'] is int ? fareConfigs.last['price_special'] : int.tryParse(fareConfigs.last['price_special']?.toString() ?? '0') ?? 0;
        }

        AppHaptics.success();
      }
    } catch (e) {
      debugPrint("Fare Calc Error: $e");
    }

    setState(() => _isLoading = false);
  }

  void _swapStations() {
    if (fromStation != null || toStation != null) {
      AppHaptics.selectionClick();
      setState(() {
        final temp = fromStation;
        fromStation = toStation;
        toStation = temp;
      });
      _calculateFare();
    }
  }

  Future<void> _openStationSheet(bool isFrom) async {
    AppHaptics.lightImpact();
    await RidelSheet.show(
      context,
      title: isFrom ? "Select From Station" : "Select To Station",
      showBackButton: true, // Universal back button
      child: StationSelectorSheet(
        isSelectingSource: isFrom,
        isBusMode: false,
        currentFromStation: fromStation != null
            ? {'stop_name': fromStation, 'stop_id': ''}
            : null,
        currentToStation:
            toStation != null ? {'stop_name': toStation, 'stop_id': ''} : null,
        onStationSelected: (station, isSource) {
          setState(() {
            if (isSource) {
              fromStation = station['stop_name'];
            } else {
              toStation = station['stop_name'];
            }
          });
          if (fromStation != null && toStation != null) {
            _calculateFare();
          }
        },
      ),
    );
  }

  Widget _buildSelectionCapsule(
      {required IconData icon,
      required Color iconColor,
      required String title,
      required bool isPlaceholder,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 55,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  color: isPlaceholder ? Colors.grey.shade500 : Colors.white,
                  fontWeight:
                      isPlaceholder ? FontWeight.normal : FontWeight.w600,
                  fontSize: 15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!isPlaceholder)
              GestureDetector(
                onTap: () => setState(() {
                  title == fromStation ? fromStation = null : toStation = null;
                  _normalFare = null;
                }),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white38, size: 20),
              )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 TOP PADDING: RidelSheet ke header (85px) ko clear karne ke liye 95px diya hai
    return Padding(
      padding: const EdgeInsets.only(top: 95, left: 20, right: 20, bottom: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🚀 STATION SELECTION CAPSULES STACK
          SizedBox(
            height: 120,
            child: Stack(
              children: [
                Column(
                  children: [
                    _buildSelectionCapsule(
                      icon: Icons.my_location_rounded,
                      iconColor: const Color(0xFF00E5FF),
                      title: fromStation ?? "Select Source Station",
                      isPlaceholder: fromStation == null,
                      onTap: () => _openStationSheet(true),
                    ),
                    const Spacer(),
                    _buildSelectionCapsule(
                      icon: Icons.location_on_rounded,
                      iconColor: const Color(0xFFFF3B30),
                      title: toStation ?? "Select Destination Station",
                      isPlaceholder: toStation == null,
                      onTap: () => _openStationSheet(false),
                    ),
                  ],
                ),
                Positioned(
                  right: 40,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _swapStations,
                      child: Container(
                        height: 32,
                        width: 32,
                        decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 8)
                            ]),
                        child: const Icon(Icons.swap_vert_rounded,
                            size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),

          // 🚀 FARE TICKET RESULT
          AnimatedSize(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            child: Container(
              margin: const EdgeInsets.only(top: 24),
              child: _isLoading
                  ? const SizedBox(
                      height: 100,
                      child: Center(
                          child: BrandedLoader(isFullScreen: false)))
                  : (_normalFare != null
                      ? Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                              color:
                                  const Color(0xFF151515), // Deep premium black
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: const Color(0xFF00E5FF)
                                      .withValues(alpha: 0.3),
                                  width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                    color: const Color(0xFF00E5FF)
                                        .withValues(alpha: 0.05),
                                    blurRadius: 20,
                                    spreadRadius: 5)
                              ]),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text("Standard Fare",
                                          style: TextStyle(
                                              color: Colors.white60,
                                              fontSize: 13,
                                              letterSpacing: 0.5)),
                                      const SizedBox(height: 4),
                                      Text("₹$_normalFare",
                                          style: GoogleFonts.inter(
                                              color: const Color(0xFF00E5FF),
                                              fontSize: 42,
                                              fontWeight: FontWeight.w900)),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.05),
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    child: Column(
                                      children: [
                                        const Icon(Icons.timer_outlined,
                                            color: Colors.white70, size: 22),
                                        const SizedBox(height: 6),
                                        Text("~$_timeMinutes min",
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14)),
                                      ],
                                    ),
                                  )
                                ],
                              ),
                              if (_specialFare != null) ...[
                                const SizedBox(height: 20),
                                const Divider(color: Colors.white10, height: 1),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Sunday / National Holiday",
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 13)),
                                    Text("₹$_specialFare",
                                        style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                )
                              ]
                            ],
                          ),
                        )
                      : const SizedBox()),
            ),
          )
        ],
      ),
    );
  }
}
