import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridel/core/services/theme_service.dart';
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
              activeThumbColor: const Color(0xFF00E5FF),
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
