import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'glass_nav_bar.dart';
import '../features/map/widgets/map_search_sheet.dart';
import '../features/home/screens/home_screen.dart';
import '../features/commute/shared/screens/commute_screen.dart';
import '../features/map/screens/full_screen_map.dart';
import '../core/map/map_provider.dart';
import '../core/providers/app_navigation_provider.dart'; 
import '../core/widgets/ridel_sheet.dart';
import '../features/profile/screens/profile_screen.dart';
import '../core/utils/app_haptics.dart';
import '../features/tour/screens/tour_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _isSearchMode = false;

  final List<Widget> _screens = [
    const HomeScreen(),
    const CommuteScreen(),
    const Scaffold(backgroundColor: Color(0xFF0B0E17), body: Center(child: Text("Wallet Screen", style: TextStyle(color: Colors.white54)))), // Wapas purana dummy page
    const FullScreenMapPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0B0E17) : Colors.white;
    final double statusBarHeight = MediaQuery.of(context).padding.top;

    // 🔥 Navigation Provider se current index le rahe hain
    final navProvider = Provider.of<AppNavigationProvider>(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: bgColor,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(
              child: IndexedStack(
                index: navProvider.currentIndex,
                children: _screens,
              ),
            ),

            Positioned.fill(
              child: Offstage(
                offstage: navProvider.currentIndex != 3,
                child: MapSearchSheet(
                  isMapTabActive: navProvider.currentIndex == 3,
                  onSearchModeChanged: (isSearching) {
                    if (_isSearchMode != isSearching) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isSearchMode = isSearching);
                      });
                    }
                  },
                  onSearchSubmitted: (query) {
                    if (navProvider.currentIndex != 3) navProvider.setTab(3);
                    Provider.of<MapProvider>(context, listen: false).searchAndNavigate(query);
                  },
                  onBackToPreviousTab: () {
                    navProvider.goBack();
                  },
                ),
              ),
            ),

            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              bottom: (navProvider.currentIndex == 3 || _isSearchMode) ? -150 : 0,
              left: 0, right: 0,
              child: GlassNavBar(
                currentIndex: navProvider.currentIndex,
                onTabSelected: (index) => navProvider.setTab(index),
                // 🔥 Yahan se profile icon dabane par purani wali bottom sheet khulegi
                onProfileTapped: () {
                  AppHaptics.lightImpact();
                  RidelSheet.show(
                    context,
                    title: "Settings",
                    showCloseButton: true,
                    child: const ProfileSheetContent(),
                  );
                },
              ),
            ),

            Positioned(
              top: 0, left: 0, right: 0,
              child: IgnorePointer(
                child: Container(
                  height: statusBarHeight + 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [const Color(0xFF0B0E17).withOpacity(0.85), const Color(0xFF0B0E17).withOpacity(0.0)],
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
}