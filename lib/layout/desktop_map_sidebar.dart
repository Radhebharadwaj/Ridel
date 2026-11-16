import 'dart:async';

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
import 'package:ridel/core/theme/app_theme.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/widgets/adaptive_blur.dart';
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
  bool _isSearchFocused = false;
  Timer? _debounceTimer;

  PlaceModel? _savedHome;
  PlaceModel? _savedWork;
  StreamSubscription<AuthState>? _authSubscription;

  static const Color cyanAccent = Color(0xFF00E5FF);
  static const Color blueAccent = Color(0xFF0A84FF);

  final List<Map<String, dynamic>> _quickCategories = const [
    {
      'key': 'petrol',
      'label': 'Petrol',
      'icon': Icons.local_gas_station_rounded,
      'color': Color(0xFF00C7E6),
      'osmTag': 'fuel',
    },
    {
      'key': 'food',
      'label': 'Food',
      'icon': Icons.restaurant_rounded,
      'color': Color(0xFFFF9500),
      'osmTag': 'restaurant|cafe|fast_food',
    },
    {
      'key': 'parking',
      'label': 'Parking',
      'icon': Icons.local_parking_rounded,
      'color': Color(0xFF30D158),
      'osmTag': 'parking',
    },
    {
      'key': 'hospitals',
      'label': 'Hospitals',
      'icon': Icons.local_hospital_rounded,
      'color': Color(0xFFFF453A),
      'osmTag': 'hospital|clinic',
    },
    {
      'key': 'ev',
      'label': 'EV',
      'icon': Icons.ev_station_rounded,
      'color': Color(0xFFBF5AF2),
      'osmTag': 'charging_station',
    },
    {
      'key': 'atms',
      'label': 'ATMs',
      'icon': Icons.atm_rounded,
      'color': Color(0xFF0A84FF),
      'osmTag': 'atm|bank',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedPlaces();
    _searchFocus.addListener(_handleFocusChange);
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _isSearchFocused = _searchFocus.hasFocus);
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
    _searchFocus.removeListener(_handleFocusChange);
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
    _debounceTimer = Timer(const Duration(milliseconds: 280), () async {
      final locService =
          Provider.of<GlobalLocationService>(context, listen: false);
      final pos = locService.currentPosition;
      final userLatLng =
          pos != null ? LatLng(pos.latitude, pos.longitude) : null;

      final results =
          await _searchService.searchPlaces(trimmed, userLocation: userLatLng);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
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
    final screenHeight = MediaQuery.sizeOf(context).height;

    // Exact Weather Card outer shell tokens (matching WeatherFloatingWidget 1:1)
    final Color glassColor =
        RidelSurfaceTokens.pillBackground(isDark, elevated: true);
    final Color borderColor = RidelSurfaceTokens.border(isDark);
    final List<BoxShadow> panelShadows = RidelSurfaceTokens.pillShadows(isDark);
    const double outerRadius = 28.0;

    final sidebarContent = Container(
      width: 376,
      constraints: BoxConstraints(
        maxHeight: screenHeight - 40,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(outerRadius),
        boxShadow: panelShadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(outerRadius),
        child: AdaptiveBlur(
          sigmaX: 14.0,
          sigmaY: 14.0,
          child: Container(
            decoration: BoxDecoration(
              color: glassColor,
              borderRadius: BorderRadius.circular(outerRadius),
              border: Border.all(color: borderColor, width: 0.75),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. PREMIUM HEADER (Brand + Live Dot + Theme + Collapse)
                _buildHeader(isDark),

                // 2. SMOOTH CAPSULE PILL SEARCH BAR (Dead-Center Text & Icons)
                _buildSearchPill(isDark),

                // Subtle hairline separator matching Weather Card inner rhythm
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Container(
                    height: 0.5,
                    color: RidelSurfaceTokens.divider(isDark),
                  ),
                ),

                // 3. CENTER PANEL CONTENT
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildActiveRouteSection(isDark),
                        if (_searchResults.isNotEmpty || _isSearching)
                          _buildSearchResultsCard(isDark)
                        else ...[
                          _buildCategoriesSection(isDark),
                          const SizedBox(height: 16),
                          _buildSavedPlacesGrid(isDark),
                          const SizedBox(height: 14),
                          _buildRecentSearchesCard(isDark),
                          _buildMapViewControlsCard(isDark),
                        ],
                      ],
                    ),
                  ),
                ),

                // 4. SEAMLESS ACCOUNT DOCK
                _buildFooter(isDark, user),
              ],
            ),
          ),
        ),
      ),
    );

    return kIsWeb ? PointerInterceptor(child: sidebarContent) : sidebarContent;
  }

  // -------------------------------------------------------------------------
  // 1. HEADER
  // -------------------------------------------------------------------------
  Widget _buildHeader(bool isDark) {
    final primaryText = isDark ? Colors.white : const Color(0xFF111318);
    final accent =
        isDark ? RidelSurfaceTokens.iosBlueDark : RidelSurfaceTokens.iosBlueLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.asset(
                'assets/icon/logo.png',
                width: 34,
                height: 34,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ridel Maps',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: primaryText,
                      letterSpacing: -0.4,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF30D158),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              ValueListenableBuilder<String>(
                valueListenable:
                    context.read<GlobalLocationService>().currentCityName,
                builder: (context, city, _) {
                  final label = (city.isEmpty || city == 'Locating...')
                      ? 'Live Navigation'
                      : city;
                  return Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                      height: 1.1,
                    ),
                  );
                },
              ),
            ],
          ),
          const Spacer(),
          _buildHeaderIconPill(
            isDark: isDark,
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            iconColor: isDark ? const Color(0xFFFFD60A) : const Color(0xFFF59E0B),
            onTap: () {
              AppHaptics.selectionClick();
              ThemeService.toggleTheme();
            },
          ),
          const SizedBox(width: 8),
          _buildHeaderIconPill(
            isDark: isDark,
            tooltip: 'Collapse Sidebar',
            icon: Icons.keyboard_double_arrow_left_rounded,
            iconColor: isDark ? Colors.white70 : const Color(0xFF4B5563),
            onTap: () {
              AppHaptics.selectionClick();
              widget.onCollapse();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIconPill({
    required bool isDark,
    required String tooltip,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.045),
              shape: BoxShape.circle,
              border: Border.all(
                color: RidelSurfaceTokens.border(isDark),
                width: 0.75,
              ),
            ),
            child: Center(child: Icon(icon, size: 17, color: iconColor)),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 2. SMOOTH CAPSULE PILL SEARCH BAR (Mathematically Centered Text & Icons)
  // -------------------------------------------------------------------------
  Widget _buildSearchPill(bool isDark) {
    final accent =
        isDark ? RidelSurfaceTokens.iosBlueDark : RidelSurfaceTokens.iosBlueLight;
    final pillFill = isDark
        ? const Color(0xFF1C2230).withValues(alpha: 0.92)
        : const Color(0xFFF2F4F8);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: pillFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _isSearchFocused
                ? accent.withValues(alpha: 0.75)
                : RidelSurfaceTokens.border(isDark),
            width: _isSearchFocused ? 1.25 : 0.75,
          ),
          boxShadow: _isSearchFocused
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.16),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              size: 19,
              color: _isSearchFocused
                  ? accent
                  : (isDark ? Colors.white60 : const Color(0xFF6B7280)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: _onSearchChanged,
                cursorColor: accent,
                textAlignVertical: TextAlignVertical.center,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : const Color(0xFF111318),
                  height: 1.2,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Search places, petrol, food...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    color: isDark ? Colors.white38 : const Color(0xFF8A94A6),
                    height: 1.2,
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchCtrl,
              builder: (context, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: () {
                      AppHaptics.lightImpact();
                      _searchCtrl.clear();
                      _onSearchChanged('');
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.14)
                            : Colors.black.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 3. EXPLORE NEARBY (Full-Capsule Multi-Select Pills)
  // -------------------------------------------------------------------------
  Widget _buildCategoriesSection(bool isDark) {
    final mapProvider = Provider.of<MapProvider>(context);
    final activeCategories = mapProvider.activeNearbyCategories;
    final accent =
        isDark ? RidelSurfaceTokens.iosBlueDark : RidelSurfaceTokens.iosBlueLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'EXPLORE NEARBY',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
                color: isDark ? Colors.white54 : const Color(0xFF6B7280),
              ),
            ),
            if (activeCategories.isNotEmpty)
              GestureDetector(
                onTap: () {
                  AppHaptics.lightImpact();
                  mapProvider.clearAllNearbyCategories();
                },
                child: Text(
                  'Clear all',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickCategories.map((cat) {
            final key = cat['key'] as String;
            final isSelected = activeCategories.contains(key);
            final color = cat['color'] as Color;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  AppHaptics.selectionClick();
                  mapProvider.toggleNearbyCategory(
                    key: key,
                    label: cat['label'] as String,
                    osmTag: cat['osmTag'] as String,
                    color: color,
                    context: context,
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: isDark ? 0.22 : 0.14)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03)),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isSelected
                          ? color.withValues(alpha: 0.75)
                          : RidelSurfaceTokens.border(isDark),
                      width: isSelected ? 1.1 : 0.75,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        cat['icon'] as IconData,
                        size: 14,
                        color: isSelected ? color : color.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        cat['label'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isSelected
                              ? (isDark ? Colors.white : const Color(0xFF111318))
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : const Color(0xFF1F2937)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 4. QUICK COMMUTE SAVED PLACES (2-Column Glass Cards matching Weather Card)
  // -------------------------------------------------------------------------
  Widget _buildSavedPlacesGrid(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SAVED PLACES',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
            color: isDark ? Colors.white54 : const Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSavedPlaceTile(
                isDark: isDark,
                title: 'Home',
                subtitle: _savedHome?.name ?? 'Set address',
                icon: Icons.home_rounded,
                iconColor: const Color(0xFF0A84FF),
                onTap: () {
                  if (_savedHome != null) {
                    _selectPlace(_savedHome!);
                  } else {
                    _searchFocus.requestFocus();
                    _searchCtrl.text = 'Home';
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSavedPlaceTile(
                isDark: isDark,
                title: 'Work',
                subtitle: _savedWork?.name ?? 'Set address',
                icon: Icons.work_rounded,
                iconColor: const Color(0xFFFF9500),
                onTap: () {
                  if (_savedWork != null) {
                    _selectPlace(_savedWork!);
                  } else {
                    _searchFocus.requestFocus();
                    _searchCtrl.text = 'Work';
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSavedPlaceTile({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.045)
                : Colors.black.withValues(alpha: 0.025),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: RidelSurfaceTokens.border(isDark),
              width: 0.75,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: isDark ? 0.18 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 17, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF111318),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 5. RECENT SEARCHES (Clean Center Card)
  // -------------------------------------------------------------------------
  Widget _buildRecentSearchesCard(bool isDark) {
    final recents = context.select<MapProvider, List<PlaceModel>>(
      (p) => p.recentSearches.take(3).toList(),
    );
    if (recents.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RECENT',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: isDark ? Colors.white54 : const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.025),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: RidelSurfaceTokens.border(isDark),
                width: 0.75,
              ),
            ),
            child: Column(
              children: List.generate(recents.length, (i) {
                final place = recents[i];
                final isLast = i == recents.length - 1;
                return Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.vertical(
                        top: i == 0 ? const Radius.circular(20) : Radius.zero,
                        bottom:
                            isLast ? const Radius.circular(20) : Radius.zero,
                      ),
                      onTap: () => _selectPlace(place),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.history_rounded,
                              size: 16,
                              color: isDark
                                  ? Colors.white54
                                  : const Color(0xFF6B7280),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                place.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.9)
                                      : const Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            Icon(
                              Icons.north_west_rounded,
                              size: 14,
                              color: isDark ? Colors.white30 : Colors.black26,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isLast)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Container(
                          height: 0.5,
                          color: RidelSurfaceTokens.divider(isDark),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 6. MAP VIEW CONTROLS (3D Buildings, Labels)
  // -------------------------------------------------------------------------
  Widget _buildMapViewControlsCard(bool isDark) {
    final mapProvider = Provider.of<MapProvider>(context);
    final accent =
        isDark ? RidelSurfaceTokens.iosBlueDark : RidelSurfaceTokens.iosBlueLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: RidelSurfaceTokens.border(isDark),
          width: 0.75,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.view_in_ar_rounded, size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Text(
                '3D Buildings',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          Switch.adaptive(
            value: mapProvider.is3DMode,
            activeThumbColor: accent,
            onChanged: (_) {
              AppHaptics.selectionClick();
              mapProvider.toggle3DView();
            },
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 7. ACTIVE ROUTE / DESTINATION SUMMARY
  // -------------------------------------------------------------------------
  Widget _buildActiveRouteSection(bool isDark) {
    final mapProvider = Provider.of<MapProvider>(context);
    final target = mapProvider.targetDestination;
    if (target == null) return const SizedBox.shrink();

    final accent =
        isDark ? RidelSurfaceTokens.iosBlueDark : RidelSurfaceTokens.iosBlueLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: isDark ? 0.12 : 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accent.withValues(alpha: 0.35),
            width: 0.85,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.location_on_rounded, size: 18, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mapProvider.activeDestination?.name ?? 'Selected Destination',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF111318),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => mapProvider.clearDestination(),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.black.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onPressed: () {
                  AppHaptics.heavyImpact();
                  mapProvider.startTurnByTurnNavigation();
                },
                icon: const Icon(Icons.navigation_rounded, size: 16),
                label: Text(
                  'Start Navigation',
                  style: GoogleFonts.inter(
                      fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 8. SEARCH RESULTS CARD
  // -------------------------------------------------------------------------
  Widget _buildSearchResultsCard(bool isDark) {
    final accent =
        isDark ? RidelSurfaceTokens.iosBlueDark : RidelSurfaceTokens.iosBlueLight;

    if (_isSearching) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: accent),
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No matching places found',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: isDark ? Colors.white54 : const Color(0xFF6B7280),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: RidelSurfaceTokens.border(isDark),
          width: 0.75,
        ),
      ),
      child: Column(
        children: List.generate(_searchResults.length, (i) {
          final place = _searchResults[i];
          final isLast = i == _searchResults.length - 1;
          return Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? const Radius.circular(20) : Radius.zero,
                  bottom: isLast ? const Radius.circular(20) : Radius.zero,
                ),
                onTap: () => _selectPlace(place),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: isDark ? 0.15 : 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.place_rounded, size: 16, color: accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              place.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF111318),
                              ),
                            ),
                            if (place.address.isNotEmpty)
                              Text(
                                place.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white54
                                      : const Color(0xFF6B7280),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    height: 0.5,
                    color: RidelSurfaceTokens.divider(isDark),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 9. FOOTER ACCOUNT DOCK
  // -------------------------------------------------------------------------
  Widget _buildFooter(bool isDark, User? user) {
    final accent =
        isDark ? RidelSurfaceTokens.iosBlueDark : RidelSurfaceTokens.iosBlueLight;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.025)
            : Colors.black.withValues(alpha: 0.02),
        border: Border(
          top: BorderSide(
            color: RidelSurfaceTokens.divider(isDark),
            width: 0.5,
          ),
        ),
      ),
      child: user == null
          ? Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person_outline_rounded,
                      size: 18, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ridel Account',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF111318),
                        ),
                      ),
                      Text(
                        'Sync saved places & trips',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () {
                      AppHaptics.selectionClick();
                      showRidelAuthDialog(context);
                    },
                    child: Text(
                      'Sign In',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: accent.withValues(alpha: 0.18),
                  child: Icon(Icons.person_rounded, size: 17, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.userMetadata?['full_name'] ?? 'Explorer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF111318),
                        ),
                      ),
                      Text(
                        user.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sign Out',
                  icon: const Icon(Icons.logout_rounded,
                      size: 18, color: Color(0xFFFF453A)),
                  splashRadius: 16,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
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
