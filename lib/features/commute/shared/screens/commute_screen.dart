import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/widgets/app_header.dart';

import 'package:ridel/features/commute/shared/widgets/commute_search_card.dart';
import 'package:ridel/features/commute/metro/widgets/metro_services_grid.dart';
import 'package:ridel/features/commute/bus/widgets/bus_services_grid.dart';

class CommuteScreen extends StatefulWidget {
  const CommuteScreen({super.key});

  @override
  State<CommuteScreen> createState() => _CommuteScreenState();
}

class _CommuteScreenState extends State<CommuteScreen> {
  // 0 = Metro, 1 = Bus
  int _selectedMode = 0; 

  Color get _accentColor => _selectedMode == 0 ? const Color(0xFF00E5FF) : const Color(0xFFFF9F0A);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      resizeToAvoidBottomInset: true, 
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),

              // 1. HEADER
              AppHeader(
                showProfile: false, 
                actionWidget: _buildPremiumToggle(isDark), 
              ),

              const SizedBox(height: 25),

              // 2. SEARCH CARD
              CommuteSearchCard(
                isDark: isDark, 
                selectedMode: _selectedMode
              ),

              const SizedBox(height: 35),
              
              // 3. DYNAMIC SERVICE GRID (Duplicate Text Removed!)
              _selectedMode == 0 
                  ? const MetroServicesGrid()
                  : const BusServicesGrid(),

              const SizedBox(height: 100), 
            ],
          ),
        ),
      ),
    );
  }

  // TOGGLE SWITCH (Top Right)
  Widget _buildPremiumToggle(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      height: 44, 
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleItem("Metro", 0, isDark),
          _toggleItem("Bus", 1, isDark),
        ],
      ),
    );
  }

  Widget _toggleItem(String label, int index, bool isDark) {
    bool isSelected = _selectedMode == index;
    return GestureDetector(
      onTap: () {
        AppHaptics.selectionClick();
        setState(() => _selectedMode = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? _accentColor.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(100), // Capsule click effect
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? _accentColor : Colors.grey, 
            fontWeight: FontWeight.bold, 
            fontSize: 13
          ),
        ),
      ),
    );
  }
}