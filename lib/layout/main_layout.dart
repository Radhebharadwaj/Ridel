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
import 'package:ridel/core/services/theme_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/widgets/ridel_glass.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/features/auth/services/auth_service.dart';
import 'package:ridel/features/auth/widgets/auth_dialog.dart';
import 'package:ridel/features/map/screens/full_screen_map.dart';
import 'package:ridel/layout/desktop_map_sidebar.dart';
import 'package:ridel/main.dart';

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

  void _openAccountSheet() {
    AppHaptics.lightImpact();
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      showRidelAuthDialog(context);
    } else {
      RidelSheet.show(
        context,
        title: "Account",
        showCloseButton: true,
        child: const AccountSettingsSheet(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isDesktop = MediaQuery.of(context).size.width >= 768;
    final topPadding = MediaQuery.of(context).padding.top;

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

            // 🚀 3. MOBILE MODE: FLOATING ACCOUNT / PROFILE BUTTON (Top Right)
            if (!isDesktop)
              Positioned(
                top: topPadding + 16.0,
                right: 16.0,
                child: ValueListenableBuilder<double>(
                  valueListenable: _searchSheetProgressNotifier,
                  builder: (context, progress, child) {
                    double opacity = (progress <= 0.45)
                        ? 1.0
                        : (1.0 - ((progress - 0.45) / (0.90 - 0.45)))
                            .clamp(0.0, 1.0);

                    return IgnorePointer(
                      ignoring: opacity == 0.0,
                      child: Opacity(
                        opacity: opacity,
                        child: child,
                      ),
                    );
                  },
                  child: _buildMobileAccountButton(isDark),
                ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF161922).withValues(alpha: 0.90)
              : Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_rounded, size: 20, color: Color(0xFF00E5FF)),
            const SizedBox(width: 8),
            Text(
              'Ridel Maps',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );

    return kIsWeb ? PointerInterceptor(child: button) : button;
  }

  Widget _buildMobileAccountButton(bool isDark) {
    final button = GestureDetector(
      onTap: _openAccountSheet,
      child: SizedBox(
        width: 44,
        height: 44,
        child: RidelGlass(
          borderRadius: BorderRadius.circular(50),
          baseColor: isDark
              ? const Color(0xFF1C1C1E).withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.90),
          blurSigma: 20.0,
          child: Center(
            child: Icon(
              Icons.person_outline_rounded,
              color: isDark ? Colors.white : Colors.black87,
              size: 22,
            ),
          ),
        ),
      ),
    );

    return kIsWeb ? PointerInterceptor(child: button) : button;
  }
}

class AccountSettingsSheet extends StatelessWidget {
  const AccountSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: isDark
                    ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                    : const Color(0xFF007AFF).withValues(alpha: 0.12),
                child: const Icon(
                  Icons.person_rounded,
                  size: 28,
                  color: Color(0xFF00E5FF),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.userMetadata?['full_name'] ?? 'Explorer',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          const SizedBox(height: 8),

          // Theme switch tile
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: isDark ? Colors.amberAccent : Colors.orange,
              size: 24,
            ),
            title: Text(
              'Dark Mode',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            trailing: Switch.adaptive(
              value: isDark,
              activeColor: const Color(0xFF00E5FF),
              onChanged: (val) {
                AppHaptics.selectionClick();
                ThemeService.toggleTheme();
              },
            ),
          ),
          const SizedBox(height: 16),

          // Sign Out Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withValues(alpha: 0.12),
              foregroundColor: Colors.redAccent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
            ),
            onPressed: () async {
              AppHaptics.heavyImpact();
              Navigator.pop(context);
              await AuthService().signOut();
              if (context.mounted) {
                ToastService.showSuccess(context, 'Signed out');
              }
            },
            icon: const Icon(Icons.logout_rounded, size: 20),
            label: Text(
              'Sign Out',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
