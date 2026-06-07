// lib/core/widgets/app_gate_overlay.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ridel/core/services/app_config_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/widgets/ridel_logo.dart';

// ======================================================================
// 🚧 AppGateOverlay — Non-dismissible glassmorphism enforcement modal
// Blocks app usage when update is required or maintenance is active.
// ======================================================================
class AppGateOverlay extends StatefulWidget {
  final Widget child;

  const AppGateOverlay({super.key, required this.child});

  @override
  State<AppGateOverlay> createState() => _AppGateOverlayState();
}

class _AppGateOverlayState extends State<AppGateOverlay>
    with SingleTickerProviderStateMixin {
  AppStatus _status = AppStatus.normal;
  bool _isChecking = true;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final status = await AppConfigService().checkAppStatus();
    if (mounted) {
      setState(() {
        _status = status;
        _isChecking = false;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 🟢 Actual app content underneath
        widget.child,

        // 🚧 Enforcement overlay when blocked
        if (!_isChecking && _status != AppStatus.normal)
          _buildGateModal(context),
      ],
    );
  }

  Widget _buildGateModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMaintenance = _status == AppStatus.maintenance;

    // 🎨 Dynamic color palette based on status
    final accentColor =
        isMaintenance ? const Color(0xFFFFD60A) : const Color(0xFF0A84FF);
    final accentGlow = accentColor.withValues(alpha: 0.3);

    final configService = AppConfigService();
    final maintenanceMsg = configService.maintenanceMessage ??
        'We\'re performing scheduled maintenance. We\'ll be back shortly.';

    return PopScope(
      canPop: false, // 🛑 Block hardware back button
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // 🌫️ Heavy frosted glass backdrop — fully blocks interaction
            Positioned.fill(
              child: GestureDetector(
                onTap: () {}, // Absorb taps
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    color: isDark
                        ? const Color(0xFF0B0E17).withValues(alpha: 0.92)
                        : Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ),
            ),

            // 🎯 Center modal card
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.85, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (context, scale, child) {
                  return Transform.scale(scale: scale, child: child);
                },
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, opacity, child) {
                    return Opacity(opacity: opacity, child: child);
                  },
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.88,
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: accentGlow,
                          blurRadius: 60,
                          spreadRadius: -10,
                          offset: const Offset(0, 20),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 36),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(32),
                            color: isDark
                                ? const Color(0xFF1A1D28)
                                    .withValues(alpha: 0.8)
                                : Colors.white.withValues(alpha: 0.85),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : Colors.black.withValues(alpha: 0.06),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 🎯 Pulsing icon
                              AnimatedBuilder(
                                animation: _pulseAnimation,
                                builder: (context, child) {
                                  return Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          accentColor.withValues(
                                              alpha: 0.15 *
                                                  _pulseAnimation.value),
                                          accentColor.withValues(alpha: 0.0),
                                        ],
                                        radius: 1.2,
                                      ),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 56,
                                        height: 56,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: accentColor
                                              .withValues(alpha: 0.12),
                                        ),
                                        child: Icon(
                                          isMaintenance
                                              ? Icons.construction_rounded
                                              : Icons.system_update_rounded,
                                          color: accentColor,
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 24),

                              // 🏷️ Title
                              Text(
                                isMaintenance
                                    ? 'Under Maintenance'
                                    : 'Update Required',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),

                              const SizedBox(height: 12),

                              // 📄 Description
                              Text(
                                isMaintenance
                                    ? maintenanceMsg
                                    : 'A new version of Ridel is available with critical improvements. Please update to continue using the app.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w400,
                                  height: 1.5,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.6)
                                      : Colors.black54,
                                ),
                              ),

                              const SizedBox(height: 8),

                              // 🔢 Version info badge (update only)
                              if (!isMaintenance &&
                                  AppConfigService().latestVersion != null)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(100),
                                    color: accentColor.withValues(alpha: 0.1),
                                    border: Border.all(
                                      color: accentColor.withValues(alpha: 0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    'v${AppConfigService().latestVersion} available',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: accentColor,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),

                              const SizedBox(height: 28),

                              // 🚀 Primary action button
                              if (!isMaintenance) _buildUpdateButton(context),

                              if (isMaintenance) _buildMaintenanceInfo(context),

                              const SizedBox(height: 16),

                              // 🏷️ Branding footer
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  RidelLogo(
                                    size: 16,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.25)
                                        : Colors.black26,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Ridel',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                              .withValues(alpha: 0.25)
                                          : Colors.black26,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
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

  Widget _buildUpdateButton(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        AppHaptics.buttonClick();
        // 🚀 Open Play Store / App Store
        const playStoreUrl =
            'https://play.google.com/store/apps/details?id=com.pixra.ridel';
        final uri = Uri.parse(playStoreUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A84FF),
              Color(0xFF007AFF),
              Color(0xFF0066E0),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0A84FF).withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.upgrade_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Update Now',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMaintenanceInfo(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark
            ? const Color(0xFFFFD60A).withValues(alpha: 0.08)
            : const Color(0xFFFFD60A).withValues(alpha: 0.12),
        border: Border.all(
          color: const Color(0xFFFFD60A).withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.access_time_rounded,
            color: const Color(0xFFFFD60A).withValues(alpha: 0.8),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'We\'ll be back online shortly. Thank you for your patience.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.55)
                    : Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
