import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/widgets/app_header.dart';
import 'package:ridel/features/commute/shared/widgets/commute_search_card.dart';
import 'package:ridel/features/commute/metro/widgets/metro_services_grid.dart';
import 'package:ridel/features/commute/bus/widgets/bus_services_grid.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/main.dart';

class CommuteScreen extends StatefulWidget {
  const CommuteScreen({super.key});

  @override
  State<CommuteScreen> createState() => _CommuteScreenState();
}

class _CommuteScreenState extends State<CommuteScreen> {
  final ValueNotifier<bool> _isSearchSheetOpen = ValueNotifier<bool>(true);
  String? activeTicketingMode;

  @override
  void dispose() {
    _isSearchSheetOpen.dispose();
    // Agar future me koi aur controllers add karein to yaha dispose zaroor karein
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth >= 800;

          if (isDesktop) {
            return _buildDesktopLayout(context, isDark);
          } else {
            return _buildMobileLayout(isDark);
          }
        },
      ),
    );
  }

  // ==========================================
  // 📱 MOBILE/TABLET LAYOUT
  // ==========================================
  Widget _buildMobileLayout(bool isDark) {
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(left: 20, right: 20, top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppHeader(showProfile: true),
                const SizedBox(height: 20),
                ValueListenableBuilder<int>(
                  valueListenable: globalTransportMode,
                  builder: (context, selectedMode, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CommuteSearchCard(
                          isDark: isDark,
                          selectedMode: selectedMode,
                          activeTicketingMode: activeTicketingMode,
                          onTicketingModeChanged: (mode) =>
                              setState(() => activeTicketingMode = mode),
                        ),
                        const SizedBox(height: 30),
                        GestureDetector(
                          onTap: () =>
                              setState(() => activeTicketingMode = null),
                          behavior: HitTestBehavior.opaque,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: activeTicketingMode != null ? 0.3 : 1.0,
                            child: IgnorePointer(
                              ignoring: activeTicketingMode != null,
                              child: selectedMode == 0
                                  ? MetroServicesGrid(
                                      onTicketingIntent: (intent) => setState(
                                          () => activeTicketingMode = intent))
                                  : BusServicesGrid(
                                      onTicketingIntent: (intent) => setState(
                                          () => activeTicketingMode = intent)),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 💻 DESKTOP LAYOUT
  // ==========================================
  Widget _buildDesktopLayout(BuildContext context, bool isDark) {
    return ValueListenableBuilder<bool>(
        valueListenable: globalSidebarOpen,
        builder: (context, isRailExpanded, child) {
          return Stack(
            children: [

              ValueListenableBuilder<bool>(
                  valueListenable: _isSearchSheetOpen,
                  builder: (context, isSheetOpen, child) {
                    double railWidth = isRailExpanded ? 220 : 80;
                    double sheetWidth = 380;
                    double gap = 16;
                    double minimizedOffset = sheetWidth - 40;

                    double leftPosition = railWidth + gap;
                    if (!isSheetOpen) {
                      leftPosition -= minimizedOffset;
                    }

                    return AnimatedPositioned(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      left: leftPosition,
                      top: 16,
                      bottom: 16,
                      width: sheetWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E2129).withValues(alpha: 0.98)
                              : Colors.white.withValues(alpha: 0.98),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.black.withValues(alpha: 0.05)),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20)
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: ValueListenableBuilder<int>(
                              valueListenable: globalTransportMode,
                              builder: (context, transportMode, child) {
                                return MapSearchSheetContent(
                                  isDark: isDark,
                                  transportMode: transportMode,
                                  isSheetOpen: isSheetOpen,
                                  activeTicketingMode: activeTicketingMode,
                                  onTicketingIntent: (intent) => setState(
                                      () => activeTicketingMode = intent),
                                  onTicketingModeChanged: (mode) => setState(
                                      () => activeTicketingMode = mode),
                                  onToggleOpen: () {
                                    AppHaptics.lightImpact();
                                    _isSearchSheetOpen.value =
                                        !_isSearchSheetOpen.value;
                                  },
                                );
                              }),
                        ),
                      ),
                    );
                  }),
            ],
          );
        });
  }
}

// ==============================================================
// 💎 THE FLOATING SEARCH SHEET CONTENT (FORM & ITINERARY)
// ==============================================================
class MapSearchSheetContent extends StatelessWidget {
  final bool isDark;
  final int transportMode;
  final bool isSheetOpen;
  final String? activeTicketingMode;
  final Function(String) onTicketingIntent;
  final Function(String?) onTicketingModeChanged;
  final VoidCallback onToggleOpen;

  // OPTIMIZATION: Moved static list here to avoid memory reallocation on every build.
  static const List<Map<String, dynamic>> _itinerarySteps = [];

  const MapSearchSheetContent(
      {super.key,
      required this.isDark,
      required this.transportMode,
      required this.isSheetOpen,
      required this.activeTicketingMode,
      required this.onTicketingIntent,
      required this.onTicketingModeChanged,
      required this.onToggleOpen});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                transportMode == 0 ? "Metro Routing" : "Bus Routing",
                style: GoogleFonts.poppins(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: Icon(
                    isSheetOpen
                        ? Icons.arrow_back_ios_new_rounded
                        : Icons.arrow_forward_ios_rounded,
                    color: isDark ? Colors.white : Colors.black,
                    size: 20),
                onPressed: onToggleOpen,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            ],
          ),
          const SizedBox(height: 20),
          CommuteSearchCard(
            isDark: isDark,
            selectedMode: transportMode,
            activeTicketingMode: activeTicketingMode,
            onTicketingModeChanged: onTicketingModeChanged,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => onTicketingModeChanged(null),
            behavior: HitTestBehavior.opaque,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: activeTicketingMode != null ? 0.3 : 1.0,
              child: IgnorePointer(
                ignoring: activeTicketingMode != null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildItineraryCard(),
                    const SizedBox(height: 30),
                    transportMode == 0
                        ? MetroServicesGrid(
                            onTicketingIntent: onTicketingIntent)
                        : BusServicesGrid(onTicketingIntent: onTicketingIntent),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItineraryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2129) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Detailed Itinerary",
                  style: GoogleFonts.inter(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              Icon(Icons.keyboard_arrow_down_rounded,
                  color: isDark ? Colors.white54 : Colors.black54),
            ],
          ),
          const SizedBox(height: 20),
          // Using the static list here
          ..._itinerarySteps.map((step) => _buildItineraryStep(step)),
        ],
      ),
    );
  }

  Widget _buildItineraryStep(Map<String, dynamic> step) {
    double circleSize = step['type'] == 'station' ? 12 : 18;
    bool isStartOrEnd =
        step['type'] == 'start' || step['type'] == 'destination';
    bool isInterchange = step['type'] == 'interchange';
    Color lineColor = isStartOrEnd
        ? const Color(0xFF8B2CF5)
        : (isInterchange
            ? Colors.white
            : (isDark ? Colors.white24 : Colors.black12));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          child: Column(
            children: [
              const SizedBox(height: 2),
              Container(
                width: circleSize,
                height: circleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: step['type'] == 'destination'
                      ? const Color(0xFF8B2CF5)
                      : Colors.transparent,
                  border: Border.all(
                      color: isDark ? Colors.white : Colors.black,
                      width: isStartOrEnd || isInterchange ? 2 : 1),
                ),
                child: isStartOrEnd || isInterchange
                    ? Center(
                        child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDark ? Colors.white : Colors.black)))
                    : null,
              ),
              if (step['type'] != 'destination')
                Container(
                    width: 2,
                    height: step['type'] == 'station' ? 30 : 50,
                    color: lineColor),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step['station'],
                  style: GoogleFonts.inter(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 16,
                      fontWeight: step['type'] == 'station'
                          ? FontWeight.w500
                          : FontWeight.bold)),
              if (step['details'] != null)
                Text(step['details'],
                    style: GoogleFonts.inter(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontSize: 14)),
              if (step['stops'] != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF121419)
                          : const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(step['stops'],
                          style: GoogleFonts.inter(
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: isDark ? Colors.white : Colors.black, size: 16)
                    ],
                  ),
                ),
              if (step['type'] != 'destination') const SizedBox(height: 16),
            ],
          ),
        )
      ],
    );
  }
}


