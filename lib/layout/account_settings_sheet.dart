import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/map/map_style_helper.dart';
import 'package:ridel/core/services/theme_service.dart';
import 'package:ridel/core/theme/app_theme.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/features/auth/services/auth_service.dart';
import 'package:ridel/features/auth/widgets/auth_dialog.dart';

void openAccountSettings(BuildContext context) {
  AppHaptics.lightImpact();
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) {
    showRidelAuthDialog(context);
  } else {
    RidelSheet.show(
      context,
      title: "Account & Settings",
      showCloseButton: true,
      child: const AccountSettingsSheet(),
    );
  }
}

class AccountSettingsSheet extends StatelessWidget {
  const AccountSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mapProvider = context.watch<MapProvider>();
    final accent =
        isDark ? RidelSurfaceTokens.iosBlueDark : RidelSurfaceTokens.iosBlueLight;
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.black.withValues(alpha: 0.03);
    final border = RidelSurfaceTokens.border(isDark);
    final divider = RidelSurfaceTokens.divider(isDark);
    final primaryText = isDark ? Colors.white : const Color(0xFF111318);
    final secondaryText = isDark ? Colors.white54 : const Color(0xFF6B7280);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. PROFILE CARD
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border, width: 0.75),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: accent.withValues(alpha: 0.16),
                  child: Icon(Icons.person_rounded, size: 26, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.userMetadata?['full_name'] ?? 'Explorer',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: primaryText,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user?.email ?? '',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: secondaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),
          _sectionLabel('APPEARANCE & MAP', secondaryText),
          const SizedBox(height: 8),

          // 2. APPEARANCE & MAP CONTROLS CARD
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border, width: 0.75),
            ),
            child: Column(
              children: [
                _switchRow(
                  icon: isDark
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  iconColor:
                      isDark ? const Color(0xFFFFD60A) : const Color(0xFFF59E0B),
                  title: 'Dark Mode',
                  value: isDark,
                  accent: accent,
                  primaryText: primaryText,
                  onChanged: (_) {
                    AppHaptics.selectionClick();
                    ThemeService.toggleTheme();
                  },
                ),
                _hairline(divider),
                // Map Style Segmented Selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.layers_rounded, size: 19, color: accent),
                          const SizedBox(width: 12),
                          Text(
                            'Map Style',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: primaryText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _styleChip(
                            label: 'Light',
                            selected:
                                mapProvider.currentTheme == MapThemeType.light,
                            accent: accent,
                            isDark: isDark,
                            onTap: () {
                              AppHaptics.selectionClick();
                              mapProvider.setTheme(MapThemeType.light);
                            },
                          ),
                          const SizedBox(width: 8),
                          _styleChip(
                            label: 'Dark',
                            selected:
                                mapProvider.currentTheme == MapThemeType.dark,
                            accent: accent,
                            isDark: isDark,
                            onTap: () {
                              AppHaptics.selectionClick();
                              mapProvider.setTheme(MapThemeType.dark);
                            },
                          ),
                          const SizedBox(width: 8),
                          _styleChip(
                            label: 'Satellite',
                            selected: mapProvider.currentTheme ==
                                MapThemeType.satellite,
                            accent: accent,
                            isDark: isDark,
                            onTap: () {
                              AppHaptics.selectionClick();
                              mapProvider.setTheme(MapThemeType.satellite);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _hairline(divider),
                _switchRow(
                  icon: Icons.view_in_ar_rounded,
                  iconColor: accent,
                  title: '3D Buildings',
                  value: mapProvider.is3DMode,
                  accent: accent,
                  primaryText: primaryText,
                  onChanged: (_) {
                    AppHaptics.selectionClick();
                    mapProvider.toggle3DView();
                  },
                ),
                _hairline(divider),
                _switchRow(
                  icon: Icons.label_outline_rounded,
                  iconColor: const Color(0xFF30D158),
                  title: 'Map Labels',
                  value: mapProvider.showLabels,
                  accent: accent,
                  primaryText: primaryText,
                  onChanged: (val) {
                    AppHaptics.selectionClick();
                    mapProvider.toggleLabels(val);
                  },
                ),
                _hairline(divider),
                _switchRow(
                  icon: Icons.storefront_rounded,
                  iconColor: const Color(0xFFFF9500),
                  title: 'Show Nearby POIs',
                  value: mapProvider.showPOIs,
                  accent: accent,
                  primaryText: primaryText,
                  onChanged: (val) {
                    AppHaptics.selectionClick();
                    mapProvider.togglePOIs(val);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),
          _sectionLabel('EXPERIENCE & PRIVACY', secondaryText),
          const SizedBox(height: 8),

          // 3. EXPERIENCE & PRIVACY CARD
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border, width: 0.75),
            ),
            child: Column(
              children: [
                ValueListenableBuilder<HapticLevel>(
                  valueListenable: AppHaptics.hapticLevel,
                  builder: (context, level, _) {
                    final enabled = level != HapticLevel.off;
                    return _switchRow(
                      icon: Icons.vibration_rounded,
                      iconColor: const Color(0xFFBF5AF2),
                      title: 'Haptic Feedback',
                      value: enabled,
                      accent: accent,
                      primaryText: primaryText,
                      onChanged: (val) {
                        AppHaptics.setLevel(
                            val ? HapticLevel.medium : HapticLevel.off);
                        if (val) AppHaptics.selectionClick();
                      },
                    );
                  },
                ),
                _hairline(divider),
                InkWell(
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(20)),
                  onTap: () async {
                    AppHaptics.lightImpact();
                    mapProvider.recentSearches.clear();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('recent_searches');
                    if (context.mounted) {
                      ToastService.showSuccess(
                          context, 'Search history cleared');
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline_rounded,
                            size: 19, color: Color(0xFFFF453A)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Clear Search History',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: primaryText,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: secondaryText),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 4. SIGN OUT PILL BUTTON
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF453A).withValues(alpha: 0.14),
                foregroundColor: const Color(0xFFFF453A),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: BorderSide(
                    color: const Color(0xFFFF453A).withValues(alpha: 0.30),
                    width: 0.75,
                  ),
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
              icon: const Icon(Icons.logout_rounded, size: 19),
              label: Text(
                'Sign Out',
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
            color: color,
          ),
        ),
      );

  Widget _hairline(Color color) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(height: 0.5, color: color),
      );

  Widget _switchRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required bool value,
    required Color accent,
    required Color primaryText,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 19, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: primaryText,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _styleChip({
    required String label,
    required bool selected,
    required Color accent,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? accent
                : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected
                  ? Colors.white
                  : (isDark ? Colors.white70 : const Color(0xFF374151)),
            ),
          ),
        ),
      ),
    );
  }
}
