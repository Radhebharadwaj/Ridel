import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';

class BusServicesGrid extends StatelessWidget {
  const BusServicesGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    const busAccentColor = Color(0xFFFF9F0A); // Bus Orange Color

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSquareAction(context, Icons.directions_bus_rounded, "Route\nFinder", cardColor, textColor, accentColor: busAccentColor),
          _buildSquareAction(context, Icons.sensors_rounded, "Live\nStatus", cardColor, textColor, accentColor: busAccentColor),
          _buildSquareAction(context, Icons.confirmation_number_rounded, "Buy\nTicket", cardColor, textColor, accentColor: busAccentColor),
        ],
      ),
    );
  }

  Widget _buildSquareAction(BuildContext context, IconData icon, String label, Color bg, Color textColor, {VoidCallback? onTap, required Color accentColor}) {
    return GestureDetector(
      onTap: () {
        AppHaptics.lightImpact();
        if (onTap != null) onTap();
      },
      child: Container(
        width: 85,
        height: 110,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: accentColor),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: textColor, height: 1.2),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}