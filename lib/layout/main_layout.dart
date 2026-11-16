import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/profile_repository.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/features/map/screens/full_screen_map.dart';
import 'package:ridel/layout/desktop_map_sidebar.dart';
import 'package:ridel/main.dart';
import 'package:ridel/core/utils/responsive.dart';
import 'package:ridel/core/theme/app_theme.dart';
import 'package:ridel/core/widgets/adaptive_blur.dart';

export 'package:ridel/layout/account_settings_sheet.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final ValueNotifier<double> _searchSheetProgressNotifier = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWelcomeFlow();
      _checkAndTriggerColdBootLocation();
    });
  }

  Future<void> _checkAndTriggerColdBootLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        if (mounted) {
          Provider.of<GlobalLocationService>(context, listen: false)
              .autoDetectAndSetRegion();
        }
      }
    } catch (e) {
      debugPrint("Cold boot location error: $e");
    }
  }

  Future<void> _handleWelcomeFlow() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final profile = await ProfileRepository().getProfile();
      if (mounted) {
        final String fullName = profile?['full_name'] ??
            user.userMetadata?['full_name'] ??
            'Explorer';
        final String firstName = fullName.split(' ')[0];

        AppHaptics.success();
        ToastService.showSuccess(context,
            'Welcome back, $firstName! 🚗 Ready for your next journey?');
      }
    }
  }

  @override
  void dispose() {
    _searchSheetProgressNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isDesktop = ResponsiveLayout.isDesktop(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // 🚀 1. FULL SCREEN INTERACTIVE MAP (ALWAYS INTERACTIVE, ZERO IGNOREPOINTER)
            Positioned.fill(
              child: FullScreenMapPage(
                searchSheetProgressNotifier: _searchSheetProgressNotifier,
                isMapTabActive: true,
              ),
            ),

            // 🚀 2. DESKTOP MODE: FLOATING SLIDING SIDEBAR
            if (isDesktop)
              ValueListenableBuilder<bool>(
                valueListenable: globalSidebarOpen,
                builder: (context, isOpen, _) {
                  return Stack(
                    children: [
                      // Floating "Restore Sidebar" button when sidebar is collapsed
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        top: 24,
                        left: isOpen ? -180 : 24,
                        child: _buildRestoreSidebarButton(isDark),
                      ),

                      // Desktop Sidebar container
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        top: 20,
                        left: isOpen ? 20 : -420,
                        child: DesktopMapSidebar(
                          onCollapse: () {
                            globalSidebarOpen.value = false;
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),

          ],
        ),
      ),
    );
  }

  Widget _buildRestoreSidebarButton(bool isDark) {
    final button = GestureDetector(
      onTap: () {
        AppHaptics.selectionClick();
        globalSidebarOpen.value = true;
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: RidelSurfaceTokens.pillShadows(isDark),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: AdaptiveBlur(
            sigmaX: 14.0,
            sigmaY: 14.0,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: RidelSurfaceTokens.pillBackground(isDark, elevated: true),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: RidelSurfaceTokens.border(isDark),
                  width: 0.75,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.menu_rounded,
                    size: 18,
                    color: isDark
                        ? RidelSurfaceTokens.iosBlueDark
                        : RidelSurfaceTokens.iosBlueLight,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Ridel Maps',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF111318),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return kIsWeb ? PointerInterceptor(child: button) : button;
  }
}
