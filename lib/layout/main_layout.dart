import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/widgets/app_header.dart';
import 'package:ridel/main.dart';

// 🚀 Naye Imports Welcome Flow ke liye
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/profile/services/profile_repository.dart';
import '../core/utils/toast_service.dart';


import '../core/providers/app_navigation_provider.dart';
import '../core/utils/app_haptics.dart';
import '../core/widgets/notification_sheet.dart';
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

  double _railWidth = 70.0;

  @override
  void initState() {
    super.initState();
    // 🚀 MASTER WELCOME FLOW TRIGGER
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWelcomeFlow();
    });
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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                        bool showOlaMap =
                            isMapActive && (isDesktop ? !isHome : true);

                        return AnimatedPositioned(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutQuint,
                          left: 0,
                          top: 0,
                          bottom: 0,
                          right: 0,
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
                                      color: isDark
                                          ? const Color(0xFF0B0E17)
                                          : Colors.white,
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
                                        color: isDark
                                            ? const Color(0xFF0B0E17)
                                            : Colors.white),
                                  ),
                                ),
                              ],
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
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOutQuint,
                                top: desktopMargin,
                                bottom: desktopMargin,
                                right: desktopMargin,
                                left: baseLeft,
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 200),
                                  opacity: isHome ? 1.0 : 0.0,
                                  child: IgnorePointer(
                                    ignoring: !isHome,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF0B0E17)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                            color: isDark
                                                ? Colors.white
                                                    .withValues(alpha: 0.02)
                                                : Colors.black
                                                    .withValues(alpha: 0.05)),
                                      ),
                                      child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          child: _DesktopPromoDashboard(
                                              isDark: isDark,
                                              navProvider: navProvider)),
                                    ),
                                  ),
                                ),
                              ),
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
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: _WebNavigationRail(
                  desktopMargin: desktopMargin,
                  currentIndex: navProvider.currentIndex,
                  isDark: isDark,
                  currentWidth: _railWidth,
                  onWidthChanged: (width) => setState(() => _railWidth = width),
                  onTabSelected: (index) => navProvider.setTab(index),
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

  const _WebNavigationRail({
    required this.desktopMargin,
    required this.currentIndex,
    required this.isDark,
    required this.currentWidth,
    required this.onWidthChanged,
    required this.onTabSelected,
  });

  @override
  State<_WebNavigationRail> createState() => _WebNavigationRailState();
}

class _WebNavigationRailState extends State<_WebNavigationRail> {
  bool _isHidden = false;
  bool _isNotifActive = false;
  bool _isProfileActive = false;
  bool _isGetAppActive = false;
  bool _isAnimating = false;

  void _toggleRailExpand() {
    if (_isHidden || _isAnimating) return;
    AppHaptics.selectionClick();
    _isAnimating = true;
    final bool isCurrentlyExpanded = widget.currentWidth > 75.0;
    widget.onWidthChanged(isCurrentlyExpanded ? 70.0 : 220.0);
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) _isAnimating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isExpanded = widget.currentWidth > 75 && !_isHidden;
    final double currentRadius = _isHidden ? 24.0 : (isExpanded ? 24.0 : 100.0);

    return Padding(
      padding: EdgeInsets.only(
          left: widget.desktopMargin,
          top: widget.desktopMargin,
          bottom: widget.desktopMargin,
          right: 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: Alignment.bottomLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              height: _isHidden ? 48.0 : constraints.maxHeight,
              width: _isHidden ? 48.0 : widget.currentWidth,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(currentRadius),
                border: Border.all(
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 1),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black
                          .withValues(alpha: _isHidden ? 0.15 : 0.25),
                      blurRadius: _isHidden ? 20 : 40,
                      offset: const Offset(0, 5))
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(currentRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 40.0, sigmaY: 40.0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    color: widget.isDark
                        ? const Color(0xFF1C1C1E).withValues(alpha: 0.85)
                        : const Color(0xFFF2F2F7).withValues(alpha: 0.90),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: 0,
                          bottom: 0,
                          left: 0,
                          width: 220.0,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 250),
                            opacity: _isHidden ? 0.0 : 1.0,
                            child: IgnorePointer(
                                ignoring: _isHidden,
                                child:
                                    _buildSidebarContent(isExpanded, context)),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 250),
                            opacity: _isHidden ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !_isHidden,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  AppHaptics.heavyImpact();
                                  setState(() => _isHidden = false);
                                  widget.onWidthChanged(70.0);
                                },
                                child: Container(
                                    width: 48,
                                    height: 48,
                                    color: Colors.transparent,
                                    child: Center(
                                        child: Icon(Icons.menu_rounded,
                                            color: widget.isDark
                                                ? Colors.white
                                                    .withValues(alpha: 0.9)
                                                : Colors.black87,
                                            size: 22))),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSidebarContent(bool isExpanded, BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleRailExpand,
      onDoubleTap: _toggleRailExpand,
      child: ValueListenableBuilder<bool>(
        valueListenable: globalIsHome,
        builder: (context, isHome, child) {
          return ValueListenableBuilder<int>(
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
                        const SizedBox(height: 30),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              AppHaptics.lightImpact();
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                              Future.delayed(const Duration(milliseconds: 150),
                                  () {
                                if (mounted) {
                                  globalIsHome.value = true;
                                  widget.onTabSelected(0);
                                }
                              });
                            },
                            child: Container(
                              height: 60,
                              color: Colors.transparent,
                              child: Row(
                                children: [
                                  SizedBox(
                                      width: 68,
                                      child: Center(
                                          child: Icon(
                                              Icons.directions_bike_rounded,
                                              color: widget.isDark
                                                  ? Colors.white
                                                  : Colors.black,
                                              size: 30))),
                                  Expanded(
                                      child: ClipRect(
                                          child: AnimatedOpacity(
                                              duration: const Duration(
                                                  milliseconds: 200),
                                              opacity: isExpanded ? 1.0 : 0.0,
                                              child: Text("RIDEL",
                                                  style: GoogleFonts.poppins(
                                                      color: widget.isDark
                                                          ? Colors.white
                                                          : Colors.black,
                                                      fontSize: 24,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      letterSpacing: 2.5),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow:
                                                      TextOverflow.fade))))
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Divider(
                                color: widget.isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.1),
                                height: 1,
                                thickness: 1)),
                        const SizedBox(height: 15),
                        _RailItem(
                            icon: Icons.train_rounded,
                            label: "Metro",
                            isActive: widget.currentIndex == 0 &&
                                transportMode == 0 &&
                                !isHome,
                            activeColor: const Color(0xFF00E5FF),
                            isDark: widget.isDark,
                            isExpanded: isExpanded,
                            onTap: () {
                              AppHaptics.lightImpact();
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                              Future.delayed(const Duration(milliseconds: 150),
                                  () {
                                if (mounted) {
                                  globalTransportMode.value = 0;
                                  globalIsHome.value = false;
                                  globalSearchSheetOpen.value = true;
                                  widget.onTabSelected(0);
                                }
                              });
                            }),
                        const SizedBox(height: 4),
                        _RailItem(
                            icon: Icons.directions_bus_rounded,
                            label: "Bus",
                            isActive: widget.currentIndex == 0 &&
                                transportMode == 1 &&
                                !isHome,
                            activeColor: const Color(0xFFFF9F0A),
                            isDark: widget.isDark,
                            isExpanded: isExpanded,
                            onTap: () {
                              AppHaptics.lightImpact();
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                              Future.delayed(const Duration(milliseconds: 150),
                                  () {
                                if (mounted) {
                                  globalTransportMode.value = 1;
                                  globalIsHome.value = false;
                                  globalSearchSheetOpen.value = true;
                                  widget.onTabSelected(0);
                                }
                              });
                            }),
                        const SizedBox(height: 4),
                        _RailItem(
                            icon: Icons.map_rounded,
                            label: "Map",
                            isActive: widget.currentIndex == 1 && !isHome,
                            activeColor: const Color(0xFF00E5FF),
                            isDark: widget.isDark,
                            isExpanded: isExpanded,
                            onTap: () {
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                              Future.delayed(const Duration(milliseconds: 150),
                                  () {
                                if (mounted) {
                                  globalIsHome.value = false;
                                  globalSearchSheetOpen.value = true;
                                  widget.onTabSelected(1);
                                }
                              });
                            }),
                        const Spacer(),
                        _RailItem(
                            icon: Icons.notifications_rounded,
                            label: "Notifications",
                            isActive: _isNotifActive,
                            activeColor: const Color(0xFFFF3B30),
                            isDark: widget.isDark,
                            isExpanded: isExpanded,
                            onTap: () {
                              AppHaptics.lightImpact();
                              setState(() => _isNotifActive = true);
                              RidelSheet.show(context,
                                      title: "Notifications",
                                      showCloseButton: true,
                                      child: const NotificationSheetContent())
                                  .whenComplete(() {
                                if (mounted) {
                                  // 🚀 ADDED {
                                  setState(() => _isNotifActive = false);
                                } // 🚀 ADDED }
                              });
                            }),
                        const SizedBox(height: 4),
                        _RailItem(
                            icon: Icons.person_rounded,
                            label: "Profile",
                            isActive: _isProfileActive,
                            activeColor: const Color(0xFFB15EFF),
                            isDark: widget.isDark,
                            isExpanded: isExpanded,
                            onTap: () {
                              AppHaptics.lightImpact();
                              setState(() => _isProfileActive = true);
                              RidelSheet.show(context,
                                      title: "Settings",
                                      showCloseButton: true,
                                      customHeader: true,
                                      child: const ProfileSheetContent())
                                  .whenComplete(() {
                                if (mounted) {
                                  setState(() => _isProfileActive = false);
                                }
                              });
                            }),
                        const SizedBox(height: 4),
                        _RailItem(
                            icon: Icons.smartphone_rounded,
                            label: "Get App",
                            isActive: _isGetAppActive,
                            activeColor: const Color(0xFF00E5FF),
                            isDark: widget.isDark,
                            isExpanded: isExpanded,
                            onTap: () {
                              AppHaptics.selectionClick();
                              setState(() => _isGetAppActive = true);
                            }),
                        const SizedBox(height: 12),
                        Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Divider(
                                color: widget.isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.1),
                                height: 1,
                                thickness: 1)),
                        const SizedBox(height: 12),
                        _RailItem(
                            icon: Icons.keyboard_double_arrow_down_rounded,
                            label: "Hide Sidebar",
                            isActive: false,
                            activeColor: Colors.white,
                            isDark: widget.isDark,
                            isExpanded: isExpanded,
                            onTap: () {
                              AppHaptics.heavyImpact();
                              if (isExpanded) widget.onWidthChanged(70.0);
                              setState(() => _isHidden = true);
                              widget.onWidthChanged(48.0);
                            }),
                        const SizedBox(height: 25),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
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
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive
        ? widget.activeColor
        : (widget.isDark ? Colors.white60 : Colors.black54);
    final hoverBgColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.04);

    return Tooltip(
      message: widget.isExpanded ? "" : widget.label,
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
          color: widget.isDark ? Colors.grey[900] : Colors.grey[800],
          borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 52,
              decoration: BoxDecoration(
                  color: _isHovering ? hoverBgColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(12)),
              child: Stack(
                children: [
                  AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      left: 0,
                      top: widget.isActive ? 12 : 26,
                      bottom: widget.isActive ? 12 : 26,
                      width: 4,
                      child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: widget.isActive ? 1.0 : 0.0,
                          child: Container(
                              decoration: BoxDecoration(
                                  color: widget.activeColor,
                                  borderRadius: BorderRadius.circular(4))))),
                  Row(
                    children: [
                      SizedBox(
                          width: 52,
                          child: Center(
                              child: AnimatedScale(
                                  scale: _isHovering ? 1.1 : 1.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(widget.icon,
                                      color: color, size: 26)))),
                      Expanded(
                          child: ClipRect(
                              child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 200),
                                  opacity: widget.isExpanded ? 1.0 : 0.0,
                                  child: Text(widget.label,
                                      style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: widget.isActive
                                              ? FontWeight.bold
                                              : FontWeight.w600,
                                          color: color),
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.fade))))
                    ],
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

class _DesktopPromoDashboard extends StatelessWidget {
  final bool isDark;
  final AppNavigationProvider navProvider;

  const _DesktopPromoDashboard(
      {required this.isDark, required this.navProvider});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
            right: -50,
            top: -50,
            child: Icon(Icons.hub_rounded,
                size: 500, color: Colors.white.withValues(alpha: 0.02))),
        Positioned.fill(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(
                top: 60.0, left: 50.0, right: 50.0, bottom: 60.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text("Navigate Delhi NCR,\nSmarter.",
                    style: GoogleFonts.poppins(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 52,
                        fontWeight: FontWeight.w800,
                        height: 1.1)),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Text(
                      "Your ultimate companion for Metro & Bus routes. Explore live tracking, find accurate fares, and plan seamless journeys instantly.",
                      style: GoogleFonts.inter(
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          height: 1.6)),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    AppHaptics.selectionClick();
                    globalTransportMode.value = 0;
                    globalIsHome.value = false;
                    globalSearchSheetOpen.value = true;
                    navProvider.setTab(0);
                  },
                  icon: const Icon(Icons.map_rounded),
                  label: Text("Plan Journey",
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? Colors.white : Colors.black,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0),
                ),
                const SizedBox(height: 60),
                Wrap(
                  spacing: 24.0,
                  runSpacing: 24.0,
                  children: [
                    _HoverFeatureCard(
                        title: "Metro Network",
                        subtitle:
                            "Interactive map with fares, platforms, and train timings.",
                        icon: Icons.subway_rounded,
                        color: const Color(0xFF00E5FF),
                        isDark: isDark,
                        onTap: () {
                          AppHaptics.lightImpact();
                          globalTransportMode.value = 0;
                          globalIsHome.value = false;
                          globalSearchSheetOpen.value = true;
                          navProvider.setTab(0);
                        }),
                    _HoverFeatureCard(
                        title: "Live Bus Tracking",
                        subtitle:
                            "Real-time DTC bus GPS tracking and route finder.",
                        icon: Icons.directions_bus_filled_rounded,
                        color: const Color(0xFFFF9F0A),
                        isDark: isDark,
                        onTap: () {
                          AppHaptics.lightImpact();
                          globalTransportMode.value = 1;
                          globalIsHome.value = false;
                          globalSearchSheetOpen.value = true;
                          navProvider.setTab(0);
                        }),
                    _HoverFeatureCard(
                        title: "Download App",
                        subtitle:
                            "Get the Ridel app on your phone for AR navigation.",
                        icon: Icons.phone_android_rounded,
                        color: const Color(0xFFB15EFF),
                        isDark: isDark,
                        onTap: () {}),
                  ],
                )
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HoverFeatureCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _HoverFeatureCard(
      {required this.title,
      required this.subtitle,
      required this.icon,
      required this.color,
      required this.isDark,
      required this.onTap});

  @override
  State<_HoverFeatureCard> createState() => _HoverFeatureCardState();
}

class _HoverFeatureCardState extends State<_HoverFeatureCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: 320,
          transform: Matrix4.translationValues(0, _isHovering ? -8.0 : 0, 0),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: widget.isDark
                ? (_isHovering
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFF151515))
                : (_isHovering ? Colors.white : const Color(0xFFF5F5F7)),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: widget.isDark
                    ? (_isHovering
                        ? widget.color.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.04))
                    : (_isHovering
                        ? widget.color.withValues(alpha: 0.3)
                        : Colors.black.withValues(alpha: 0.05))),
            boxShadow: _isHovering
                ? [
                    BoxShadow(
                        color: widget.color.withValues(alpha: 0.15),
                        blurRadius: 30,
                        offset: const Offset(0, 10))
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16)),
                  child: Icon(widget.icon, color: widget.color, size: 28)),
              const SizedBox(height: 24),
              Text(widget.title,
                  style: GoogleFonts.inter(
                      color: widget.isDark ? Colors.white : Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(widget.subtitle,
                  style: GoogleFonts.inter(
                      color: widget.isDark ? Colors.white54 : Colors.black54,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      height: 1.5)),
            ],
          ),
        ),
      ),
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
