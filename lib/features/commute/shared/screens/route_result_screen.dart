import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:provider/provider.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/providers/app_navigation_provider.dart';
import 'package:ridel/core/providers/notification_provider.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/notification_service.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/widgets/ridel_glass.dart';
import 'package:ridel/features/commute/bus/services/bus_service.dart';

import 'package:ridel/features/commute/metro/services/metro_service.dart';
import 'package:ridel/features/commute/shared/models/route_models.dart';
import 'package:ridel/features/commute/shared/widgets/journey_timeline_card.dart';
import 'package:ridel/features/commute/shared/widgets/route_header.dart';
import 'package:ridel/features/commute/shared/widgets/schematic_route_map.dart';
import 'package:ridel/main.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ridel/core/widgets/app_header.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';

import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/app_shadows.dart';
import 'package:ridel/features/commute/shared/widgets/facilities_sheet.dart';

import 'package:ridel/core/widgets/ridel_loading_dots.dart';

class RouteResultScreen extends StatefulWidget {
  final String fromStation;
  final String toStation;
  final List<RouteResult>? routesData;
  final bool isMetro;

  const RouteResultScreen({
    super.key,
    required this.fromStation,
    required this.toStation,
    this.routesData,
    this.isMetro = true,
  });

  @override
  State<RouteResultScreen> createState() => _RouteResultScreenState();
}

class _RouteResultScreenState extends State<RouteResultScreen> {
  late List<RouteResult>? _currentRoutesData;
  late RouteResult? _activeRouteData;
  late String _currentFrom;
  late String _currentTo;
  final BusRoutePreference _busPreference = BusRoutePreference.fastest;
  bool _isLoading = false;
  int? _activeStationIndex;
  String? _trackingError;
  StreamSubscription<Position>? _locationSubscription;
  bool _hasNotifiedArrival = false;
  bool _hasShownFarToast = false;

  bool _isPanelOpen = true;
  double _railWidth = 80.0;
  
  // To track which route is expanded (0 for primary, 1 for alternate)
  int _expandedRouteIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentFrom = widget.fromStation;
    _currentTo = widget.toStation;
    
    // SMART SORT LOGIC: Apply custom sorting before rendering the list
    if (widget.routesData != null && widget.routesData!.length > 1) {
      List<RouteResult> sorted = List.from(widget.routesData!);
      sorted.sort((a, b) {
        int timeDiff = (a.totalTimeMin - b.totalTimeMin).abs();
        if (timeDiff <= 10) {
          int aTransfers = a.path.where((s) => s.type == StationType.interchange).length;
          int bTransfers = b.path.where((s) => s.type == StationType.interchange).length;
          if (aTransfers != bTransfers) {
            return aTransfers.compareTo(bTransfers);
          }
        }
        return a.totalTimeMin.compareTo(b.totalTimeMin);
      });
      _currentRoutesData = sorted;
    } else {
      _currentRoutesData = widget.routesData;
    }
    
    _activeRouteData = _currentRoutesData != null && _currentRoutesData!.isNotEmpty ? _currentRoutesData!.first : null;
    _initLiveTracking();
  }

  void _initLiveTracking() {
    final locationService =
        Provider.of<GlobalLocationService>(context, listen: false);
    if (!locationService.hasValidLocation) {
      setState(() => _trackingError = "GPS signal lost or disabled.");
    }

    _locationSubscription =
        locationService.engineLocationStream.listen((Position userPos) {
      if (_activeRouteData == null || _activeRouteData!.path.isEmpty) {
        return;
      }
      double minDistance = double.infinity;
      int closestIndex = 0;
      final path = _activeRouteData!.path;
      for (int i = 0; i < path.length; i++) {
        double dist = Geolocator.distanceBetween(
            userPos.latitude, userPos.longitude, path[i].lat, path[i].lon);
        if (dist < minDistance) {
          minDistance = dist;
          closestIndex = i;
        }
      }
      double distanceFromStart = Geolocator.distanceBetween(
          userPos.latitude, userPos.longitude, path.first.lat, path.first.lon);

      if (_activeStationIndex == null && distanceFromStart > 3000) {
        if (!_hasShownFarToast) {
          _hasShownFarToast = true;
          if (mounted) {
            ToastService.showInfo(context, "Navigate to starting station", title: "Route Alert");
          }
        }
      }

      if (distanceFromStart <= 200 && !_hasNotifiedArrival) {
        _hasNotifiedArrival = true;
        if (mounted) {
          Provider.of<NotificationProvider>(context, listen: false)
              .pushLocalNotification(
                  title: "Station Reached! 🚀",
                  message:
                      "You are near ${path.first.name}. Open Ridel to continue your journey.",
                  type: NotificationType.system,
                  buzzPhone: true);
        }
      }

      if (mounted) {
        if (_trackingError != null || _activeStationIndex != closestIndex) {
          setState(() {
            _trackingError = null;
            _activeStationIndex = closestIndex;
          });
        }
      }
    });
  }

  void _openDeviceMap() async {
    if (_activeRouteData == null || _activeRouteData!.path.isEmpty) {
      return;
    }
    final locService =
        Provider.of<GlobalLocationService>(context, listen: false);
    final pos = locService.currentPosition;
    if (pos == null) {
      ToastService.showError(context, "Unable to fetch current location.");
      return;
    }
    final double destLat = _activeRouteData!.path.first.lat;
    final double destLng = _activeRouteData!.path.first.lon;
    double distanceInMeters = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, destLat, destLng);
    String googleMode = distanceInMeters <= 300 ? 'walking' : 'driving';
    String appleMode = distanceInMeters <= 300 ? 'w' : 'd';

    final Uri googleUrl = Uri.parse(
        "https://www.google.com/maps/dir/?api=1&origin=${pos.latitude},${pos.longitude}&destination=$destLat,$destLng&travelmode=$googleMode");
    final Uri appleUrl = Uri.parse(
        "http://maps.apple.com/?saddr=${pos.latitude},${pos.longitude}&daddr=$destLat,$destLng&dirflg=$appleMode");

    if (await canLaunchUrl(googleUrl)) {
      await launchUrl(googleUrl, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(appleUrl)) {
      await launchUrl(appleUrl, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ToastService.showError(context, "No map application found.");
    }
  }

  void _openRidelMap() async {
    if (_activeRouteData == null || _activeRouteData!.path.isEmpty) {
      return;
    }
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    final locService =
        Provider.of<GlobalLocationService>(context, listen: false);
    final pos = locService.currentPosition;
    if (pos != null) {
      final destLat = _activeRouteData!.path.first.lat;
      final destLng = _activeRouteData!.path.first.lon;
      final currentLoc = maplibre.LatLng(pos.latitude, pos.longitude);
      final stationLatLng = maplibre.LatLng(destLat, destLng);
      await mapProvider.startStationNavigation(
          currentLoc, stationLatLng, _activeRouteData!.path.first.name);

      if (!mounted) return;
      ToastService.showSuccess(context, "Navigation started in Ridel Maps.");
    } else {
      ToastService.showError(context, "GPS location unavailable.");
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleSwap(String newFrom, String newTo) async {
    _locationSubscription?.cancel();
    setState(() {
      _isLoading = true;
      _currentFrom = newFrom;
      _currentTo = newTo;
      _activeRouteData = null; // Fix: Reset previous route results
      _activeStationIndex = null;
      _trackingError = null;
      _hasNotifiedArrival = false;
    });
    try {
      List<RouteResult>? newRoutesData;
      if (widget.isMetro) {
        newRoutesData = await MetroService().findBestRoute(newFrom, newTo);
      } else {
        final busResult = await BusService()
            .findBusRoute(newFrom, newTo, preference: _busPreference);
        if (busResult != null) {
          newRoutesData = [busResult];
        } else {
          newRoutesData = [];
        }
      }

      if (mounted) {
        setState(() {
          _currentRoutesData = newRoutesData;
          _activeRouteData = newRoutesData != null && newRoutesData.isNotEmpty ? newRoutesData.first : null;
          _expandedRouteIndex = 0;
          _isLoading = false;
        });
        _initLiveTracking(); // Restart live tracking for new route
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final String errorMsg = e.toString().replaceAll("Exception: ", "");
        if (errorMsg.contains("Network error") || errorMsg.contains("No route found")) {
          ToastService.showError(context, errorMsg);
        } else {
          ToastService.showError(context, "Error finding route.");
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    const double desktopMargin = 24.0;
    final bgColor = isDesktop
        ? (isDark ? const Color(0xFF1F1F1E) : const Color(0xFFF8F6F0))
        : (isDark ? const Color(0xFF0B0E17) : const Color(0xFFF8F6F0));

    // ==================== DESKTOP CONTENT ====================
    Widget contentList = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RouteHeader(
          fromStation: _currentFrom,
          toStation: _currentTo,
          topPadding: 0,
          isScrolled: false,
          onBack: () {
            Navigator.pop(context);
            Future.delayed(const Duration(milliseconds: 100), () {
              globalSearchSheetOpen.value = true;
            });
          },
          onSwap: _handleSwap,
        ),
        const SizedBox(height: 25),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _isLoading
              ? _buildLoadingState()
              : _activeRouteData != null
                  ? _buildAccordionRoutes()
                  : _buildErrorState(),
        ),
        const SizedBox(height: 40),
        if (!_isLoading && _activeRouteData != null && widget.isMetro) ...[
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 12),
            child: Text("Station Facilities",
                style: GoogleFonts.inter(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FacilitiesSheetContent(routeData: _activeRouteData!),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );

    // ==================== MOBILE CONTENT ====================

    Widget mobileContent = SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(left: 20, right: 20, top: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppHeader(
                    showProfile: true,
                    isRouteMode: true,
                    backgroundColor: bgColor,
                    onBack: () => Navigator.pop(context),
                    actionWidget: RidelBounceButton(
                      scaleFactor: 0.88,
                      onTap: () {
                        AppHaptics.lightImpact();
                        _openDeviceMap();
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.centerRight,
                        color: Colors.transparent,
                        child: Icon(
                          Icons.near_me_rounded,
                          color: isDark ? Colors.white70 : Colors.black87,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                      const SizedBox(height: 20),


                      
                      _isLoading
                          ? _buildLoadingState()
                          : _activeRouteData != null
                              ? _buildAccordionRoutes()
                              : _buildErrorState(),
                      if (_activeRouteData != null) ...[
                        const SizedBox(height: 20),
                        SchematicRouteMap(
                          routeData: _activeRouteData!,
                          isMetro: widget.isMetro,
                          activeStationIndex: _activeStationIndex,
                          trackingError: _trackingError,
                          onOpenRidelMap: _openRidelMap,
                          onOpenDeviceMap: _openDeviceMap,
                        ),
                        if (widget.isMetro) ...[
                          const SizedBox(height: 20),
                          _buildStationFacilitiesCard(),
                        ],
                      ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );

    return Scaffold(
      backgroundColor: bgColor,
      body: isDesktop
          ? Stack(
              children: [
                Builder(builder: (context) {
                  double baseLeft = desktopMargin + _railWidth + desktopMargin;
                  return AnimatedPositioned(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    left: baseLeft,
                    top: desktopMargin,
                    bottom: desktopMargin,
                    right: desktopMargin,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24.0),
                      child: widget.isMetro
                          ? Container(
                              color: isDark
                                  ? const Color(0xFF0B0E17)
                                  : Colors.white,
                              child: Center(
                                  child: Text("Ola Maps Metro Route Here",
                                      style: TextStyle(color: isDark ? Colors.white24 : Colors.black26))),
                            )
                          : Container(
                              color: isDark
                                  ? const Color(0xFF0B0E17)
                                  : Colors.white,
                              child: Center(
                                  child: Text("Ola Maps Bus Route Here",
                                      style: TextStyle(color: isDark ? Colors.white24 : Colors.black26))),
                            ),
                    ),
                  );
                }),
                Builder(builder: (context) {
                  double baseLeft = desktopMargin + _railWidth + desktopMargin;
                  return Positioned(
                    top: desktopMargin + 24.0,
                    left: baseLeft + 24.0,
                    width: 380,
                    child: AnimatedScale(
                      scale: _isPanelOpen ? 1.0 : 0.0,
                      alignment: Alignment.topLeft,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutQuint,
                      child: AnimatedOpacity(
                        opacity: _isPanelOpen ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: IgnorePointer(
                          ignoring: !_isPanelOpen,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxHeight: MediaQuery.of(context).size.height -
                                    (desktopMargin * 2) -
                                    48.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF0B0E17)
                                        .withValues(alpha: 0.98)
                                    : Colors.white.withValues(alpha: 0.98),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.black.withValues(alpha: 0.05)),
                                boxShadow: isDark
                                    ? AppShadows.cardFloating
                                    : [
                                        BoxShadow(
                                          color: const Color(0xFFE5E0D8).withValues(alpha: 0.8),
                                          blurRadius: 24,
                                          spreadRadius: -4,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  padding: const EdgeInsets.only(
                                      top: 24, bottom: 24),
                                  child: contentList,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                Builder(builder: (context) {
                  double baseLeft = desktopMargin + _railWidth + desktopMargin;
                  return Positioned(
                    top: desktopMargin + 24.0,
                    left: baseLeft + 24.0,
                    child: AnimatedScale(
                      scale: !_isPanelOpen ? 1.0 : 0.0,
                      alignment: Alignment.center,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutQuint,
                      child: IgnorePointer(
                        ignoring: _isPanelOpen,
                        child: RidelBounceButton(
                          scaleFactor: 0.85,
                          onTap: () {
                            setState(() => _isPanelOpen = true);
                          },
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: RidelGlass(
                              borderRadius: BorderRadius.circular(50),
                              baseColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
                              blurSigma: 20.0,
                              isVerticalCard: true,
                              child: const Center(
                                  child: Icon(
                                      Icons.keyboard_double_arrow_right_rounded,
                                      color: Color(0xFF00E5FF),
                                      size: 24)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _WebNavigationRail(
                      desktopMargin: desktopMargin,
                      currentWidth: _railWidth,
                      onWidthChanged: (width) =>
                          setState(() => _railWidth = width),
                      isDark: isDark,
                      currentIndex: 0,
                      onTabSelected: (index) {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);

                        final navProvider = Provider.of<AppNavigationProvider>(
                            context,
                            listen: false);

                        Future.delayed(const Duration(milliseconds: 100), () {
                          navProvider.setTab(index);
                        });
                      }),
                ),
              ],
            )
          : mobileContent,
    );
  }

  Widget _buildLoadingState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2129) : Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
        boxShadow: isDark
            ? AppShadows.cardFloating
            : [
                BoxShadow(
                  color: const Color(0xFFE5E0D8).withValues(alpha: 0.8),
                  blurRadius: 24,
                  spreadRadius: -4,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: const Center(
        child: PremiumDotLoader(),
      ),
    );
  }

  Widget _buildErrorState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2129) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.15)),
        boxShadow: isDark
            ? AppShadows.cardFloating
            : [
                BoxShadow(
                  color: const Color(0xFFE5E0D8).withValues(alpha: 0.8),
                  blurRadius: 24,
                  spreadRadius: -4,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 12),
          Flexible(
              child: Text(
                  "Route unavailable. Try changing preferences or checking network.",
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87))),
        ],
      ),
    );
  }
  Widget _buildAccordionRoutes() {
    if (_currentRoutesData == null || _currentRoutesData!.isEmpty) {
      return _buildErrorState();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final routesToRender = _currentRoutesData!.take(2).toList();
    return Column(
      children: List.generate(routesToRender.length, (index) {
        final route = routesToRender[index];
        final isExpanded = _expandedRouteIndex == index;
        final isPrimary = index == 0;
        
        int interchanges = route.path.where((s) => s.type == StationType.interchange).length;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(35),
            clipBehavior: Clip.antiAlias,
            child: AnimatedSize(
              alignment: Alignment.topCenter,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOutCubic,
                  child: AnimatedCrossFade(
                    duration: const Duration(milliseconds: 350),
                    crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    firstChild: GestureDetector(
                      onTap: () {
                        AppHaptics.selectionClick();
                        setState(() {
                          _expandedRouteIndex = index;
                          _activeRouteData = route;
                        });
                        _initLiveTracking();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF161A25).withValues(alpha: 0.75)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(35),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.04),
                            width: 1.0,
                          ),
                          boxShadow: isDark
                              ? [
                                  ...AppShadows.cardFloating,
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.8),
                                    blurRadius: 40,
                                    spreadRadius: 8,
                                    offset: const Offset(0, 15),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: const Color(0xFFE5E0D8).withValues(alpha: 0.8),
                                    blurRadius: 24,
                                    spreadRadius: -4,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isPrimary ? Icons.flash_on_rounded : Icons.alt_route_rounded,
                      color: isPrimary ? Colors.amber : Colors.cyan,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPrimary ? "Suggested Route" : "Alternative Route",
                            style: GoogleFonts.inter(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${(route.totalTimeSeconds / 60).ceil()} min • $interchanges Transfer${interchanges == 1 ? '' : 's'}",
                            style: GoogleFonts.inter(
                              color: isDark ? Colors.white70 : Colors.black54,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      CupertinoIcons.chevron_down,
                      color: isDark ? Colors.white54 : Colors.black45,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
                secondChild: JourneyTimelineCard(
                  routeData: route,
                  fromStation: _currentFrom,
                  toStation: _currentTo,
                  isMetro: widget.isMetro,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStationFacilitiesCard() {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isLightMode
            ? Colors.white
            : const Color(0xFF161A25).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(35),
        border: Border.all(
          color: isLightMode
              ? Colors.black.withValues(alpha: 0.04)
              : Colors.white.withValues(alpha: 0.12),
          width: 1.0,
        ),
        boxShadow: isLightMode
            ? [
                BoxShadow(
                  color: const Color(0xFFE5E0D8).withValues(alpha: 0.8),
                  blurRadius: 24,
                  spreadRadius: -4,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                ...AppShadows.cardFloating,
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 40,
                  spreadRadius: 8,
                  offset: const Offset(0, 15),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.elevator_rounded, color: isLightMode ? Colors.black87 : Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Station Facilities',
                style: GoogleFonts.inter(
                  color: isLightMode ? Colors.black87 : Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _openFacilitiesSheet(isOrigin: true),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    decoration: BoxDecoration(
                      color: isLightMode ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isLightMode ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.building_2_fill, size: 20, color: isLightMode ? Colors.black54 : Colors.white54),
                        const SizedBox(height: 8),
                        Text("Origin", maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, color: isLightMode ? Colors.black54 : Colors.white54, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(_currentFrom.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: isLightMode ? Colors.black87 : Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () => _openFacilitiesSheet(isOrigin: false),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    decoration: BoxDecoration(
                      color: isLightMode ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isLightMode ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.ticket_fill, size: 20, color: isLightMode ? Colors.black54 : Colors.white54),
                        const SizedBox(height: 8),
                        Text("Destination", maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, color: isLightMode ? Colors.black54 : Colors.white54, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(_currentTo.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: isLightMode ? Colors.black87 : Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  void _openFacilitiesSheet({required bool isOrigin}) {
    AppHaptics.selectionClick();
    if (_activeRouteData == null || _activeRouteData!.path.isEmpty) return;
    final path = _activeRouteData!.path;
    final stationId = isOrigin ? path.first.id : path.last.id;
    RidelSheet.show(
      context,
      title: "Station Facilities",
      showCloseButton: true,
      useRootNavigator: true,
      isDynamicHeight: true,
      child: FacilitiesSheetContent(routeData: _activeRouteData!, initialStationId: stationId),
    );
  }
}

class _WebNavigationRail extends StatefulWidget {
  final double desktopMargin;
  final int currentIndex;
  final bool isDark;
  final double currentWidth;
  final Function(double) onWidthChanged;
  final Function(int) onTabSelected;

  const _WebNavigationRail(
      {required this.desktopMargin,
      required this.currentIndex,
      required this.isDark,
      required this.currentWidth,
      required this.onWidthChanged,
      required this.onTabSelected});

  @override
  State<_WebNavigationRail> createState() => _WebNavigationRailState();
}

class _WebNavigationRailState extends State<_WebNavigationRail> {
  void _toggleRail() {
    final bool isCurrentlyExpanded = widget.currentWidth > 80.0;
    widget.onWidthChanged(isCurrentlyExpanded ? 80.0 : 220.0);
  }

  @override
  Widget build(BuildContext context) {
    final bool isExpanded = widget.currentWidth > 80.0;

    return Padding(
      padding: EdgeInsets.only(
          left: widget.desktopMargin,
          top: widget.desktopMargin,
          bottom: widget.desktopMargin,
          right: 0),
      child: RidelBounceButton(
        scaleFactor: 0.98,
        onTap: _toggleRail,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          width: widget.currentWidth,
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF1E2129) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: widget.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05)),
            boxShadow: AppShadows.cardFloating,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: ValueListenableBuilder<int>(
                valueListenable: globalTransportMode,
                builder: (context, transportMode, child) {
                  return CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 25),
                            Container(
                              height: 60,
                              margin: const EdgeInsets.only(bottom: 20),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 70,
                                    child: Center(
                                      child: RidelBounceButton(
                                        scaleFactor: 0.85,
                                        onTap: () {
                                          Navigator.of(context).popUntil(
                                              (route) => route.isFirst);
                                          Future.delayed(
                                              const Duration(milliseconds: 150),
                                              () {
                                            globalIsHome.value = true;
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                              color: widget.isDark
                                                  ? Colors.white
                                                      .withValues(alpha: 0.1)
                                                  : Colors.black
                                                      .withValues(alpha: 0.05),
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          child: Icon(
                                              Icons.directions_bike_rounded,
                                              color: widget.isDark
                                                  ? Colors.white
                                                  : Colors.black,
                                              size: 28),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Flexible(
                                    child: AnimatedOpacity(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      opacity: isExpanded ? 1.0 : 0.0,
                                      child: Text("RIDEL",
                                          style: GoogleFonts.poppins(
                                              color: widget.isDark
                                                  ? Colors.white
                                                  : Colors.black,
                                              fontSize: 22,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 2.0),
                                          maxLines: 1,
                                          overflow: TextOverflow.clip),
                                    ),
                                  )
                                ],
                              ),
                            ),
                            _RailItem(
                                icon: Icons.train_rounded,
                                label: "Metro",
                                isActive: widget.currentIndex == 0 &&
                                    transportMode == 0,
                                activeColor: const Color(0xFF00E5FF),
                                isDark: widget.isDark,
                                isExpanded: isExpanded,
                                onTap: () {
                                  Navigator.of(context)
                                      .popUntil((route) => route.isFirst);
                                  Future.delayed(
                                      const Duration(milliseconds: 150), () {
                                    globalTransportMode.value = 0;
                                    globalIsHome.value = false;
                                    globalSearchSheetOpen.value = true;
                                    widget.onTabSelected(0);
                                  });
                                }),
                            const SizedBox(height: 8),
                            _RailItem(
                                icon: Icons.directions_bus_rounded,
                                label: "Bus",
                                isActive: widget.currentIndex == 0 &&
                                    transportMode == 1,
                                activeColor: const Color(0xFFFF9F0A),
                                isDark: widget.isDark,
                                isExpanded: isExpanded,
                                onTap: () {
                                  Navigator.of(context)
                                      .popUntil((route) => route.isFirst);
                                  Future.delayed(
                                      const Duration(milliseconds: 150), () {
                                    globalTransportMode.value = 1;
                                    globalIsHome.value = false;
                                    globalSearchSheetOpen.value = true;
                                    widget.onTabSelected(0);
                                  });
                                }),
                            const SizedBox(height: 8),
                            _RailItem(
                                icon: Icons.map_rounded,
                                label: "Map",
                                isActive: widget.currentIndex == 1,
                                activeColor: const Color(0xFF00E5FF),
                                isDark: widget.isDark,
                                isExpanded: isExpanded,
                                onTap: () {
                                  Navigator.of(context)
                                      .popUntil((route) => route.isFirst);
                                  Future.delayed(
                                      const Duration(milliseconds: 150), () {
                                    globalIsHome.value = false;
                                    widget.onTabSelected(1);
                                  });
                                }),
                            const Spacer(),
                            _RailItem(
                                icon: Icons.notifications_rounded,
                                label: "Notifications",
                                isActive: false,
                                activeColor: widget.isDark ? Colors.white : Colors.black87,
                                isDark: widget.isDark,
                                isExpanded: isExpanded,
                                onTap: () {}),
                            const SizedBox(height: 8),
                            _RailItem(
                                icon: Icons.person_rounded,
                                label: "Profile",
                                isActive: false,
                                activeColor: widget.isDark ? Colors.white : Colors.black87,
                                isDark: widget.isDark,
                                isExpanded: isExpanded,
                                onTap: () {
                                  Navigator.of(context)
                                      .popUntil((route) => route.isFirst);
                                }),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final bool isDark;
  final bool isExpanded;
  final VoidCallback onTap;
  const _RailItem(
      {required this.icon,
      required this.label,
      required this.isActive,
      required this.activeColor,
      required this.isDark,
      required this.isExpanded,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color =
        isActive ? activeColor : (isDark ? Colors.white54 : Colors.black54);
    return RidelBounceButton(
      scaleFactor: 0.95,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              SizedBox(
                  width: 70,
                  child: Center(child: Icon(icon, color: color, size: 26))),
              Flexible(
                  child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: isExpanded ? 1.0 : 0.0,
                      child: Text(label,
                          style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w500,
                              color: color),
                          maxLines: 1,
                          overflow: TextOverflow.clip)))
            ],
          ),
        ),
      ),
    );
  }
}
