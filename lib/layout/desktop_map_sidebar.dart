import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
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
import 'package:ridel/features/auth/screens/login_screen.dart';
import 'package:ridel/features/auth/services/auth_service.dart';
import 'package:ridel/features/map/map_engine/map_engine.dart';
import 'package:ridel/features/map/models/place_model.dart';
import 'package:ridel/features/map/services/master_search_service.dart';
import 'package:ridel/main.dart';

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

  static const Color cyanAccent = Color(0xFF00E5FF);

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

    final containerColor = isDark
        ? const Color(0xFF161922).withValues(alpha: 0.90)
        : Colors.white.withValues(alpha: 0.92);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    final sidebarContent = ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          width: 380,
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. BRAND HEADER & COLLAPSE
              _buildHeader(isDark),

              // 2. SEARCH BOX
              _buildSearchField(isDark),

              // 3. SCROLLABLE BODY
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Active Route or Destination card (if any)
                      _buildActiveRouteSection(isDark),

                      // Search Results (if searching)
                      if (_searchResults.isNotEmpty || _isSearching)
                        _buildSearchResultsList(isDark)
                      else ...[
                        const SizedBox(height: 12),
                        // Quick Categories Grid
                        _buildCategoriesSection(isDark),

                        const SizedBox(height: 20),
                        // Saved Places
                        _buildSavedPlacesSection(isDark),
                      ],

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // 4. FOOTER: USER & SETTINGS
              _buildFooter(isDark, user),
            ],
          ),
        ),
      ),
    );

    return kIsWeb ? PointerInterceptor(child: sidebarContent) : sidebarContent;
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00E5FF), Color(0xFF007AFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.explore_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            'Ridel Maps',
            style: GoogleFonts.inter(
              fontSize: 19,
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
          IconButton(
            tooltip: 'Collapse Sidebar',
            icon: Icon(
              Icons.keyboard_double_arrow_left_rounded,
              color: isDark ? Colors.white70 : Colors.black54,
              size: 22,
            ),
            onPressed: () {
              AppHaptics.selectionClick();
              widget.onCollapse();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(bool isDark) {
    final searchBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.04);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: searchBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 1,
          ),
        ),
        child: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          onChanged: _onSearchChanged,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: 'Search places, petrol, food...',
            hintStyle: GoogleFonts.inter(
              fontSize: 14,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            prefixIcon: Icon(
              CupertinoIcons.search,
              size: 18,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: isDark ? Colors.white54 : Colors.black54,
                    onPressed: () {
                      _searchCtrl.clear();
                      _onSearchChanged('');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoriesSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EXPLORE NEARBY',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white38 : Colors.black38,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickCategories.map((cat) {
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _triggerCategorySearch(cat['query'] as String),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (cat['color'] as Color).withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(cat['icon'] as IconData,
                        size: 16, color: cat['color'] as Color),
                    const SizedBox(width: 6),
                    Text(
                      cat['label'] as String,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white87 : Colors.black87,
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

  Widget _buildActiveRouteSection(bool isDark) {
    return Consumer<MapProvider>(
      builder: (context, provider, _) {
        final hasPlace = provider.targetDestination != null;
        final hasRoute = provider.isRouteCalculated;
        final routeResult = provider.currentRouteResult;

        if (!hasPlace && !hasRoute) return const SizedBox.shrink();

        final distanceKm =
            routeResult != null ? routeResult.distanceKm.toStringAsFixed(1) : '—';
        final durationMins =
            routeResult != null ? routeResult.durationMins.toString() : '—';

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      const Color(0xFF00E5FF).withValues(alpha: 0.12),
                      const Color(0xFF007AFF).withValues(alpha: 0.08),
                    ]
                  : [
                      const Color(0xFF00E5FF).withValues(alpha: 0.08),
                      const Color(0xFF007AFF).withValues(alpha: 0.04),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: cyanAccent.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.navigation_rounded, color: cyanAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasRoute ? 'Route Ready' : 'Destination Selected',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: isDark ? Colors.white54 : Colors.black45,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      AppHaptics.lightImpact();
                      provider.clearSearchSession(context);
                    },
                  ),
                ],
              ),
              if (hasRoute) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildStatChip(
                      icon: Icons.timer_outlined,
                      label: '$durationMins mins',
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      icon: Icons.straighten_rounded,
                      label: '$distanceKm km',
                      isDark: isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cyanAccent,
                    foregroundColor: Colors.black87,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    AppHaptics.heavyImpact();
                    provider.start3DNavigation();
                  },
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: Text(
                    'Start 3D Navigation',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    AppHaptics.selectionClick();
                    provider.calculateAndDrawNativeRoute(context, mode: 'driving');
                  },
                  icon: const Icon(Icons.directions_car_rounded, size: 18),
                  label: Text(
                    'Get Directions',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cyanAccent),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsList(bool isDark) {
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RESULTS (${_searchResults.length})',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white38 : Colors.black38,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _searchResults.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          ),
          itemBuilder: (context, index) {
            final place = _searchResults[index];
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                child: const Icon(Icons.location_on_outlined, size: 16, color: cyanAccent),
              ),
              title: Text(
                place.name,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                place.address,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _selectPlace(place),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSavedPlacesSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SAVED PLACES',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white38 : Colors.black38,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        _buildSavedPlaceTile(
          icon: Icons.home_rounded,
          title: 'Home',
          place: _savedHome,
          isDark: isDark,
        ),
        const SizedBox(height: 6),
        _buildSavedPlaceTile(
          icon: Icons.work_rounded,
          title: 'Work',
          place: _savedWork,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildSavedPlaceTile({
    required IconData icon,
    required String title,
    required PlaceModel? place,
    required bool isDark,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (place != null) {
          _selectPlace(place);
        } else {
          _triggerCategorySearch(title);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cyanAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    place?.address ?? 'Tap to search & set',
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
            Icon(Icons.chevron_right_rounded,
                size: 18, color: isDark ? Colors.white24 : Colors.black26),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(bool isDark, User? user) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: cyanAccent.withValues(alpha: 0.2),
            child: const Icon(Icons.person_rounded, size: 18, color: cyanAccent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user?.userMetadata?['full_name'] ?? 'Explorer',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  user?.email ?? '',
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
          IconButton(
            tooltip: isDark ? 'Light Theme' : 'Dark Theme',
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 20,
              color: isDark ? Colors.amberAccent : Colors.orange,
            ),
            onPressed: () {
              AppHaptics.selectionClick();
              ThemeService.toggleTheme();
            },
          ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout_rounded, size: 20, color: Colors.redAccent),
            onPressed: () async {
              AppHaptics.heavyImpact();
              await AuthService().signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

