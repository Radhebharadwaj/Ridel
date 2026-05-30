import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/notification_service.dart';
import 'package:ridel/core/services/place_service.dart';
import 'package:ridel/core/widgets/notification_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/profile/services/profile_repository.dart';
import '../utils/app_haptics.dart';
import 'city_selector_sheet.dart';
import 'ridel_glass_dropdown.dart';
import 'ridel_sheet.dart';

import 'package:ridel/core/utils/ridel_bounce_button.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart';

class AppHeader extends StatefulWidget {
  final Widget? actionWidget;
  final bool showProfile;
  final bool isScrolled;

  const AppHeader({
    super.key,
    this.actionWidget,
    this.showProfile = true,
    this.isScrolled = false,
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
    });
  }

  Future<void> _initLocation() async {
    try {
      await _repo.getProfile();
      String current = ProfileRepository.userCity.value;
      if (current == "Locating..." ||
          current == "Select City" ||
          current.isEmpty ||
          current == "Detecting...") {
        _detectAndSaveRealLocation();
      }
    } catch (e) {
      debugPrint('Error initializing location: $e');
    }
  }

  Future<void> _detectAndSaveRealLocation() async {
    try {
      final locationService =
          Provider.of<GlobalLocationService>(context, listen: false);

      if (!locationService.hasValidLocation) {
        ProfileRepository.userCity.value = "Locating...";
        await locationService.initializeEcoLocation();
      }

      final position = locationService.currentPosition;

      if (position != null) {
        final detectedCity = await PlaceService.getCityFromCoordinates(
            position.latitude, position.longitude);

        if (detectedCity != null) {
          ProfileRepository.userCity.value = detectedCity;
          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            await _repo.updateProfile({'current_city': detectedCity});
          }
        }
      }
    } catch (_) {}
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

  String _formatCityName(String name) {
    if (name.isEmpty) return "Select City";
    String clean = name
        .replaceAll(RegExp(r'^New\s+', caseSensitive: false), '')
        .replaceAll(RegExp(r'^West\s+', caseSensitive: false), '')
        .trim();
    if (clean.isEmpty) return "Select City";
    return clean[0].toUpperCase() + clean.substring(1).toLowerCase();
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
        left: 24,
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
            child: ValueListenableBuilder<String>(
              valueListenable: ProfileRepository.userCity,
              builder: (context, cityName, child) {
                final displayTitle = _formatCityName(cityName);
                final isFake = cityName == "Fake GPS Detected";

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  reverseDuration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutBack,
                  // 🚀 FIX: Invalid 'alignment' parameter hata diya.
                  // layoutBuilder ka Stack already left align kar raha hai perfectly!
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
                      : Align(
                          alignment: Alignment.centerLeft,
                          key: const ValueKey("normal_title"),
                          child: GestureDetector(
                            onTap: _openCitySelector,
                            behavior: HitTestBehavior.opaque,
                            child: Text(
                              displayTitle,
                              textAlign: TextAlign.left,
                              style: GoogleFonts.inter(
                                fontSize: isFake ? 22 : 32,
                                fontWeight: FontWeight.w800,
                                color: isFake ? Colors.redAccent : textColor,
                                letterSpacing: -1.0,
                                height: 1.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                );
              },
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.actionWidget != null) widget.actionWidget!,
              if (widget.showProfile && widget.actionWidget == null)
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
                      child: ValueListenableBuilder<List<RidelNotification>>(
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
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00E5FF),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: bgColor, width: 2.0),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF00E5FF)
                                              .withValues(alpha: 0.5),
                                          blurRadius: 6,
                                        )
                                      ],
                                    ),
                                  ),
                                )
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
