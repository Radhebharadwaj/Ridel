import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/widgets/app_header.dart';
import 'package:ridel/main.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/features/commute/metro/map/metro_data_provider.dart';

// 🚀 Naye Imports Welcome Flow ke liye
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/profile/services/profile_repository.dart';
import '../core/utils/toast_service.dart';

import '../core/providers/app_navigation_provider.dart';
import '../core/utils/app_haptics.dart';

import '../core/widgets/ridel_glass.dart';
import '../core/widgets/ridel_sheet.dart';
import '../features/commute/bus/widgets/bus_services_grid.dart';

import '../features/commute/metro/widgets/metro_services_grid.dart';
import '../features/commute/shared/screens/commute_screen.dart';
import '../features/commute/shared/widgets/commute_search_card.dart';
import '../features/map/screens/full_screen_map.dart';

import '../features/profile/screens/profile_screen.dart';
import 'glass_nav_bar.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final ValueNotifier<double> _searchSheetProgressNotifier = ValueNotifier(0.0);

  double _railWidth = 240.0;
  bool _isSidebarVisible = true;

  @override
  void initState() {
    super.initState();
    // 🚀 MASTER WELCOME FLOW TRIGGER
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWelcomeFlow();
      _checkAndTriggerColdBootLocation();
      
      // 🚀 TASK 3: Eager Pre-fetching (The Flash Speed Trick)
      final locService = Provider.of<GlobalLocationService>(context, listen: false);
      locService.addListener(_onLocationUpdated);
    });
  }

  void _onLocationUpdated() {
    if (!mounted) return;
    final locService = Provider.of<GlobalLocationService>(context, listen: false);
    if (locService.currentPosition != null) {
      // Silently trigger the fetch in background
      Provider.of<MetroDataProvider>(context, listen: false).fetchMapData();
      locService.removeListener(_onLocationUpdated);
    }
  }

  // 🚀 TASK 2: COLD-BOOT HOOK
  Future<void> _checkAndTriggerColdBootLocation() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      if (mounted) {
        // Automatically trigger detection without asking user again
        Provider.of<GlobalLocationService>(context, listen: false).autoDetectAndSetRegion();
      }
    }
  }

  // ==========================================================
  // 🌟 PREMIUM WELCOME LOGIC (Guest tooltip removed)
  // ==========================================================
  Future<void> _handleWelcomeFlow() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final user = Supabase.instance.client.auth.currentUser;

    if (user != null) {
      // 🟢 LOGGED IN USER
      final profile = await ProfileRepository().getProfile();
      if (mounted) {
        final String fullName = profile?['full_name'] ?? 'Explorer';
        final String firstName = fullName.split(' ')[0]; // Sirf First Name

        AppHaptics.success();
        ToastService.showSuccess(context,
            'Welcome back, $firstName! 🚗 Ready for your next journey?');
      }
    }
    // No action for guest users – the floating button has been removed.
  }

  @override
  void dispose() {
    _searchSheetProgressNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isDesktop = MediaQuery.of(context).size.width > 600;

    const double desktopMargin = 32.0;

    final double statusBarHeight = MediaQuery.of(context).padding.top;

    final navProvider = Provider.of<AppNavigationProvider>(context);
    final bool isCommuteActive = navProvider.currentIndex == 0;
    final bool isMapActive = navProvider.currentIndex == 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // ==========================================================
            // 🚀 LAYER 1: BASE MAPS
            // ==========================================================
            ValueListenableBuilder<bool>(
              valueListenable: globalIsHome,
              builder: (context, isHome, child) {
                return ValueListenableBuilder<int>(
                  valueListenable: globalTransportMode,
                  builder: (context, transportMode, child) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: globalSearchSheetOpen,
                      builder: (context, isSearchOpen, child) {
                        bool showMetroMap =
                            isCommuteActive && transportMode == 0 && !isHome;
                        bool showBusMapPlaceholder =
                            isCommuteActive && transportMode == 1 && !isHome;
                        bool showOlaMap = isDesktop || isMapActive;

                        return AnimatedPositioned(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutQuint,
                          left: 0,
                          top: 0,
                          bottom: 0,
                          right: 0,
                          child: IgnorePointer(
                            ignoring: isDesktop && _isSidebarVisible,
                            child: ClipRRect(
                              borderRadius: BorderRadius.zero,
                            child: Stack(
                              children: [
                                AnimatedOpacity(
                                  duration: const Duration(milliseconds: 300),
                                  opacity: showOlaMap ? 1.0 : 0.0,
                                  child: IgnorePointer(
                                    ignoring: !showOlaMap,
                                    child: FullScreenMapPage(
                                      searchSheetProgressNotifier:
                                          _searchSheetProgressNotifier,
                                      isMapTabActive: isMapActive,
                                    ),
                                  ),
                                ),
                                AnimatedOpacity(
                                  duration: const Duration(milliseconds: 300),
                                  opacity: showMetroMap ? 1.0 : 0.0,
                                  child: IgnorePointer(
                                    ignoring: !showMetroMap,
                                    child: Container(
                                      color: Colors.transparent,
                                      child: const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                                AnimatedOpacity(
                                  duration: const Duration(milliseconds: 300),
                                  opacity: showBusMapPlaceholder ? 1.0 : 0.0,
                                  child: IgnorePointer(
                                    ignoring: !showBusMapPlaceholder,
                                    child: Container(
                                        color: Colors.transparent),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    );
                  },
                );
              },
            ),

            // ==========================================================
            // 💻 LAYER 2: DESKTOP PANELS & DASHBOARD
            // ==========================================================
            if (isDesktop) ...[
              ValueListenableBuilder<bool>(
                valueListenable: globalIsHome,
                builder: (context, isHome, child) {
                  return ValueListenableBuilder<int>(
                    valueListenable: globalTransportMode,
                    builder: (context, transportMode, child) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: globalSearchSheetOpen,
                        builder: (context, isSearchOpen, child) {
                          bool showCommutePanel = isCommuteActive && !isHome;
                          double panelWidth = 380.0;
                          double baseLeft =
                              desktopMargin + _railWidth + desktopMargin;

                          return Stack(
                            children: [

                              Positioned(
                                top: desktopMargin + 24.0,
                                left: baseLeft + 24.0,
                                child: AnimatedScale(
                                  scale: (!isHome && !isSearchOpen) ? 1.0 : 0.0,
                                  alignment: Alignment.center,
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOutQuint,
                                  child: IgnorePointer(
                                    ignoring: isSearchOpen,
                                    child: GestureDetector(
                                      onTap: () {
                                        AppHaptics.selectionClick();
                                        globalSearchSheetOpen.value = true;
                                      },
                                      child: SizedBox(
                                        width: 56,
                                        height: 56,
                                        child: RidelGlass(
                                          borderRadius:
                                              BorderRadius.circular(50),
                                          baseColor: isDark
                                              ? const Color(0xFF1C1C1E)
                                                  .withValues(alpha: 0.90)
                                              : Colors.white
                                                  .withValues(alpha: 0.95),
                                          blurSigma: 20.0,
                                          isVerticalCard: true,
                                          child: const Center(
                                              child: Icon(
                                                  Icons
                                                      .keyboard_double_arrow_right_rounded,
                                                  color: Color(0xFF00E5FF),
                                                  size: 24)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: desktopMargin + 24.0,
                                left: baseLeft + 24.0,
                                width: panelWidth,
                                child: AnimatedScale(
                                  scale: (showCommutePanel && isSearchOpen)
                                      ? 1.0
                                      : 0.0,
                                  alignment: Alignment.topLeft,
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOutQuint,
                                  child: AnimatedOpacity(
                                    opacity: (showCommutePanel && isSearchOpen)
                                        ? 1.0
                                        : 0.0,
                                    duration: const Duration(milliseconds: 300),
                                    child: IgnorePointer(
                                      ignoring:
                                          !(showCommutePanel && isSearchOpen),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                            maxHeight: MediaQuery.of(context)
                                                    .size
                                                    .height -
                                                (desktopMargin * 2) -
                                                48.0),
                                        child: _buildDesktopCommutePanel(
                                            isDark, transportMode),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ],

            // ==========================================================
            // 📱 LAYER 3: PREMIUM MOBILE LAYOUT
            // ==========================================================
            if (!isDesktop) ...[
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: isMapActive,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    opacity: isMapActive ? 0.0 : 1.0,
                    child: Container(
                        color: isDark ? const Color(0xFF0B0E17) : Colors.white,
                        child: const CommuteScreen()),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                bottom: (isMapActive) ? -150 : 20,
                left: 0,
                right: 0,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: GlassNavBar(
                      currentIndex: navProvider.currentIndex,
                      onTabSelected: (index) {
                        AppHaptics.selectionClick();
                        if (index == 1) {
                          // 🚀 ADDED {
                          globalIsHome.value = false;
                        } else {
                          globalIsHome.value = true;
                        }
                        navProvider.setTab(index);
                      },
                      onProfileTapped: () {
                        AppHaptics.lightImpact();
                        RidelSheet.show(
                          context,
                          title: "Settings",
                          showCloseButton: true,
                          child: const ProfileSheetContent(),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],

            // ==========================================================
            // 🚀 LAYER 4: WEB NAVIGATION RAIL
            // ==========================================================
            if (isDesktop)
              Positioned.fill(
                child: _WebNavigationRail(
                  desktopMargin: desktopMargin,
                  currentIndex: navProvider.currentIndex,
                  isDark: isDark,
                  currentWidth: _railWidth,
                  onWidthChanged: (width) => setState(() => _railWidth = width),
                  onTabSelected: (index) => navProvider.setTab(index),
                  isSidebarVisible: _isSidebarVisible,
                  onVisibilityChanged: (visible) {
                    setState(() => _isSidebarVisible = visible);
                  },
                ),
              ),

            if (!isDesktop)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: statusBarHeight + 10,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          isDark
                              ? const Color(0xFF0B0E17).withValues(alpha: 0.85)
                              : Colors.white.withValues(alpha: 0.95),
                          isDark
                              ? const Color(0xFF0B0E17).withValues(alpha: 0.0)
                              : Colors.white.withValues(alpha: 0.0)
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopCommutePanel(bool isDark, int transportMode) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1C1C1E).withValues(alpha: 0.85)
                : const Color(0xFFF2F2F7).withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: 0)
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: AppHeader(showProfile: false)),
                    IconButton(
                      icon: Icon(Icons.keyboard_double_arrow_left_rounded,
                          color: isDark ? Colors.white70 : Colors.black87),
                      onPressed: () {
                        AppHaptics.lightImpact();
                        globalSearchSheetOpen.value = false;
                      },
                    )
                  ],
                ),
                const SizedBox(height: 20),
                CommuteSearchCard(isDark: isDark, selectedMode: transportMode),
                const SizedBox(height: 30),
                transportMode == 0
                    ? const MetroServicesGrid()
                    : const BusServicesGrid(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==============================================================
// 💎 _WebNavigationRail & _DesktopPromoDashboard classes same rahengi
// ==============================================================
class _WebNavigationRail extends StatefulWidget {
  final double desktopMargin;
  final int currentIndex;
  final bool isDark;
  final double currentWidth;
  final Function(double) onWidthChanged;
  final Function(int) onTabSelected;
  final bool isSidebarVisible;
  final ValueChanged<bool> onVisibilityChanged;

  const _WebNavigationRail({
    required this.desktopMargin,
    required this.currentIndex,
    required this.isDark,
    required this.currentWidth,
    required this.onWidthChanged,
    required this.onTabSelected,
    required this.isSidebarVisible,
    required this.onVisibilityChanged,
  });

  @override
  State<_WebNavigationRail> createState() => _WebNavigationRailState();
}

class _WebNavigationRailState extends State<_WebNavigationRail> {
  bool _isRightPaneOpen = false; 
  String _activeRightPaneTab = ''; // can be 'search', 'metro', 'bus', etc.

  bool get isDark => widget.isDark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Floating "Restore Sidebar" button
        AnimatedPositioned(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          top: 24,
          left: widget.isSidebarVisible ? -100 : 20, // Only visible when sidebar is hidden
          child: FloatingActionButton.small(
            backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            child: Icon(Icons.view_sidebar_rounded, color: isDark ? Colors.white : Colors.black),
            onPressed: () => widget.onVisibilityChanged(true),
          ),
        ),

        // Sliding Sidebar (Fixed - No RawGestureDetector, No EagerGestureRecognizer)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          top: 0, bottom: 0,
          left: widget.isSidebarVisible ? 0 : -600.0, 
          child: _buildSidebarContent(),
        ),
      ],
    );
  }

  Widget _buildSidebarContent() {
    final content = MouseRegion(
      opaque: true, // Safely blocks clicks/hovers from reaching the map without swallowing children's taps
      child: Listener(
        onPointerSignal: (event) {}, // Blocks scroll wheel leaks
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0), // EXACT Weather Card Blur
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: isDark 
                    ? const Color(0xFF1E2129).withValues(alpha: 0.85) // EXACT Weather Card Color
                    : Colors.white.withValues(alpha: 0.85),
                border: Border(
                  right: BorderSide(
                    color: isDark 
                        ? Colors.white.withValues(alpha: 0.12) // EXACT Weather Card Border
                        : Colors.black.withValues(alpha: 0.05),
                    width: 1.0,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min, // Hugs the animating right pane
                children: [
                  _buildLeftPane(),
                  _buildDynamicRightPane(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    
    return kIsWeb ? PointerInterceptor(child: content) : content;
  }

  Widget _buildLeftPane() {
    return Container(
      width: 240,
      color: Colors.transparent, // CRITICAL: Let the unified parent glass show through
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header (Logo & BETA)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(
              children: [
                Icon(Icons.directions_bike_rounded, color: isDark ? Colors.white : Colors.black, size: 24),
                const SizedBox(width: 8),
                Text('Maps', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(8)),
                  child: Text('BETA', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          
          // 2. SCROLLABLE MIDDLE SECTION (Fixes Overflow)
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Transport Modes (Wiring to globalTransportMode)
                  ValueListenableBuilder<int>(
                    valueListenable: globalTransportMode,
                    builder: (context, mode, child) {
                      return Column(
                        children: [
                          _buildDesktopNavButton(
                            icon: Icons.train_rounded, 
                            title: 'Metro', 
                            isActive: _activeRightPaneTab == 'metro', 
                            isDark: isDark, 
                            onTap: () {
                              globalTransportMode.value = 0;
                              setState(() {
                                _isRightPaneOpen = true;
                                _activeRightPaneTab = 'metro';
                              });
                            }
                          ),
                          _buildDesktopNavButton(
                            icon: Icons.directions_bus_rounded, 
                            title: 'Bus', 
                            isActive: _activeRightPaneTab == 'bus', 
                            isDark: isDark, 
                            onTap: () {
                              globalTransportMode.value = 1;
                              setState(() {
                                _isRightPaneOpen = true;
                                _activeRightPaneTab = 'bus';
                              });
                            }
                          ),
                        ],
                      );
                    }
                  ),
                  
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0), child: Divider(color: Colors.white10, height: 1)),
                  
                  // 3. Main Actions
                  _buildDesktopNavButton(
                    icon: Icons.search, 
                    title: 'Search', 
                    isActive: _activeRightPaneTab == 'search', 
                    isDark: isDark, 
                    onTap: () {
                      setState(() {
                        _isRightPaneOpen = true;
                        _activeRightPaneTab = 'search';
                      });
                    }
                  ),
                  _buildDesktopNavButton(icon: Icons.grid_view_rounded, title: 'Guides', isActive: false, isDark: isDark, onTap: () {}),
                  _buildDesktopNavButton(icon: Icons.directions_rounded, title: 'Directions', isActive: false, isDark: isDark, onTap: () {}),
                  
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0), child: Divider(color: Colors.white10, height: 1)),
                  
                  // 4. Recents
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                    child: Text('Recents', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13)),
                  ),
                  // (Inject Recent items list here later)
                ],
              ),
            ),
          ),
          
          // 3. BOTTOM BUTTONS (Safely anchored, no Spacer needed)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider(color: Colors.white10, height: 1)),
          const SizedBox(height: 8),
          
          // 5. Bottom Settings & Profile
          _buildDesktopNavButton(icon: Icons.notifications_rounded, title: 'Notifications', isActive: _activeRightPaneTab == 'notifications', isDark: isDark, onTap: () {
            setState(() { _isRightPaneOpen = true; _activeRightPaneTab = 'notifications'; });
          }),
          _buildDesktopNavButton(icon: Icons.person_outline_rounded, title: 'Profile', isActive: _activeRightPaneTab == 'profile', isDark: isDark, onTap: () {
            setState(() { _isRightPaneOpen = true; _activeRightPaneTab = 'profile'; });
          }),
          _buildDesktopNavButton(icon: Icons.phone_iphone_rounded, title: 'Get App', isActive: _activeRightPaneTab == 'get_app', isDark: isDark, onTap: () {
            setState(() { _isRightPaneOpen = true; _activeRightPaneTab = 'get_app'; });
          }),
          _buildDesktopNavButton(icon: Icons.keyboard_double_arrow_left_rounded, title: 'Hide Sidebar', isActive: false, isDark: isDark, onTap: () {
            widget.onVisibilityChanged(false);
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDynamicRightPane() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      width: _isRightPaneOpen ? 360.0 : 0.0,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.transparent, // CRITICAL: Let the unified parent glass show through
        border: Border(
          left: BorderSide(
            // Subtle inner divider between the left and right pane
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
            width: 1.0,
          ),
        ),
      ),
      child: ClipRect(
        child: OverflowBox(
          minWidth: 360.0,
          maxWidth: 360.0,
          alignment: Alignment.topLeft,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dynamic Header with Close Button
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _activeRightPaneTab == 'search' ? 'Search' : 
                        _activeRightPaneTab == 'metro' ? 'Metro Routing' : 
                        _activeRightPaneTab == 'bus' ? 'Bus Routing' :
                        _activeRightPaneTab == 'profile' ? 'Profile Settings' :
                        _activeRightPaneTab == 'notifications' ? 'Notifications' :
                        _activeRightPaneTab == 'get_app' ? 'Get App' : 'Menu', 
                        style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 22, fontWeight: FontWeight.bold)
                      ),
                      IconButton(
                        icon: Icon(Icons.cancel_rounded, color: isDark ? Colors.white30 : Colors.black38),
                        onPressed: () => setState(() => _isRightPaneOpen = false), // Closes the pane
                      ),
                    ],
                  ),
                ),
                // Dynamic Body Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: _buildRightPaneContent(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightPaneContent() {
    switch (_activeRightPaneTab) {
      case 'metro':
      case 'bus':
        return Column(
          children: [
            CommuteSearchCard(isDark: isDark, selectedMode: _activeRightPaneTab == 'metro' ? 0 : 1, activeTicketingMode: null, onTicketingModeChanged: (_) {}),
            const SizedBox(height: 24),
            _activeRightPaneTab == 'metro' ? MetroServicesGrid(onTicketingIntent: (_) {}) : BusServicesGrid(onTicketingIntent: (_) {}),
          ],
        );
      case 'profile':
        return Center(child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text('Profile Settings Content', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
        ));
      case 'get_app':
        return Center(child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text('QR Code & App Download Links', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
        ));
      case 'notifications':
        return Center(child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text('Your Notifications', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
        ));
      case 'search':
      default:
        return _buildSearchTabContent(); // Your existing search logic
    }
  }

  Widget _buildSearchTabContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 2. Search Input Box
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: isDark ? Colors.white54 : Colors.black54, size: 20),
              const SizedBox(width: 10),
              Text('Ridel Maps', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 15)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // 3. Find Nearby Header & List
        Text('Find Nearby', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _buildDesktopNearbyTile(context, icon: Icons.local_gas_station_rounded, color: Colors.blueAccent, title: 'Petrol Pumps', isDark: isDark),
              _buildDesktopDivider(isDark),
              _buildDesktopNearbyTile(context, icon: Icons.train_rounded, color: Colors.blue, title: 'Railway Stations', isDark: isDark),
              _buildDesktopDivider(isDark),
              _buildDesktopNearbyTile(context, icon: Icons.hotel_rounded, color: Colors.purpleAccent, title: 'Hotels', isDark: isDark),
              _buildDesktopDivider(isDark),
              _buildDesktopNearbyTile(context, icon: Icons.directions_subway_rounded, color: Colors.blueAccent, title: 'Metro', isDark: isDark),
              _buildDesktopDivider(isDark),
              _buildDesktopNearbyTile(context, icon: Icons.restaurant_rounded, color: Colors.orange, title: 'Restaurants', isDark: isDark),
              _buildDesktopDivider(isDark),
              _buildDesktopNearbyTile(context, icon: Icons.local_parking_rounded, color: Colors.blueAccent, title: 'Parking', isDark: isDark),
              _buildDesktopDivider(isDark),
              _buildDesktopNearbyTile(context, icon: Icons.coffee_rounded, color: Colors.orangeAccent, title: 'Coffee', isDark: isDark),
              _buildDesktopDivider(isDark),
              _buildDesktopNearbyTile(context, icon: Icons.local_gas_station_rounded, color: Colors.lightBlue, title: 'CNG', isDark: isDark),
              _buildDesktopDivider(isDark),
              _buildDesktopNearbyTile(context, icon: Icons.fitness_center_rounded, color: Colors.cyan, title: 'Gym', isDark: isDark),
            ],
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildDesktopNavButton({required IconData icon, required String title, required bool isActive, required bool isDark, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: InkWell(
        onTap: onTap, // WIRED UP
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? (isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.shade50) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          child: Row(
            children: [
              Icon(icon, color: isActive ? Colors.blue : (isDark ? Colors.white54 : Colors.black54), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title, 
                  style: TextStyle(color: isActive ? Colors.blue : (isDark ? Colors.white : Colors.black), fontSize: 15, fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopNearbyTile(BuildContext context, {required IconData icon, required Color color, required String title, required bool isDark}) {
    return InkWell(
      onTap: () {
        AppHaptics.selectionClick();
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 16),
            Text(
              title,
              style: GoogleFonts.inter(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 48.0),
      child: Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
    );
  }
}


class DelayedOffstage extends StatefulWidget {
  final bool offstage;
  final Duration delay;
  final Widget child;

  const DelayedOffstage({
    super.key,
    required this.offstage,
    required this.delay,
    required this.child,
  });

  @override
  State<DelayedOffstage> createState() => _DelayedOffstageState();
}

class _DelayedOffstageState extends State<DelayedOffstage> {
  bool _offstage = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _offstage = widget.offstage;
  }

  @override
  void didUpdateWidget(DelayedOffstage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.offstage != oldWidget.offstage) {
      _timer?.cancel();
      if (widget.offstage) {
        _timer = Timer(widget.delay, () {
          if (mounted) {
            setState(() {
              _offstage = true;
            });
          }
        });
      } else {
        setState(() {
          _offstage = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: _offstage,
      child: widget.child,
    );
  }
}
