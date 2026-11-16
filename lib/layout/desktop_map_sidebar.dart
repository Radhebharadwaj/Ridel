import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/saved_places_service.dart';
import 'package:ridel/core/services/theme_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/features/auth/services/auth_service.dart';
import 'package:ridel/features/auth/widgets/auth_dialog.dart';
import 'package:ridel/features/map/map_engine/map_engine.dart';
import 'package:ridel/features/map/models/place_model.dart';
import 'package:ridel/features/map/services/master_search_service.dart';

class DesktopMapSidebar extends StatefulWidget {
  final VoidCallback onCollapse;

  const DesktopMapSidebar({
    super.key,
    required this.onCollapse,
  });

  @override
  State<DesktopMapSidebar> createState() => _DesktopMapSidebarState();
}

class _DesktopMapSidebarState extends State<DesktopMapSidebar> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final MasterSearchService _searchService = MasterSearchService();

  List<PlaceModel> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounceTimer;

  PlaceModel? _savedHome;
  PlaceModel? _savedWork;
  StreamSubscription<AuthState>? _authSubscription;

  static const Color cyanAccent = Color(0xFF00E5FF);
  static const Color blueAccent = Color(0xFF007AFF);

  final List<Map<String, dynamic>> _quickCategories = const [
    {
      'label': 'Petrol',
      'icon': Icons.local_gas_station_rounded,
      'color': Color(0xFF00E5FF),
      'query': 'Petrol Pump',
    },
    {
      'label': 'Food',
      'icon': Icons.restaurant_rounded,
      'color': Color(0xFFFF9500),
      'query': 'Restaurant Cafe',
    },
    {
      'label': 'Parking',
      'icon': Icons.local_parking_rounded,
      'color': Color(0xFF34C759),
      'query': 'Parking',
    },
    {
      'label': 'Hospitals',
      'icon': Icons.local_hospital_rounded,
      'color': Color(0xFFFF3B30),
      'query': 'Hospital',
    },
    {
      'label': 'EV Station',
      'icon': Icons.ev_station_rounded,
      'color': Color(0xFFA28BFE),
      'query': 'EV Charging',
    },
    {
      'label': 'ATMs',
      'icon': Icons.atm_rounded,
      'color': Color(0xFF007AFF),
      'query': 'ATM Bank',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedPlaces();
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadSavedPlaces() async {
    try {
      final home = await SavedPlacesService.getHome();
      final work = await SavedPlacesService.getWork();
      if (mounted) {
        setState(() {
          _savedHome = home;
          _savedWork = work;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _debounceTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
      return;
    }

    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final locService =
          Provider.of<GlobalLocationService>(context, listen: false);
      final pos = locService.currentPosition;
      final userLatLng =
          pos != null ? LatLng(pos.latitude, pos.longitude) : null;

      final results = await _searchService.searchPlaces(trimmed,
          userLocation: userLatLng);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  void _triggerCategorySearch(String query) {
    AppHaptics.lightImpact();
    _searchCtrl.text = query;
    _onSearchChanged(query);
  }

  Future<void> _selectPlace(PlaceModel place) async {
    AppHaptics.selectionClick();
    _searchFocus.unfocus();

    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    final targetCoords = LatLng(place.latitude, place.longitude);

    mapProvider.saveNewSearch(place);
    mapProvider.setDestinationSelected(true);
    mapProvider.setTargetDestination(targetCoords);
    mapProvider.addNativeDestinationPin(targetCoords);
    mapProvider.engine.setUIState(MapUIState.placeSelected);

    if (mapProvider.controller != null) {
      await mapProvider.controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: targetCoords, zoom: 15.5),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _searchResults = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = Supabase.instance.client.auth.currentUser;
    final screenHeight = MediaQuery.of(context).size.height;

    final containerColor = isDark
        ? const Color(0xFF131722).withValues(alpha: 0.94)
        : Colors.white.withValues(alpha: 0.95);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    final sidebarContent = Container(
      width: 380,
      constraints: BoxConstraints(
        maxHeight: screenHeight - 48,
      ),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
            blurRadius: 36,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. BRAND HEADER WITH THEME TOGGLE & COLLAPSE
              _buildHeader(isDark),

              // 2. SEARCH BOX
              _buildSearchField(isDark),

              // 3. SCROLLABLE BODY
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Active Route Card (if selected)
                      _buildActiveRouteSection(isDark),

                      // Search Results or Default Sections
                      if (_searchResults.isNotEmpty || _isSearching)
                        _buildSearchResultsList(isDark)
                      else ...[
                        const SizedBox(height: 10),
                        _buildCategoriesSection(isDark),
                        const SizedBox(height: 16),
                        _buildSavedPlacesSection(isDark),
                        const SizedBox(height: 14),
                        _buildQuickControlsSection(isDark),
                      ],

                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),

              // 4. FOOTER: USER PROFILE / LOGIN POPUP TRIGGER
              _buildFooter(isDark, user),
            ],
          ),
        ),
      ),
    );

    return kIsWeb ? PointerInterceptor(child: sidebarContent) : sidebarContent;
  }

  // -------------------------------------------------------------------------
  // 1. HEADER (Brand + Theme Toggle + Collapse)
  // -------------------------------------------------------------------------
  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 10),
      child: Row(
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [cyanAccent, blueAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: cyanAccent.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.explore_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            'Ridel Maps',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : Colors.black87,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: cyanAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cyanAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              'LIVE',
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: cyanAccent,
              ),
            ),
          ),
          const Spacer(),

          // 🌙/☀️ LIGHT/DARK THEME TOGGLE (Clean, top-right placement)
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              tooltip: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
              icon: Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                size: 18,
                color: isDark ? Colors.amberAccent : Colors.orange,
              ),
              splashRadius: 16,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
              onPressed: () {
                AppHaptics.selectionClick();
                ThemeService.toggleTheme();
              },
            ),
          ),

          const SizedBox(width: 8),

          // Collapse Sidebar Button
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              tooltip: 'Collapse Sidebar',
              icon: Icon(
                Icons.keyboard_double_arrow_left_rounded,
                color: isDark ? Colors.white70 : Colors.black54,
                size: 19,
              ),
              splashRadius: 16,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
              onPressed: () {
                AppHaptics.selectionClick();
                widget.onCollapse();
              },
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 2. SEARCH BAR
  // -------------------------------------------------------------------------
  Widget _buildSearchField(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          onChanged: _onSearchChanged,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search places, petrol, food...',
            hintStyle: GoogleFonts.inter(
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 20,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.clear_rounded,
                      size: 18,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                    onPressed: () {
                      _searchCtrl.clear();
                      _onSearchChanged('');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 3. EXPLORE NEARBY CATEGORIES
  // -------------------------------------------------------------------------
  Widget _buildCategoriesSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EXPLORE NEARBY',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickCategories.map((cat) {
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _triggerCategorySearch(cat['query'] as String),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(cat['icon'] as IconData,
                        size: 15, color: cat['color'] as Color),
                    const SizedBox(width: 5),
                    Text(
                      cat['label'] as String,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 4. SAVED PLACES (Home / Work)
  // -------------------------------------------------------------------------
  Widget _buildSavedPlacesSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SAVED PLACES',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(height: 8),
        _buildSavedPlaceRow(
          isDark: isDark,
          title: 'Home',
          subtitle: _savedHome?.name ?? 'Tap to search & set',
          icon: Icons.home_rounded,
          iconColor: const Color(0xFF00E5FF),
          place: _savedHome,
          onTap: () {
            if (_savedHome != null) {
              _selectPlace(_savedHome!);
            } else {
              _searchFocus.requestFocus();
              _searchCtrl.text = 'Home';
            }
          },
        ),
        const SizedBox(height: 6),
        _buildSavedPlaceRow(
          isDark: isDark,
          title: 'Work',
          subtitle: _savedWork?.name ?? 'Tap to search & set',
          icon: Icons.work_rounded,
          iconColor: const Color(0xFF007AFF),
          place: _savedWork,
          onTap: () {
            if (_savedWork != null) {
              _selectPlace(_savedWork!);
            } else {
              _searchFocus.requestFocus();
              _searchCtrl.text = 'Work';
            }
          },
        ),
      ],
    );
  }

  Widget _buildSavedPlaceRow({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required PlaceModel? place,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black45,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 5. QUICK CONTROLS (3D View, Recenter)
  // -------------------------------------------------------------------------
  Widget _buildQuickControlsSection(bool isDark) {
    final mapProvider = Provider.of<MapProvider>(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.view_in_ar_rounded,
                  size: 16, color: isDark ? cyanAccent : blueAccent),
              const SizedBox(width: 8),
              Text(
                '3D Buildings',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
          Switch.adaptive(
            value: mapProvider.is3DMode,
            activeThumbColor: cyanAccent,
            onChanged: (val) {
              AppHaptics.selectionClick();
              mapProvider.toggle3DView();
            },
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 6. ACTIVE ROUTE / SELECTION SUMMARY
  // -------------------------------------------------------------------------
  Widget _buildActiveRouteSection(bool isDark) {
    final mapProvider = Provider.of<MapProvider>(context);
    final target = mapProvider.targetDestination;
    if (target == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cyanAccent.withValues(alpha: isDark ? 0.08 : 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cyanAccent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 18, color: cyanAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Selected Destination',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    mapProvider.clearDestination();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cyanAccent,
                  foregroundColor: Colors.black87,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  AppHaptics.heavyImpact();
                  mapProvider.startTurnByTurnNavigation();
                },
                icon: const Icon(Icons.navigation_rounded, size: 16),
                label: Text(
                  'Start Navigation',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 7. SEARCH RESULTS
  // -------------------------------------------------------------------------
  Widget _buildSearchResultsList(bool isDark) {
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: cyanAccent),
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            'No matching places found',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ),
      );
    }

    return Column(
      children: _searchResults.map((place) {
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _selectPlace(place),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.place_outlined,
                    size: 18, color: isDark ? Colors.white60 : Colors.black54),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (place.address.isNotEmpty)
                        Text(
                          place.address,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: isDark ? Colors.white38 : Colors.black45,
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
        );
      }).toList(),
    );
  }

  // -------------------------------------------------------------------------
  // 8. FOOTER: USER / SIGN IN POPUP TRIGGER
  // -------------------------------------------------------------------------
  Widget _buildFooter(bool isDark, User? user) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: user == null
          // Guest User -> Sleek "Sign In" Banner
          ? Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: cyanAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_outline_rounded,
                      size: 18, color: cyanAccent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sign In',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        'Save places & sync trips',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: isDark ? Colors.white38 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cyanAccent,
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      AppHaptics.selectionClick();
                      showRidelAuthDialog(context);
                    },
                    child: Text(
                      'Sign In',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            )
          // Logged In User -> Profile with Sign Out
          : Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: cyanAccent.withValues(alpha: 0.2),
                  child: const Icon(Icons.person_rounded, size: 16, color: cyanAccent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.userMetadata?['full_name'] ?? 'Explorer',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        user.email ?? '',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: isDark ? Colors.white38 : Colors.black45,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sign Out',
                  icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent),
                  splashRadius: 16,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  onPressed: () async {
                    AppHaptics.heavyImpact();
                    await AuthService().signOut();
                    if (mounted) {
                      setState(() {});
                      ToastService.showSuccess(context, 'Signed out');
                    }
                  },
                ),
              ],
            ),
    );
  }
}
