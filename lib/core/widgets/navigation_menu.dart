import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';

// ✅ FIXED IMPORTS (Feature-First Architecture)
import 'package:ridel/features/home/screens/home_screen.dart';
import 'package:ridel/features/metro/screens/select_screen.dart';
import 'package:ridel/features/tour/screens/tour_screen.dart';
import 'package:ridel/features/bus/screens/bus_screen.dart';
import 'package:ridel/features/profile/screens/profile_screen.dart';
import 'package:ridel/core/utils/app_haptics.dart'; // Agar haptics use ho raha ho

class NavigationMenu extends StatefulWidget {
  const NavigationMenu({super.key});

  @override
  State<NavigationMenu> createState() => _NavigationMenuState();
}


class _NavigationMenuState extends State<NavigationMenu> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  
  // ✅ Screens ko memory mein rakhne ke liye list (IndexedStack ke liye)
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(onNavigateToTab: _navigateToTab), // 0
      const SelectScreen(),                        // 1
      const TourScreen(),                          // 2
      const BusScreen(),                           // 3
      const ProfileScreen(),                       // 4
    ];
  }

  void _navigateToTab(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  void _onNavItemTap(int index) {
    if (_currentIndex == index) return;
    HapticFeedback.lightImpact(); 
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    // Safe area bottom padding (iPhone home bar ke liye)
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true, // Content bar ke piche jayega
      body: Stack(
        children: [
          // 1. Screen Content (IndexedStack = No Lag/Reloading)
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),

          // 2. ✅ OLD STYLE GLASS BAR (Full Width, 0.2 Opacity)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRect( // ClipRect jaruri hai taaki blur bahar na faile
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0), // Smooth Glass Blur
                child: Container(
                  height: 55 + bottomPadding, // Height 55 as requested
                  padding: EdgeInsets.only(bottom: bottomPadding),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2), // ✅ 0.2 Opacity (Transparent)
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1), // Subtle Top Border
                        width: 0.5
                      )
                    )
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(child: _buildNavItem(Icons.home_rounded, Icons.home_outlined, 0)),
                      Expanded(child: _buildNavItem(Icons.directions_subway_filled_rounded, Icons.directions_subway_outlined, 1)),
                      Expanded(child: _buildNavItem(Icons.explore_rounded, Icons.explore_outlined, 2)),
                      Expanded(child: _buildNavItem(Icons.directions_bus_rounded, Icons.directions_bus_outlined, 3)),
                      Expanded(child: _buildNavItem(Icons.person_rounded, Icons.person_outline_rounded, 4)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData activeIcon, IconData inactiveIcon, int index) {
    final isSelected = _currentIndex == index;
    
    return GestureDetector(
      onTap: () => _onNavItemTap(index),
      behavior: HitTestBehavior.opaque, 
      child: SizedBox(
        height: 55, 
        width: 60, // Touch target
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: Icon(
              isSelected ? activeIcon : inactiveIcon, 
              key: ValueKey(isSelected),
              // Selected: Neon Cyan, Unselected: White 0.5 opacity
              color: isSelected ? const Color(0xFF00E5FF) : Colors.white.withValues(alpha: 0.5), 
              size: 26, 
            ),
          ),
        ),
      ),
    );
  }
}