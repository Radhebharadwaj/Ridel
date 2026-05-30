import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/features/map/map_engine/map_engine.dart';

import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/universal_mic_button.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/app_shadows.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';
import 'package:ridel/features/map/models/place_model.dart';
import 'package:ridel/features/map/services/master_search_service.dart';
import 'package:ridel/features/map/services/map_share_service.dart';
import 'package:ridel/features/map/services/place_api_services.dart';
import 'package:ridel/features/map/services/route_visualizer.dart';
import 'package:ridel/features/map/services/route_engine_service.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart';
import 'package:ridel/features/map/widgets/quick_action_buttons.dart';

// 🚀 IMPORT YOUR NOTIFICATION SERVICE HERE
import 'package:ridel/core/services/notification_service.dart';
import 'package:ridel/core/utils/toast_service.dart';

// YE DONO FILES ISI KA HISSA HAIN (Do not change structure)
part 'search_sheet_headers.dart';
part 'search_sheet_views.dart';

bool _guestHistoryCleared = false;

class MapSearchSheet extends StatefulWidget {
  const MapSearchSheet({
    required this.isMapTabActive,
    required this.onSearchModeChanged,
    required this.onSearchSubmitted,
    required this.onBackToPreviousTab,
    super.key,
    this.onProgressChanged,
  });
  final bool isMapTabActive;
  final Function(bool) onSearchModeChanged;
  final Function(String) onSearchSubmitted;
  final VoidCallback onBackToPreviousTab;
  final Function(double)? onProgressChanged;

  @override
  State<MapSearchSheet> createState() => _MapSearchSheetState();
}

class _MapSearchSheetState extends State<MapSearchSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _originCtrl = TextEditingController();
  final TextEditingController _destCtrl = TextEditingController();
  final FocusNode _originFocus = FocusNode();
  final FocusNode _destFocus = FocusNode();
  PlaceModel? _originPlace;
  PlaceModel? _destPlace;
  String? _activeRoutingField;

  final FocusNode _searchFocus = FocusNode();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  // ignore: deprecated_member_use

  // ignore: deprecated_member_use
  final ExpansionTileController _nearbyTileCtrl = ExpansionTileController();

  final MasterSearchService _searchService = MasterSearchService();
  final RouteEngineService _routeEngineService = RouteEngineService();
  List<PlaceModel> _searchResults = [];
  List<PlaceModel> _recentSearches = [];
  bool _isSearching = false;
  bool _isSearchMode = false;

  bool _showSearchList = true;
  PlaceModel? _selectedPlace;

  // ignore: unused_field
  bool _isLoadingDetails = false;
  // ignore: unused_field
  EnrichedPlaceDetails? _enrichedDetails;
  // ignore: unused_field
  String? _selectedActionType;

  bool _showDirections = false;
  String _selectedNavMode = 'driving';

  // ignore: unused_field
  bool _isLoadingRoute = false;
  // ignore: unused_field
  RouteResult? _currentRoute;
  // ignore: unused_field
  String? _routeErrorMessage;

  final ValueNotifier<double> _sheetProgress = ValueNotifier(0);
  Timer? _debounce;
  String _lastQuery = '';

  bool _showDragHandle = true;
  Timer? _dragHandleTimer;

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  static const Color neonCyan = Color(0xFF00E5FF);

  static const Map<String, Map<String, String>> _ticketBookingInfo = {
    'Lal Quila': {
      'bookingWebsite': 'https://booking.asi.ind.in',
      'ticketPhone': '1800-11-22-33',
    },
    'Taj Mahal': {
      'bookingWebsite': 'https://asi.paygov.in',
      'ticketPhone': '1800-11-44-55',
    },
  };

  double _lastScreenHeight = 0;
  double _lastScreenWidth = 0;
  double _lastHapticExtent = -1.0;

  double get _safeMinSize {
    if (!mounted) return 0.15;
    final screenSize = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final requiredHeight = 86.0 + safeBottom;
    return (requiredHeight / screenSize.height).clamp(0.05, 0.40);
  }

  double get _safeMidSize => 0.35;
  double get _safeMaxSize => 0.55;

  // Helper to allow extensions to call setState without violating protected member rules
  void rebuildState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  // 🚀 FIX: Centralized Premium Notification Handler
  void _showPremiumNotification(String message, {bool isError = false}) {
    if (isError) {
      ToastService.showError(context, message, title: "Error");
      NotificationService.saveImportant("Error", message);
    } else {
      ToastService.showSuccess(context, message, title: "Success");
      NotificationService.saveSystem("Notification", message);
    }
  }

  Future<void> _handleSmartQuickAction(String type) async {
    AppHaptics.mediumImpact();
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        _showPremiumNotification('Please log in to save Home/Work locations.',
            isError: true);
        return;
      }

      final data = await supabase
          .from('user_profiles')
          .select('home_place, work_place')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return; // 🛡️ CRITICAL ASYNC SAFETY

      final column = type == 'HOME' ? 'home_place' : 'work_place';
      final savedPlace = data?[column];

      if (savedPlace != null && savedPlace['latitude'] != null) {
        _searchFocus.unfocus();
        if (_sheetController.isAttached) {
          // 🍏 APPLE CURVE (easeOutCubic for natural snap)
          _sheetController.animateTo(_safeMinSize,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic);
        }

        final lat = (savedPlace['latitude'] as num).toDouble();
        final lng = (savedPlace['longitude'] as num).toDouble();

        final mapProvider = Provider.of<MapProvider>(context, listen: false);
        await mapProvider.flyToPlace(lat, lng);
        if (!mounted) return;
        mapProvider.setDestinationSelected(true);
        await mapProvider.triggerDirectionsFlow(context);
        AppHaptics.success();
      } else {
        setState(() => _selectedActionType = type);
        _searchFocus.requestFocus();

        if (_sheetController.isAttached) {
          _sheetController.animateTo(_safeMidSize,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic);
        }

        _showPremiumNotification(
            'Search and select a location to save as $type');
      }
    } catch (e) {
      debugPrint("Smart Quick Action Error: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _isSearchMode = widget.isMapTabActive;

    _wakeUpDragHandle();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    // 🚀 FIX: iOS style fluid entrance using easeOutExpo
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 1.2), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOutExpo,
      ),
    );

    if (widget.isMapTabActive) unawaited(_slideController.forward());

    _searchFocus.addListener(() {
      _wakeUpDragHandle();
      if (_searchFocus.hasFocus) {
        if (!_showSearchList) setState(() => _showSearchList = true);

        try {
          _nearbyTileCtrl.expand();
        } catch (_) {}
      } else {

        try {
          _nearbyTileCtrl.collapse();
        } catch (_) {}
      }
      setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MapProvider>(context, listen: false)
          .addListener(_onMapProviderUpdated);
    });

    _searchCtrl.addListener(_onSearchChanged);
    unawaited(_handleGuestSessionHistory());
    unawaited(_loadRecents());
  }

  void _wakeUpDragHandle() {
    if (!mounted) return;
    if (!_showDragHandle) {
      setState(() => _showDragHandle = true);
    }
    _dragHandleTimer?.cancel();
    _dragHandleTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showDragHandle = false);
    });
  }

  void _onSearchChanged() {
    _wakeUpDragHandle();

    final currentQuery = _searchCtrl.text.trim();

    if (currentQuery.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false; // Using _isSearching as isLoading
          if (!_showSearchList) _showSearchList = true;
        });
      }
      return;
    }

    setState(() {
      _isSearching = true;
      _showSearchList = true;
      // Clear previous results if the query is significantly different
      if (!_lastQuery.startsWith(currentQuery) && !currentQuery.startsWith(_lastQuery)) {
        _searchResults = [];
      }
    });
    _lastQuery = currentQuery;

    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      debugPrint("🔍 DEBUG SEARCH: Sending query -> '$currentQuery'");
      final results = await MasterSearchService().searchPlaces(currentQuery);
      debugPrint("🔍 DEBUG SEARCH: Received ${results.length} results for '$currentQuery'");
      
      if (mounted && _searchCtrl.text.trim() == currentQuery) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _handleGuestSessionHistory() async {
    if (!_guestHistoryCleared) {
      _guestHistoryCleared = true;
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('recent_searches');
        }
      } catch (e) {
        debugPrint('Auth Check Failed: $e');
      }
    }
  }

  @override
  void didUpdateWidget(MapSearchSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isMapTabActive && !oldWidget.isMapTabActive) {
      _wakeUpDragHandle();
      unawaited(_slideController.forward());
      if (!_isSearchMode) {
        setState(() => _isSearchMode = true);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => widget.onSearchModeChanged(true));
        _sheetProgress.value = 0.0;
        if (_sheetController.isAttached) {
          try {
            _sheetController.jumpTo(_safeMinSize);
          } catch (e) {
            debugPrint('Error: $e');
          }
        }
      }
    } else if (!widget.isMapTabActive && oldWidget.isMapTabActive) {
      unawaited(_slideController.reverse());
      if (_isSearchMode) {
        _searchFocus.unfocus();
        setState(() => _isSearchMode = false);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => widget.onSearchModeChanged(false));
      }
    }
  }

  Future<void> _loadRecents() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user != null) {
        final response = await supabase
            .from('search_history')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(10);

        if (!mounted) return;
        final validRecents = (response as List<dynamic>)
            .map<PlaceModel>(
              (e) => PlaceModel(
                placeId: e['place_id']?.toString() ??
                    'recent_${e['latitude']}_${e['longitude']}',
                name: e['name']?.toString() ?? '',
                address: e['address']?.toString() ?? '',
                latitude: (e['latitude'] as num?)?.toDouble() ?? 0.0,
                longitude: (e['longitude'] as num?)?.toDouble() ?? 0.0,
                categories: [e['category']?.toString() ?? 'Recent'],
              ),
            )
            .where((p) => p.name.trim().isNotEmpty)
            .toList();
        setState(() => _recentSearches = validRecents);
      } else {
        final recents = await _searchService.getLocalHistory();
        if (!mounted) return;
        final validRecents =
            recents.where((p) => p.name.trim().isNotEmpty).toList();
        setState(() => _recentSearches = validRecents);
      }
    } catch (e) {
      final recents = await _searchService.getLocalHistory();
      if (mounted) {
        setState(() => _recentSearches =
            recents.where((p) => p.name.trim().isNotEmpty).toList());
      }
    }
  }

  Future<void> _deleteRecentSearch(PlaceModel place) async {
    AppHaptics.lightImpact();
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase
            .from('search_history')
            .delete()
            .match({'user_id': user.id, 'name': place.name});
      } else {
        final prefs = await SharedPreferences.getInstance();
        final history = prefs.getStringList('recent_searches') ?? [];
        history.removeWhere((item) => item.contains(place.name));
        await prefs.setStringList('recent_searches', history);
      }
    } catch (e) {
      debugPrint('Error caught: $e');
    }
    if (mounted) _loadRecents();
  }

  Future<void> _clearAllRecents() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase.from('search_history').delete().eq('user_id', user.id);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('recent_searches');
      }
    } catch (e) {
      debugPrint('Error caught: $e');
    }
    if (mounted) _loadRecents();
  }

  Future<void> _handleSearchExecution(String query, [PlaceModel? savedPlace]) async {
    _searchFocus.unfocus();
    if (query.trim().isEmpty) return;

    if (savedPlace != null && savedPlace.latitude != 0.0 && savedPlace.longitude != 0.0) {
      await _submitSearch(savedPlace);
      return;
    }

    final results = await _searchService.searchPlaces(query);

    if (results.isEmpty) {
      AppHaptics.heavyImpact();
      if (mounted) {
        ToastService.showError(
          context,
          "No match found for '$query'. Please check the spelling and try again.",
        );
      }
      return; // Early return to keep the sheet open and input focused
    }

    final place = results.first;
    await _submitSearch(place);
  }

  Future<void> _submitSearch([
    PlaceModel? selectedPlace,
    String? categoryQuery,
  ]) async {
    AppHaptics.lightImpact();
    _searchFocus.unfocus();

    if (categoryQuery != null) {
      widget.onSearchSubmitted(categoryQuery);
    } else {
      final placeToSubmit = selectedPlace ??
          (_searchResults.isNotEmpty ? _searchResults.first : null);
      if (placeToSubmit != null) {
        setState(() {
          _selectedPlace = placeToSubmit;
          _showSearchList = false;
          _showDirections = false;
          _isLoadingDetails = true;
        });

        await _searchService.saveToHistory(placeToSubmit);
        if (!mounted) return;

        try {
          final supabase = Supabase.instance.client;
          final user = supabase.auth.currentUser;
          if (user != null) {
            await supabase.from('search_history').insert({
              'user_id': user.id,
              'name': placeToSubmit.name,
              'address': placeToSubmit.address,
              'latitude': placeToSubmit.latitude,
              'longitude': placeToSubmit.longitude,
              'category': placeToSubmit.categories.isNotEmpty
                  ? placeToSubmit.categories.first
                  : 'unknown',
              'created_at': DateTime.now().toIso8601String(),
            });
          }
        } catch (_) {}

        await _loadRecents();
        if (!mounted) return;

        if (_selectedActionType == 'HOME' || _selectedActionType == 'WORK') {
          try {
            final user = Supabase.instance.client.auth.currentUser;
            if (user != null) {
              final column =
                  _selectedActionType == 'HOME' ? 'home_place' : 'work_place';
              await Supabase.instance.client.from('user_profiles').update({
                column: {
                  'name': placeToSubmit.name,
                  'address': placeToSubmit.address,
                  'latitude': placeToSubmit.latitude,
                  'longitude': placeToSubmit.longitude,
                },
              }).eq('id', user.id);
              if (!mounted) return;
              _showPremiumNotification(
                  "${_selectedActionType == 'HOME' ? 'Home' : 'Work'} location updated successfully!");
            }
          } catch (_) {}
          _selectedActionType = null;
        }

        widget.onSearchSubmitted(
          '${placeToSubmit.latitude},${placeToSubmit.longitude}',
        );

        if (mounted) {
          try {
            final mapProvider =
                Provider.of<MapProvider>(context, listen: false);

            // 🧭 Step 1: Fly camera to the place & drop a pin
            mapProvider.flyToPlace(
                placeToSubmit.latitude, placeToSubmit.longitude);

            // 🧭 Step 2: Update state machine → placeSelected
            // This triggers QuickActionButtons to morph to "Directions"
            mapProvider.setDestinationSelected(true);

            // 🚫 Do NOT auto-draw route here — the user must first pick a
            // transport mode from the Walk/Bike/Car/Heavy buttons, which
            // calls setNavMode → autoDrawRouteTo → routeDrawn.
          } catch (e) {
            debugPrint('⚠️ _submitSearch map wiring error: $e');
          }
        }

        try {
          final enrichedResult = await PlaceEnrichmentService().getRichPlaceDetails(placeToSubmit.name, placeToSubmit.latitude, placeToSubmit.longitude);
          if (mounted) {
            setState(() {
              _enrichedDetails = enrichedResult;
              _isLoadingDetails = false;
            });
          }
        } catch (e) {
          if (mounted) setState(() => _isLoadingDetails = false);
        }
      } else if (_searchCtrl.text.isNotEmpty) {
        if (_searchResults.isEmpty) {
          _showPremiumNotification('Place not found. Try a different name.',
              isError: true);
          _searchCtrl.clear();
        } else {
          widget.onSearchSubmitted(_searchCtrl.text);
        }
      }
    }

    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        _safeMinSize,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic, // Apple snap
      );
    }
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _searchCtrl.clear();
        unawaited(_loadRecents());
      }
    });
  }

  void _openDirectionsView() {
    AppHaptics.mediumImpact();
    setState(() {
      _showDirections = true;
      _isLoadingRoute = true;
      _routeErrorMessage = null;
      _destPlace = _selectedPlace;
      _destCtrl.text = _destPlace?.name ?? '';
      _originPlace = null;
      _originCtrl.text = 'Your Location';
      _activeRoutingField = null;
    });
    if (_sheetController.isAttached) {
      unawaited(
        _sheetController.animateTo(
          _safeMidSize,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    unawaited(_checkAndFetchRoute());
  }

  void _onMapProviderUpdated() async {
    if (!mounted) return;
    final provider = Provider.of<MapProvider>(context, listen: false);

    // 🚀 FIX: Deep Clean Synchronization with Provider
    // If provider was cleared (e.g., cross button tapped in headers) but sheet still has the place
    if (!provider.isDestinationSelected &&
        _selectedPlace != null &&
        !_showDirections) {
      setState(() {
        _selectedPlace = null;
        _destPlace = null;
        _originPlace = null;
        _searchCtrl.clear();
        _activeRoutingField = null;
        _currentRoute = null;
        _showSearchList = true;
      });
      // Optionally shrink sheet down to min size naturally
      if (_sheetController.isAttached && !_searchFocus.hasFocus) {
        _sheetController.animateTo(_safeMinSize,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic);
      }
    }

    if (provider.tappedPlaceFromMap != null) {
      final tappedPlace = provider.tappedPlaceFromMap!;
      provider.clearTappedPlace();

      if (_showDirections && _activeRoutingField != null) {
        AppHaptics.heavyImpact();
        if (_activeRoutingField == 'origin') {
          setState(() {
            _originPlace = tappedPlace;
            _originCtrl.text = tappedPlace.name;
            _activeRoutingField = 'dest';
            _destFocus.requestFocus();
          });
        } else {
          setState(() {
            _destPlace = tappedPlace;
            _destCtrl.text = tappedPlace.name;
            _activeRoutingField = null;
            _destFocus.unfocus();
            _originFocus.unfocus();
          });
        }
        unawaited(_checkAndFetchRoute());
      } else if (!_showDirections) {
        setState(() {
          _selectedPlace = tappedPlace;
          _searchCtrl.text = tappedPlace.name;
          _showSearchList = false;
          _showDirections = false;
          _isLoadingDetails = true;
        });
        if (_sheetController.isAttached) {
          unawaited(
            _sheetController.animateTo(
              _safeMidSize,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
            ),
          );
        }
        unawaited(_fetchExtraDetailsForPlace(tappedPlace));

        final destLatLng = LatLng(tappedPlace.latitude, tappedPlace.longitude);
        if (!mounted) return;
        await Provider.of<MapProvider>(context, listen: false)
            .autoDrawRouteTo(destLatLng, context);
      }
    }
  }

  Future<void> _checkAndFetchRoute() async {
    if (_destPlace == null && _selectedPlace == null) return;

    final destLoc = LatLng(
      _destPlace?.latitude ?? _selectedPlace!.latitude,
      _destPlace?.longitude ?? _selectedPlace!.longitude,
    );
    LatLng originLoc;

    if (_originPlace != null) {
      originLoc = LatLng(_originPlace!.latitude, _originPlace!.longitude);
    } else {
      final locService =
          Provider.of<GlobalLocationService>(context, listen: false);
      if (locService.currentPosition == null) {
        await locService.forceRefreshLocation();
      }
      final pos = locService.currentPosition;
      if (pos == null) {
        if (mounted) {
          setState(() {
            _isLoadingRoute = false;
            _routeErrorMessage = 'GPS not available.';
          });
        }
        return;
      }
      originLoc = LatLng(pos.latitude, pos.longitude);
    }

    if (mounted) {
      setState(() {
        _isLoadingRoute = true;
        _routeErrorMessage = null;
      });
    }

    try {
      // 🚀 FIX: Force sync with Provider's current mode to solve the Walk/Car Bug
      if (!mounted) return;
      final provider = Provider.of<MapProvider>(context, listen: false);
      final activeMode = provider.currentNavMode;

      debugPrint("🛑 ROUTE DEBUG: Fetching route from ${originLoc.latitude},${originLoc.longitude} to ${destLoc.latitude},${destLoc.longitude}");
      final route = await _routeEngineService.getRoute(
        originLoc,
        destLoc,
        mode: activeMode,
      ).timeout(const Duration(seconds: 10));

      if (route == null) {
        debugPrint("🛑 ROUTE DEBUG FATAL: RoutingService returned NULL!");
      } else {
        debugPrint("🛑 ROUTE DEBUG SUCCESS: Got ${route.coordinates.length} coordinates back!");
      }

      if (mounted) {
        setState(() {
          _currentRoute = route;
          _isLoadingRoute = false;
          if (route == null) _routeErrorMessage = 'Route unavailable.';
        });
      }

      debugPrint("🛑 DEBUG ROUTE STATUS: Route fetched? ${route != null}");
      if (route != null) {
        debugPrint("🛑 DEBUG ROUTE COORDS: Count = ${route.coordinates.length}");
      } else {
        debugPrint("🛑 DEBUG ROUTE ERROR: $_routeErrorMessage");
      }

      if (route != null) {
        if (!mounted) return;
        final mapCtrl = provider.controller;

        if (mapCtrl != null) {
          await RouteVisualizer.drawRoute(mapCtrl, route.coordinates, provider.currentTheme);

          // 🧭 State Machine: Route drawn → morph QuickActionButtons to "Start"
          provider.engine.setUIState(MapUIState.routeDrawn);

          final double minLat = math.min(originLoc.latitude, destLoc.latitude);
          final double maxLat = math.max(originLoc.latitude, destLoc.latitude);
          final double minLng =
              math.min(originLoc.longitude, destLoc.longitude);
          final double maxLng =
              math.max(originLoc.longitude, destLoc.longitude);

          mapCtrl.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(minLat, minLng),
                northeast: LatLng(maxLat, maxLng),
              ),
              left: 50,
              right: 50,
              top: 100,
              bottom: 400,
            ),
            duration: const Duration(milliseconds: 1200),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
          _routeErrorMessage = 'Network error. Try again.';
        });
      }
    }
  }

  Future<void> _fetchExtraDetailsForPlace(PlaceModel place) async {
    try {
      final enrichedResult = await PlaceEnrichmentService().getRichPlaceDetails(place.name, place.latitude, place.longitude);
      if (mounted) {
        setState(() {
          _enrichedDetails = enrichedResult;
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  void _closeDirectionsView() {
    AppHaptics.lightImpact();
    setState(() {
      _showDirections = false;
      _currentRoute = null;
      _activeRoutingField = null;
    });

    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    final mapCtrl = mapProvider.controller;

    if (mapCtrl != null) {
      unawaited(RouteVisualizer.clearRoute(mapCtrl));
      mapProvider.engine.onLocateMeTapped();
    }
  }

  void _showClearAllWarning() {
    AppHaptics.heavyImpact();
    unawaited(
      showDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Clear Recent Searches?'),
          content: const Text(
            'This will permanently delete all your recent search history. Are you sure?',
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              child: const Text('Clear All'),
              onPressed: () {
                Navigator.pop(context);
                unawaited(_clearAllRecents());
              },
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _initiatePhoneCall() async {
    if (_enrichedDetails?.osmPhone == null) return;
    final url = Uri.parse('tel:${_enrichedDetails!.osmPhone!}');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  // ignore: unused_element
  Future<void> _openWebsite() async {
    if (_enrichedDetails?.osmWebsite == null) return;
    final url = Uri.parse(_enrichedDetails!.osmWebsite!);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _expandToFull() {
    _wakeUpDragHandle();
    if (!_sheetController.isAttached) return;
    if (_sheetController.size < (_safeMaxSize - 0.02)) {
      unawaited(
        _sheetController.animateTo(
          _safeMaxSize,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _handleCancelTap() {
    AppHaptics.lightImpact();
    if (_showDirections) {
      _closeDirectionsView();
      return;
    }
    final hasFocusOrText = _searchFocus.hasFocus || _searchCtrl.text.isNotEmpty;
    final isExpanded = _sheetController.isAttached &&
        _sheetController.size > (_safeMinSize + 0.05);

    if (hasFocusOrText) {
      _searchFocus.unfocus();
      _searchCtrl.clear();
      widget.onSearchSubmitted('');
      if (_sheetController.isAttached) {
        unawaited(
          _sheetController.animateTo(
            _safeMinSize,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    } else if (isExpanded) {
      if (_sheetController.isAttached) {
        unawaited(
          _sheetController.animateTo(
            _safeMinSize,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    } else {
      _searchFocus.unfocus();
      setState(() => _isSearchMode = false);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onSearchModeChanged(false));
      widget.onBackToPreviousTab();
    }
  }

  // ignore: unused_element
  Map<String, String>? _getBookingInfoForCurrentPlace() {
    if (_selectedPlace == null) return null;
    return _ticketBookingInfo[_selectedPlace!.name];
  }

  void _handleManualDragUpdate(DragUpdateDetails details) {
    _wakeUpDragHandle();
    if (!_sheetController.isAttached) return;
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (screenHeight == 0) return;
    final delta = -details.primaryDelta! / screenHeight;
    final newSize =
        (_sheetController.size + delta).clamp(_safeMinSize, _safeMaxSize);
    _sheetController.jumpTo(newSize);
  }

  void _handleManualDragEnd(DragEndDetails details) {
    _wakeUpDragHandle();
    if (!_sheetController.isAttached) return;
    final velocity = details.primaryVelocity ?? 0;
    final size = _sheetController.size;
    const duration = Duration(milliseconds: 350);
    final snaps = <double>[_safeMinSize, _safeMidSize, _safeMaxSize];

    // 🚀 FIX: iOS-style snappy velocity release using easeOutCubic
    if (velocity < -300) {
      final next =
          snaps.firstWhere((s) => s > size + 0.02, orElse: () => _safeMaxSize);
      unawaited(
        _sheetController.animateTo(
          next,
          duration: duration,
          curve: Curves.easeOutCubic,
        ),
      );
    } else if (velocity > 300) {
      final next =
          snaps.lastWhere((s) => s < size - 0.02, orElse: () => _safeMinSize);
      unawaited(
        _sheetController.animateTo(
          next,
          duration: duration,
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      final closest =
          snaps.reduce((a, b) => (a - size).abs() < (b - size).abs() ? a : b);
      unawaited(
        _sheetController.animateTo(
          closest,
          duration: duration,
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  void dispose() {
    _dragHandleTimer?.cancel();
    _debounce?.cancel();
    _sheetController.dispose();
    _searchCtrl.dispose();
    _originCtrl.dispose();
    _destCtrl.dispose();
    _originFocus.dispose();
    _destFocus.dispose();
    _searchFocus.dispose();
    _sheetProgress.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Widget _buildDynamicDragHandle(bool isDark) {
    return MouseRegion(
      onEnter: (_) => _wakeUpDragHandle(),
      onHover: (_) => _wakeUpDragHandle(),
      child: GestureDetector(
        onTapDown: (_) => _wakeUpDragHandle(),
        onVerticalDragUpdate: _handleManualDragUpdate,
        onVerticalDragEnd: _handleManualDragEnd,
        behavior: HitTestBehavior.translucent,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _showDragHandle ? 1.0 : 0.0,
          child: Container(
            height: 32,
            alignment: Alignment.center,
            color: Colors.transparent,
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = screenSize.width > 600;

    // Header height is computed inside the builder where progress is available

    final minS = _safeMinSize;
    final midS = _safeMidSize;
    final maxS = _safeMaxSize;

    if ((_lastScreenHeight != 0 &&
            (_lastScreenHeight - screenSize.height).abs() > 20) ||
        (_lastScreenWidth != 0 &&
            (_lastScreenWidth - screenSize.width).abs() > 20)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sheetController.isAttached) {
          if (!_searchFocus.hasFocus && _selectedPlace == null && !_showDirections && _searchCtrl.text.isEmpty) {
            _sheetController.jumpTo(_safeMinSize);
          } else if (!_searchFocus.hasFocus) {
            // Only jump if NOT focused. If focused, let the 500ms focus listener animateTo handle it smoothly!
            _sheetController.jumpTo(_safeMaxSize.clamp(_safeMinSize, 1.0));
          }
        }
      });
    }
    _lastScreenHeight = screenSize.height;
    _lastScreenWidth = screenSize.width;

    var snaps = <double>[minS, midS, maxS];
    snaps.sort();
    snaps = snaps.toSet().toList();

    return SlideTransition(
      position: _slideAnimation,
      child: NotificationListener<Notification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification &&
              notification.dragDetails != null) {
            final velocity = notification.dragDetails!.primaryVelocity ?? 0;
            if (velocity < -300 && _sheetController.isAttached) {
              unawaited(
                _sheetController.animateTo(
                  _safeMaxSize,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                ),
              );
            } else if (velocity > 300 && _sheetController.isAttached) {
              unawaited(
                _sheetController.animateTo(
                  _safeMinSize,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                ),
              );
            }
          }

          if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
            // Unfocus keyboard if the user drags the sheet down
            if (notification.scrollDelta != null && notification.scrollDelta! < 0 && _searchFocus.hasFocus) {
               _searchFocus.unfocus();
            }
          }

          if (notification is DraggableScrollableNotification) {
            _wakeUpDragHandle();

            final extent = notification.extent;
            // ⌨️ KEYBOARD DISMISS FIX
            if (extent < midS - 0.05 && _searchFocus.hasFocus) {
              _searchFocus.unfocus();
            }

            final isAtSnap = (extent - minS).abs() < 0.01 ||
                (extent - midS).abs() < 0.01 ||
                (extent - maxS).abs() < 0.01;

            if (isAtSnap) {
              if ((_lastHapticExtent - extent).abs() > 0.05) {
                AppHaptics.mediumImpact();
                _lastHapticExtent = extent;
              }
            } else {
              if ((_lastHapticExtent - extent).abs() > 0.05) {
                _lastHapticExtent = -1.0;
              }
            }

            final progress = ((notification.extent - notification.minExtent) /
                    (notification.maxExtent - notification.minExtent))
                .clamp(0.0, 1.0);
            if (_sheetProgress.value != progress) {
              _sheetProgress.value = progress;
              if (widget.onProgressChanged != null) {
                widget.onProgressChanged!(progress);
              }
            }
            if (progress < 0.65) {
              try {

                if (_nearbyTileCtrl.isExpanded && !_searchFocus.hasFocus) {
                  _nearbyTileCtrl.collapse();
                }
              } catch (e) {
                debugPrint('Error: $e');
              }
              if (_showSearchList &&
                  _searchCtrl.text.isNotEmpty &&
                  _selectedPlace == null) {
                setState(() => _showSearchList = false);
                _searchFocus.unfocus();
              }
            }
          }
          return false;
        },
        child: DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: midS,
          minChildSize: minS,
          maxChildSize: maxS,
          snap: true,
          snapAnimationDuration: const Duration(milliseconds: 350),
          snapSizes: snaps,
          builder: (context, scrollController) {
            return ValueListenableBuilder<double>(
              valueListenable: _sheetProgress,
              builder: (context, progress, child) {
                // 🚀 FIX: Lerp header height from 62 (closed) → 76 (open) so closed state matches original
                final dynamicHeaderHeight = _showDirections ? 190.0 : (lerpDouble(62.0, 76.0, progress) ?? 62.0);
                const currentSideMargin = 16.0;
                final currentBottomMargin = 24.0 - (14.0 * progress);
                const sheetRadius = 50.0;

                final Color sheetBgColor = isDark
                    ? const Color(0xFF0B0E17).withValues(alpha: 0.80)
                    : Colors.white.withValues(alpha: 0.65);
                const double blurAmount = 30.0;

                return PointerInterceptor(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isDesktop ? 800 : 450,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // 🎨 PERFORMANCE FIX: RepaintBoundary around Blur
                          RepaintBoundary(
                            child: Container(
                              margin: EdgeInsets.only(
                                left: currentSideMargin,
                                right: currentSideMargin,
                                bottom: currentBottomMargin +
                                    MediaQuery.paddingOf(context).bottom,
                              ),
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(sheetRadius),
                                boxShadow: progress < 0.2
                                    ? [
                                        BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.3),
                                            blurRadius: 20,
                                            offset: const Offset(0, 8)),
                                        BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.1),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2)),
                                      ]
                                    : [
                                        BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.15),
                                            blurRadius: 8,
                                            offset: const Offset(0, -2)),
                                      ],
                              ),
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(sheetRadius),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                      sigmaX: blurAmount, sigmaY: blurAmount),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: sheetBgColor,
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.12),
                                        width: 1.0,
                                      ),
                                    ),
                                    child: ScrollConfiguration(
                                      behavior: ScrollConfiguration.of(context)
                                          .copyWith(
                                        scrollbars: false,
                                        dragDevices: {
                                          PointerDeviceKind.touch,
                                          PointerDeviceKind.mouse,
                                        },
                                      ),
                                      child: CustomScrollView(
                                        controller: scrollController,
                                        // 🚀 FIX: Removed BouncingScrollPhysics, replaced with ClampingScrollPhysics to prevent overscroll bouncing
                                        physics: const ClampingScrollPhysics(
                                            parent:
                                                AlwaysScrollableScrollPhysics()),
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior
                                                .onDrag,
                                        slivers: [
                                          SliverAppBar(
                                            pinned: true,
                                            elevation: 0,
                                            backgroundColor: Colors.transparent,
                                            collapsedHeight:
                                                dynamicHeaderHeight,
                                            toolbarHeight: dynamicHeaderHeight,
                                            flexibleSpace: GestureDetector(
                                              onTap: () {
                                                if (progress < 0.1) {
                                                  _expandToFull();
                                                }
                                              },
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              child: AnimatedSwitcher(
                                                duration: const Duration(
                                                  milliseconds: 500,
                                                ),
                                                switchInCurve: Curves.easeInCubic,
                                                switchOutCurve: Curves.easeOutCubic,
                                                child: _showDirections
                                                    ? _buildDirectionsHeader(
                                                        dynamicHeaderHeight,
                                                        isDark,
                                                      )
                                                    : (_selectedPlace != null
                                                        ? _buildSelectedPlaceHeader(
                                                            dynamicHeaderHeight,
                                                            progress,
                                                            isDark,
                                                          )
                                                        : _buildSearchHeader(
                                                            dynamicHeaderHeight,
                                                            progress,
                                                            isDark,
                                                          )),
                                              ),
                                            ),
                                          ),
                                          SliverToBoxAdapter(
                                            child: AnimatedOpacity(
                                              duration: const Duration(
                                                milliseconds: 150,
                                              ),
                                              opacity:
                                                  progress > 0.05 ? 1.0 : 0.0,
                                              child: progress > 0.05
                                                  ? _buildSheetContent(
                                                      isDark,
                                                      progress,
                                                    )
                                                  : const SizedBox(),
                                            ),
                                          ),
                                          SliverFillRemaining(
                                            hasScrollBody: false,
                                            child: Container(
                                              color: Colors.transparent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: -8,
                            left: 0,
                            right: 0,
                            child: _buildDynamicDragHandle(isDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
