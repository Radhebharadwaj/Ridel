import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/cupertino.dart';
import '../utils/app_haptics.dart';

class GetAppSheetContent extends StatelessWidget {
  const GetAppSheetContent({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final cardBgColor = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.03);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 🚀 HEADER TEXT
          Text(
            "Experience AR Navigation",
            style: GoogleFonts.inter(
                color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Scan the QR code below with your phone's camera to download the Ridel app.",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                color: subTextColor, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 30),

          // 🚀 QR CODE PLACEHOLDER (White Rounded Box)
          Container(
            width: 200,
            height: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                      blurRadius: 40,
                      spreadRadius: 10)
                ]),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Icon(Icons.qr_code_2_rounded,
                    size: 120, color: Colors.black87), // Dummy QR Icon
              ),
            ),
          ),
          const SizedBox(height: 30),

          // 🚀 APP STORE & PLAY STORE BUTTONS
          Row(
            children: [
              Expanded(
                  child: _buildStoreButton(
                      "App Store", Icons.apple_rounded, isDark)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildStoreButton(
                      "Google Play", Icons.android_rounded, isDark)),
            ],
          ),
          const SizedBox(height: 40),

          // 🚀 ECOSYSTEM SECTION
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Explore Our Ecosystem",
              style: GoogleFonts.inter(
                  color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),

          // ECOSYSTEM CARD 1
          _buildEcosystemCard(
            title: "Project Alpha",
            subtitle: "Next-Gen AI Assistant",
            icon: CupertinoIcons.sparkles,
            iconColor: const Color(0xFFB15EFF),
            cardBgColor: cardBgColor,
            borderColor: borderColor,
            textColor: textColor,
            subTextColor: subTextColor,
          ),
          const SizedBox(height: 12),

          // ECOSYSTEM CARD 2
          _buildEcosystemCard(
            title: "Ridel Driver",
            subtitle: "Partner app for transit operators",
            icon: Icons.directions_bus_rounded,
            iconColor: const Color(0xFFFF9F0A),
            cardBgColor: cardBgColor,
            borderColor: borderColor,
            textColor: textColor,
            subTextColor: subTextColor,
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildStoreButton(String title, IconData icon, bool isDark) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => AppHaptics.selectionClick(),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEcosystemCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color cardBgColor,
    required Color borderColor,
    required Color textColor,
    required Color subTextColor,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => AppHaptics.lightImpact(),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.inter(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: GoogleFonts.inter(
                            color: subTextColor, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  color: subTextColor.withValues(alpha: 0.5), size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
