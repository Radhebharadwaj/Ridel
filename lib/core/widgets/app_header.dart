import 'dart:async';
import 'package:ridel/main.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/notification_service.dart';

import 'package:ridel/core/widgets/notification_sheet.dart';

import 'package:permission_handler/permission_handler.dart';
import '../../features/profile/services/profile_repository.dart';
import '../utils/app_haptics.dart';
import 'city_selector_sheet.dart';
import 'ridel_glass_dropdown.dart';
import 'ridel_sheet.dart';

import 'package:ridel/features/admin/admin_broadcast_screen.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart';

class AppHeader extends StatefulWidget {
  final Widget? leadingWidget;
  final Widget? actionWidget;
  final bool showProfile;
  final bool isScrolled;
  final bool isRouteMode;
  final VoidCallback? onBack;

  const AppHeader({
    super.key,
    this.leadingWidget,
    this.actionWidget,
    this.showProfile = true,
    this.isScrolled = false,
    this.isRouteMode = false,
    this.onBack,
  });

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  final ProfileRepository _repo = ProfileRepository();

  String _notificationMode = 'Active';
  final List<String> _notifOptions = [
    'Active',
    'Mute Notifications',
    'Turn Off'
  ];

  double _headerScale = 1.0;
  bool _isRouteModeActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
      if (widget.isRouteMode) {
        setState(() => _isRouteModeActive = true);
        _triggerSqueezeAnimation();
      }
    });
  }

  @override
  void didUpdateWidget(AppHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRouteMode != oldWidget.isRouteMode) {
      setState(() => _isRouteModeActive = widget.isRouteMode);
      _triggerSqueezeAnimation();
    }
  }

  void _triggerSqueezeAnimation() {
    setState(() => _headerScale = 0.92);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() => _headerScale = 1.0);
      }
    });
  }

  void _handleBackTap() {
    if (widget.isRouteMode && widget.onBack != null) {
      AppHaptics.lightImpact();
      _triggerSqueezeAnimation();
      setState(() => _isRouteModeActive = false);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          widget.onBack!();
        }
      });
    }
  }

  Future<void> _initLocation() async {
    try {
      await _repo.getProfile();
      String current = ProfileRepository.userCity.value;
      
      bool isGranted = await Permission.location.isGranted;

      if (isGranted) {
        if (current.isEmpty || current == "Select City" || current == "Location Disabled") {
           ProfileRepository.userCity.value = "Locating...";
        }
        
        if (!mounted) return;
        final locationService =
            Provider.of<GlobalLocationService>(context, listen: false);
        await locationService.initializeEcoLocation(isManualTrigger: false);
      }
    } catch (e) {
      debugPrint('Error initializing location: $e');
    }
  }



  void _openCitySelector() {
    AppHaptics.lightImpact();
    CitySelectorSheet.show(context);
  }

  void _showNotificationSettings() {
    AppHaptics.heavyImpact();
    RidelGlassDropdown.show(context,
        options: _notifOptions,
        selectedValue: _notificationMode, onSelected: (val) {
      setState(() => _notificationMode = val);
      AppHaptics.lightImpact();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    final double topInset = MediaQuery.of(context).padding.top;
    final double headerPadding = widget.isScrolled ? 10 : 20;

    IconData bellIcon = Icons.notifications_rounded;
    Color bellColor = isDark ? Colors.white70 : Colors.black87;

    if (_notificationMode == 'Mute Notifications') {
      bellIcon = Icons.notifications_paused_rounded;
      bellColor = Colors.orangeAccent;
    } else if (_notificationMode == 'Turn Off') {
      bellIcon = Icons.notifications_off_rounded;
      bellColor = isDark ? Colors.white24 : Colors.black26;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: EdgeInsets.only(
        top: topInset + headerPadding,
        bottom: 16,
        left: 8.0, // tighter left alignment
        right: 24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            bgColor.withValues(alpha: widget.isScrolled ? 1.0 : 0.0),
            bgColor.withValues(alpha: widget.isScrolled ? 0.95 : 0.0),
            bgColor.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
        boxShadow: widget.isScrolled
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Consumer<GlobalLocationService>(
              builder: (context, locService, child) {
                String cityName = locService.currentCityName.value;
                String displayCity =
                    cityName.isNotEmpty ? cityName : "Detecting...";

                displayCity = displayCity.split(' ').map((word) {
                  return word.isEmpty
                      ? ""
                      : word[0].toUpperCase() + word.substring(1).toLowerCase();
                }).join(' ');

                final displayTitle = displayCity;
                final isFake = cityName == "Fake GPS Detected" || cityName == "Location Disabled";

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  reverseDuration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutBack,
                  layoutBuilder:
                      (Widget? currentChild, List<Widget> previousChildren) {
                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: <Widget>[
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.9, end: 1.0)
                            .animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: widget.isScrolled
                      ? Align(
                          alignment: Alignment.centerLeft,
                          key: const ValueKey("scrolled_pill"),
                          child: RidelLiquidButton(
                            width: 140,
                            height: 38,
                            glassTint: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                            onTap: _openCitySelector,
                            child: Text(
                              displayTitle,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        )
                      : Row(
                          key: const ValueKey("normal_title"),
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 1. BACK BUTTON (Tightened & Left-Aligned)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 450),
                              curve: Curves.fastOutSlowIn,
                              width: _isRouteModeActive ? 40.0 : 0.0,
                              child: ClipRect(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: 1.0,
                                  child: GestureDetector(
                                    onTap: _isRouteModeActive
                                        ? _handleBackTap
                                        : null,
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      width: 40.0,
                                      height: 48.0,
                                      color: Colors.transparent,
                                      alignment: Alignment.centerLeft,
                                      child: Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        size: 24,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // 2. TIGHT SPACING
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 450),
                              curve: Curves.fastOutSlowIn,
                              width: _isRouteModeActive ? 4.0 : 0.0,
                            ),

                            // 3. MAIN TITLE (locked in original position)
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: AnimatedScale(
                                  duration: const Duration(milliseconds: 450),
                                  scale: _headerScale,
                                  curve: Curves.fastOutSlowIn,
                                  child: GestureDetector(
                                    onTap: _openCitySelector,
                                    onLongPress: () {
                                      AppHaptics.heavyImpact();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const AdminBroadcastScreen(),
                                        ),
                                      );
                                    },
                                    behavior: HitTestBehavior.opaque,
                                    child: AnimatedSize(
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeInOutBack,
                                      alignment: Alignment.centerLeft,
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 300),
                                        layoutBuilder: (currentChild, previousChildren) => Stack(
                                          alignment: Alignment.centerLeft,
                                          children: [...previousChildren, if (currentChild != null) currentChild],
                                        ),
                                        child: Row(
                                          key: ValueKey<String>(displayTitle),
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isFake)
                                              const Padding(
                                                padding: EdgeInsets.only(right: 6.0),
                                                child: Icon(Icons.location_off_rounded, color: Colors.redAccent, size: 24),
                                              ),
                                            Flexible(
                                              child: Text(
                                                displayTitle,
                                                textAlign: TextAlign.left,
                                                style: GoogleFonts.inter(
                                                  fontSize: isFake ? 22 : 32,
                                                  fontWeight: FontWeight.w800,
                                                  color: textColor,
                                                  letterSpacing: -1.0,
                                                  height: 1.0,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(Icons.keyboard_arrow_down, color: isDark ? Colors.white54 : Colors.black54, size: 22),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.actionWidget != null) ...[
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.fastOutSlowIn,
                      opacity: _isRouteModeActive ? 1.0 : 0.0,
                      child: widget.actionWidget!,
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (widget.showProfile)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: _showNotificationSettings,
                      child: RidelBounceButton(
                        scaleFactor: 0.88,
                        onTap: () {
                          RidelSheet.show(
                            context,
                            title: "Notifications",
                            showCloseButton: true,
                            child: const NotificationSheetContent(),
                          );
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          color: Colors.transparent,
                          alignment: Alignment.centerRight,
                          child:
                              ValueListenableBuilder<List<RidelNotification>>(
                            valueListenable:
                                NotificationService().notificationsNotifier,
                            builder: (context, notifs, child) {
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(bellIcon, color: bellColor, size: 28),
                                  if (NotificationService()
                                          .hasUnreadNotifications() &&
                                      _notificationMode == 'Active')
                                    Positioned(
                                      top: 2,
                                      right: -2,
                                      child: ValueListenableBuilder<int>(
                                        valueListenable: globalTransportMode,
                                        builder: (context, transportMode, _) {
                                          final Color activeAccent =
                                              transportMode == 1
                                                  ? const Color(0xFFFF9F0A)
                                                  : CupertinoColors.systemBlue;
                                          return Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: activeAccent,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                  color: bgColor, width: 2.0),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: activeAccent
                                                      .withValues(alpha: 0.5),
                                                  blurRadius: 6,
                                                )
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    )
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
