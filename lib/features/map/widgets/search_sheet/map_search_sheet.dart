import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/features/map/map_engine/map_engine.dart';

import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/universal_mic_button.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/app_shadows.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';
import 'package:ridel/features/map/models/place_model.dart';
import 'package:ridel/features/map/services/master_search_service.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';
import 'package:ridel/features/map/services/map_share_service.dart';
import 'package:ridel/core/services/place_service.dart';
import 'package:ridel/features/map/services/place_api_services.dart';
import 'package:ridel/features/map/services/route_visualizer.dart';
import 'package:ridel/features/map/services/route_engine_service.dart';

import 'package:ridel/features/map/widgets/quick_action_buttons.dart';
import 'package:ridel/core/utils/route_utils.dart';

// 🚀 IMPORT YOUR NOTIFICATION SERVICE HERE
import 'package:ridel/core/services/notification_service.dart';
import 'package:ridel/core/utils/toast_service.dart';

// 🏠 SAVED PLACES LOCATION PICKER
import 'saved_places/location_picker_sheet.dart';
import 'saved_places/places_repository.dart' as saved;

// YE DONO FILES ISI KA HISSA HAIN (Do not change structure)
part 'search_sheet_headers.dart';
part 'search_sheet_views.dart';
part 'search_sheet_premium.dart';

enum SheetMode { search, placeDetail, routing }

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
  SheetMode _currentMode = SheetMode.search;

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _originCtrl = TextEditingController();
  final TextEditingController _destCtrl = TextEditingController();
  final FocusNode _originFocus = FocusNode();
  final FocusNode _destFocus = FocusNode();
  PlaceModel? _originPlace;
  PlaceModel? _destPlace;
  String? _activeRoutingField;

  final FocusNode _searchFocus = FocusNode();
  DraggableScrollableController get _sheetController =>
      Provider.of<MapProvider>(context, listen: false).sheetController;

  // ignore: deprecated_member_use

  // ignore: deprecated_member_use
  final ExpansionTileController _nearbyTileCtrl = ExpansionTileController();

  final MasterSearchService _searchService = MasterSearchService();
  final RouteEngineService _routeEngineService = RouteEngineService();
  List<PlaceModel> _searchResults = [];

  bool _isSearching = false;
  bool _isSearchMode = false;

  bool _showSearchList = false;
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

  bool _isDashVisible = true;
  Timer? _hideDashTimer;

  // Navigation Dashboard expansion state
  bool _isNavSheetExpanded = false;
  bool _wasKeyboardOpen = false;

  bool _isSearchExpanded = false;

  // 🏠 Saved Places Location Picker
  late final saved.PlacesRepository _placesRepository;
  late final LocationPickerController _locationPickerController;

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

  double _lastHapticExtent = -1.0;

  double get _safeMinSize {
    if (!mounted) return 0.15;
    // 🚀 FIX: Must divide by full screenHeight, because the parent SafeArea has top/bottom set to false!
    final screenHeight = MediaQuery.sizeOf(context).height;
    const double requiredPhysicalHeight = 70.0 + 44.0;
    return (requiredPhysicalHeight / screenHeight).clamp(0.05, 0.40);
  }

  double get _safeMidSize => 0.45;
  double get _safeMaxSize => 0.90;

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

  @override
  void initState() {
    super.initState();
    _isSearchMode = widget.isMapTabActive;

    // 🏠 Init Saved Places Location Picker
    _placesRepository = saved.PlacesRepository();
    _locationPickerController = LocationPickerController(_placesRepository);
    _locationPickerController.sheetState
        .addListener(_onLocationPickerStateChanged);

    _pokeDash();

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
      if (!mounted) return;
      if (_searchFocus.hasFocus) {
        _safeAnimateSheet(_safeMaxSize);
      }
      setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<MapProvider>(context, listen: false)
          .addListener(_onMapProviderUpdated);

      // 🚀 FIX: Broadcast initial height instantly to position Quick Access Buttons correctly on startup
      _sheetProgress.value = _safeMinSize;
      if (widget.onProgressChanged != null) {
        widget.onProgressChanged!(_safeMinSize);
      }
    });

    _searchCtrl.addListener(_onSearchChanged);
    unawaited(_handleGuestSessionHistory());
  }

  void _pokeDash() {
    if (!mounted) return;
    if (!_isDashVisible) {
      setState(() => _isDashVisible = true);
    }
    _hideDashTimer?.cancel();
    _hideDashTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isDashVisible = false);
    });
  }

  void _onLocationPickerStateChanged() {
    if (!mounted) return;
    final state = _locationPickerController.sheetState.value;

    if (state == SheetState.selectingLocation) {
      // 🚀 FIX: No longer listening to raw onCameraMove spam.
      // Reverse geocode is now triggered safely in _onMapProviderUpdated via MapProvider's onCameraIdle.

      // Trigger an initial reverse geocode
      final provider = Provider.of<MapProvider>(context, listen: false);
      final pos = provider.controller?.cameraPosition;
      if (pos != null) {
        _locationPickerController.onCameraMove(pos.target);
      }

      // Shrink sheet to show more map
      if (_sheetController.isAttached) {
        _safeAnimateSheet(_safeMinSize);
      }
    }
  }

  // Safe RAM filter that won't crash the widget tree
  List<PlaceModel> _getInstantLocalResults(String query) {
    if (query.isEmpty) return [];
    try {
      final lowerQuery = query.toLowerCase().trim();
      final allStops = DatabaseHelper.instance.instantCachedStops;

      return allStops
          .where((stop) {
            final stopName =
                (stop['stop_name'] ?? stop['name'] ?? '').toString();
            return stopName.toLowerCase().contains(lowerQuery);
          })
          .take(5)
          .map((stop) {
            return PlaceModel(
              placeId: stop['stop_id']?.toString() ?? '',
              name: stop['stop_name']?.toString() ??
                  stop['name']?.toString() ??
                  'Unknown Stop',
              address: 'Transit Stop',
              latitude: double.tryParse(
                      (stop['lat'] ?? stop['LAT'] ?? '0').toString()) ??
                  0.0,
              longitude: double.tryParse((stop['lon'] ??
                          stop['LON'] ??
                          stop['lng'] ??
                          stop['LNG'] ??
                          '0')
                      .toString()) ??
                  0.0,
              categories: stop['transport_mode'] == 0
                  ? ['metro_station']
                  : ['bus_station'],
            );
          })
          .toList();
    } catch (e) {
      debugPrint("Local Search Error: $e");
      return [];
    }
  }

  void _onSearchChanged() {
    _pokeDash();

    final query = _searchCtrl.text.trim();

    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
          if (!_showSearchList) _showSearchList = true;
        });
      }
      return;
    }

    // 🚀 1. INSTANT LOCAL SEARCH (0ms UI Update)
    final localResults = _getInstantLocalResults(query);
    setState(() {
      _showSearchList = true;
      if (localResults.isNotEmpty) {
        _searchResults = localResults;
        _isSearching = false; // Kill shimmer instantly if we have local data!
      } else {
        _isSearching = true; // Show shimmer only if RAM is empty
      }
    });

    _debounce?.cancel();

    // 🚀 2. BACKGROUND API SEARCH (500ms Debounce)
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      debugPrint("🔍 DEBUG SEARCH: Sending query -> '$query'");
      final cleanQuery = query.toLowerCase().trim();

      try {
        final globalLoc =
            Provider.of<GlobalLocationService>(context, listen: false);
        final pos = globalLoc.currentPosition;
        final latLng = pos != null ? LatLng(pos.latitude, pos.longitude) : null;

        // Fetch remote places silently
        final apiResults = await MasterSearchService().searchPlaces(
          cleanQuery,
          userLocation: latLng,
        );

        if (!mounted || _searchCtrl.text.trim() != query) return;

        setState(() {
          // Merge avoiding exact duplicates by name
          final combined = [...localResults];
          for (var apiItem in apiResults) {
            if (!combined.any((local) =>
                local.name.toLowerCase() == apiItem.name.toLowerCase())) {
              combined.add(apiItem);
            }
          }
          _searchResults = combined;
          _isSearching = false; // End shimmer
        });
      } catch (e) {
        if (mounted && _searchCtrl.text.trim() == query) {
          setState(() => _isSearching = false);
        }
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
      _pokeDash();
      unawaited(_slideController.forward());
      if (!_isSearchMode) {
        setState(() => _isSearchMode = true);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => widget.onSearchModeChanged(true));

        // 🚀 FIX: Reset to _safeMinSize instead of 0.0 to prevent button collapse
        _sheetProgress.value = _safeMinSize;
        if (widget.onProgressChanged != null) {
          widget.onProgressChanged!(_safeMinSize);
        }
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

  void _handleCancelRoute(BuildContext context, MapProvider provider) {
    FocusScope.of(context).unfocus();
    // 1. Cache the ENTIRE necessary state BEFORE clearing it
    final cachedPlace = _selectedPlace;
    final cachedCoords = provider.targetDestination;
    final cachedNavMode = provider.currentNavMode;
    final wasRouteCalculated = provider.isRouteCalculated;

    // 2. Clear the UI and Map
    provider.cancelAndClearRoute();
    setState(() {
      _selectedPlace = null;
      _currentMode = SheetMode.search;
      _isSearchExpanded = false;
      _searchCtrl.clear();
    });
    provider.setDropPinMode(false); // 🚨 CRITICAL FIX
    provider.setAddingStopMode(false); // 🚨 CRITICAL FIX

    if (_sheetController.isAttached) {
      _safeAnimateSheet(_safeMidSize);
    }

    // 3. Show the Undo Toast
    ToastService.showActionToast(context,
        message: "Route cleared", actionLabel: "UNDO", onActionTap: () async {
      AppHaptics.selectionClick();

      // RESTORE LOGIC:
      if (cachedPlace != null) {
        // A. Restore the basic place data and pin
        await _selectPlaceFromList(cachedPlace);

        // B. Restore the route if it was previously active
        if (wasRouteCalculated) {
          provider.currentNavMode = cachedNavMode;
          if (!context.mounted) return;
          await provider.calculateAndDrawNativeRoute(context, cachedNavMode);
        }
      } else if (cachedCoords != null) {
        // Fallback manual restore
        provider.addNativeDestinationPin(cachedCoords);
        provider.setTargetDestination(cachedCoords);
        provider.setDestinationSelected(true);
        provider.engine.setUIState(MapUIState.placeSelected);
      }
    });
  }

  Future<void> _selectPlaceFromList(PlaceModel place) async {
    FocusScope.of(context).unfocus(); // 🚀 KILL KEYBOARD FOCUS
    if (!mounted) return;
    final safeProvider = Provider.of<MapProvider>(context, listen: false);

    try {
      if (safeProvider.isAddingStopMode) {
        safeProvider.addIntermediateStop(place);
        safeProvider.setAddingStopMode(false);

        setState(() {
          _searchCtrl.clear();
        });

        if (_sheetController.isAttached) {
          _safeAnimateSheet(_safeMidSize);
        }

        FocusManager.instance.primaryFocus?.unfocus();
        return;
      }

      // 1. SAVE THE SEARCH TO HISTORY
      safeProvider.saveNewSearch(place);

      // 2. Lock State FIRST
      safeProvider.setDestinationSelected(true);
      safeProvider.engine.setUIState(MapUIState.placeSelected);

      // Safely animate sheet to Mid View size to show place details
      if (_sheetController.isAttached) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_sheetController.isAttached) {
            _safeAnimateSheet(_safeMidSize);
          }
        });
      }

      // 3. Process Coordinates
      double lat = place.latitude;
      double lng = place.longitude;

      if (lat == 0.0 || lng == 0.0) {
        if (place.placeId.isNotEmpty) {
          try {
            final exactCoords =
                await PlaceService.getPlaceDetails(place.placeId);
            if (exactCoords != null) {
              lat = exactCoords.latitude;
              lng = exactCoords.longitude;
            }
          } catch (_) {}
        }
      }

      // 4. Fly Camera
      if (lat != 0.0 && lng != 0.0) {
        await safeProvider.cancelAndClearRoute(resetCamera: false);
        // 🚀 TASK 1: FORCIBLY SEVER AUTO-TRACKING BEFORE CAMERA FLIGHT
        safeProvider.setAutoTracking(false);

        // 🔥 CRITICAL FIX 1: Explicitly break the native MapLibre GPS tracking lock! (Purged)

        safeProvider.setDestinationSelected(true);
        safeProvider.engine.setUIState(MapUIState.placeSelected);
        setState(() {
          _currentMode = SheetMode.search;
          _selectedPlace = place;
          _isSearchExpanded = false;
          _showSearchList = false;
          _searchResults.clear(); // 🚀 CLEAR LIST TO PREVENT OVERRIDE
          _isSearching = false;
        });
        if (!mounted) return;
        safeProvider.setTargetDestination(LatLng(lat, lng));
        if (_sheetController.isAttached) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _safeAnimateSheet(_safeMidSize);
          });
        }

        // Drop the native Red Circle at the selected place coordinates
        safeProvider.addNativeDestinationPin(LatLng(lat, lng));
        await safeProvider.flyToPlace(lat, lng);
      } else {
        if (mounted) {
          ToastService.showError(context, "Location coordinates not found.");
        }
      }

      widget.onSearchSubmitted(place.name);
    } catch (e) {
      debugPrint("💥 CRITICAL ERROR DURING PLACE SELECTION: $e");
    }
  }

  Future<void> _handleSearchExecution(String query,
      [PlaceModel? savedPlace]) async {
    _searchFocus.unfocus();
    if (query.trim().isEmpty) return;

    if (savedPlace != null &&
        savedPlace.latitude != 0.0 &&
        savedPlace.longitude != 0.0) {
      await _submitSearch(savedPlace);
      return;
    }

    // 🚀 INTERCEPT CATEGORY SEARCHES (Nearby Places)
    final lowerQuery = query.trim().toLowerCase();

    // RAM Cache Queries (Zero API)
    if (lowerQuery == 'metro' ||
        lowerQuery == 'metro stations' ||
        lowerQuery == 'bus stops') {
      final provider = Provider.of<MapProvider>(context, listen: false);
      await provider.showNearbyStopsOnMap(lowerQuery);

      // Collapse sheet to show the map
      if (_sheetController.isAttached) {
        _sheetController.animateTo(
          _safeMinSize,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      return;
    }

    // Network Queries (Overpass API)
    final otherCategories = [
      'petrol pumps',
      'railway stations',
      'hotels',
      'restaurants',
      'parking',
      'coffee',
      'cng',
      'gym'
    ];
    if (otherCategories.contains(lowerQuery)) {
      final provider = Provider.of<MapProvider>(context, listen: false);
      await provider.findAndShowNearby(lowerQuery, context);

      if (_sheetController.isAttached) {
        _sheetController.animateTo(
          _safeMinSize,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
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

    if (categoryQuery != null) {
      widget.onSearchSubmitted(categoryQuery);
    } else {
      PlaceModel? initialPlace = selectedPlace ??
          (_searchResults.isNotEmpty ? _searchResults.first : null);
      if (initialPlace != null) {
        PlaceModel placeToSubmit = initialPlace;
        // --- NEW: Fetch exact coordinates if they are 0.0 ---
        if (placeToSubmit.latitude == 0.0 || placeToSubmit.longitude == 0.0) {
          if (placeToSubmit.placeId.isNotEmpty) {
            try {
              final exactCoords =
                  await PlaceService.getPlaceDetails(placeToSubmit.placeId);
              if (exactCoords != null &&
                  exactCoords.latitude != 0.0 &&
                  exactCoords.longitude != 0.0) {
                placeToSubmit = PlaceModel(
                  placeId: placeToSubmit.placeId,
                  name: placeToSubmit.name,
                  address: placeToSubmit.address,
                  latitude: exactCoords.latitude,
                  longitude: exactCoords.longitude,
                  categories: placeToSubmit.categories,
                  rating: placeToSubmit.rating,
                  openingHours: placeToSubmit.openingHours,
                  phone: placeToSubmit.phone,
                  imageUrls: placeToSubmit.imageUrls,
                );
              }
            } catch (_) {
              // Silently fail to fallback
            }
          }
        }

        setState(() {
          _selectedPlace = placeToSubmit;
          _showSearchList = false;
          _showDirections = false;
          _currentMode = SheetMode.search;
          _isLoadingDetails = true;
          _isSearchExpanded = false;
        });

        if (!mounted) return;
        final provider = Provider.of<MapProvider>(context, listen: false);
        provider.setDestinationSelected(true);
        provider.engine.setUIState(MapUIState.placeSelected);

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
            if (placeToSubmit.latitude != 0.0 &&
                placeToSubmit.longitude != 0.0) {
              final validLatLng =
                  LatLng(placeToSubmit.latitude, placeToSubmit.longitude);

              if (!mounted) return;
              // Update provider with valid data
              final provider = Provider.of<MapProvider>(context, listen: false);
              await provider.cancelAndClearRoute(resetCamera: false);
              // 🚀 TASK 1: FORCIBLY SEVER AUTO-TRACKING BEFORE CAMERA FLIGHT
              provider.setAutoTracking(false);

              // 🔥 CRITICAL FIX 2: Explicitly break the native MapLibre GPS tracking lock! (Purged)

              provider.setDestinationSelected(true);
              provider.engine.setUIState(MapUIState.placeSelected);
              setState(() {
                _currentMode = SheetMode.search;
                _selectedPlace = placeToSubmit;
                _isSearchExpanded = false;
              });
              provider.setTargetDestination(validLatLng);
              provider.addNativeDestinationPin(validLatLng);

              // Safely fly camera
              await provider.flyToPlace(
                  validLatLng.latitude, validLatLng.longitude);
            } else {
              // CRITICAL FALLBACK: If coordinates are STILL missing, abort flight
              // and revert UI to prevent a permanent locked/broken state.
              debugPrint(
                  "🚨 ABORTING FLIGHT: Valid coordinates not found for this place.");
              if (!mounted) return;
              final provider = Provider.of<MapProvider>(context, listen: false);
              provider.setTargetDestination(null);
              provider.setDestinationSelected(false);
              provider.engine.setUIState(MapUIState.idle);
            }
          } catch (e) {
            debugPrint('⚠️ _submitSearch map wiring error: $e');
          }
        }

        try {
          final enrichedResult = await PlaceEnrichmentService()
              .getRichPlaceDetails(placeToSubmit.name, placeToSubmit.latitude,
                  placeToSubmit.longitude);
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
      _safeAnimateSheet(_safeMidSize);
    }

    _searchFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _searchCtrl.clear();
      }
    });
  }

  void _triggerAddStopFocus() {
    setState(() {
      _searchCtrl.clear();
      _searchFocus.requestFocus();
    });
  }

  void _openDirectionsView() {
    AppHaptics.mediumImpact();
    setState(() {
      _showDirections = true;
      _currentMode = SheetMode.routing;
      _isLoadingRoute = true;
      _routeErrorMessage = null;
      _destPlace = _selectedPlace;
      _destCtrl.text = _destPlace?.name ?? '';
      _originPlace = null;
      _originCtrl.text = 'Your Location';
      _activeRoutingField = null;
    });
    if (_sheetController.isAttached) {
      _safeAnimateSheet(_safeMidSize);
    }
    unawaited(_checkAndFetchRoute());
  }

  LatLng? _lastIdleCenter;

  void _onMapProviderUpdated() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = Provider.of<MapProvider>(context, listen: false);

      // 🚀 NEW: Hook location picker reverse geocode to map IDLE center updates
      if (_locationPickerController.sheetState.value ==
          SheetState.selectingLocation) {
        final currentCenter = provider.currentMapCenter;
        if (currentCenter != null && _lastIdleCenter != currentCenter) {
          // Only trigger if we moved significantly to avoid micro-jitter geocoding
          _lastIdleCenter = currentCenter;
          _locationPickerController.onCameraMove(currentCenter);
        }
      }

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
          _isNavSheetExpanded = false;
          _currentMode = SheetMode.search;
        });
      }

      if (provider.activeDestination != null) {
        final tappedPlace = provider.activeDestination!;
        provider.clearActiveDestination();

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
          provider.setDestinationSelected(true);
          provider.engine.setUIState(MapUIState.placeSelected);
          setState(() {
            _selectedPlace = tappedPlace;
            _searchCtrl.text = tappedPlace.name;
            _showSearchList = false;
            _showDirections = false;
            _currentMode = SheetMode.search;
            _isLoadingDetails = true;
          });
          if (_sheetController.isAttached) {
            _safeAnimateSheet(_safeMidSize);
          }
          unawaited(_fetchExtraDetailsForPlace(tappedPlace));
        }
      }
    });
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
      if (!mounted) return;
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

      debugPrint(
          "🛑 ROUTE DEBUG: Fetching route from ${originLoc.latitude},${originLoc.longitude} to ${destLoc.latitude},${destLoc.longitude}");
      final route = await _routeEngineService
          .getRoute(
            originLoc,
            destLoc,
            mode: activeMode,
          )
          .timeout(const Duration(seconds: 10));

      if (route == null) {
        debugPrint("🛑 ROUTE DEBUG FATAL: RoutingService returned NULL!");
      } else {
        debugPrint(
            "🛑 ROUTE DEBUG SUCCESS: Got ${route.coordinates.length} coordinates back!");
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
        debugPrint(
            "🛑 DEBUG ROUTE COORDS: Count = ${route.coordinates.length}");
      } else {
        if (_routeErrorMessage != null) {
          debugPrint("🛑 DEBUG ROUTE ERROR: $_routeErrorMessage");
        }
      }

      if (route != null) {
        if (!mounted) return;
        final mapCtrl = provider.controller;

        if (mapCtrl != null) {
          await RouteVisualizer.drawRoute(
              mapCtrl, route.coordinates, provider.currentTheme);

          // 🧭 State Machine: Route drawn → morph QuickActionButtons to "Start"
          provider.engine.setUIState(MapUIState.routeDrawn);

          // 🚀 CRITICAL FIX: Forcefully and smoothly collapse the sheet to the floating pill state!
          if (_sheetController.isAttached) {
            _safeAnimateSheet(_safeMinSize);
          }

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
      final enrichedResult = await PlaceEnrichmentService()
          .getRichPlaceDetails(place.name, place.latitude, place.longitude);
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
      _currentMode = SheetMode.search;
      _currentRoute = null;
      _activeRoutingField = null;
    });

    if (!mounted) return;
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    final mapCtrl = mapProvider.controller;

    if (mapCtrl != null) {
      unawaited(RouteVisualizer.clearRoute(mapCtrl));
      mapProvider.engine.onLocateMeTapped();
    }
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
    _pokeDash();
    if (!_sheetController.isAttached) return;
    if (_sheetController.size < (_safeMaxSize - 0.02)) {
      _safeAnimateSheet(_safeMaxSize);
    }
  }

  // ignore: unused_element
  Map<String, String>? _getBookingInfoForCurrentPlace() {
    if (_selectedPlace == null) return null;
    return _ticketBookingInfo[_selectedPlace!.name];
  }

  void _handleManualDragUpdate(DragUpdateDetails details) {
    _pokeDash();
    if (!_sheetController.isAttached) return;
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (screenHeight == 0) return;
    final delta = -details.primaryDelta! / screenHeight;
    final newSize =
        (_sheetController.size + delta).clamp(_safeMinSize, _safeMaxSize);
    _sheetController.jumpTo(newSize);
  }

  void _handleManualDragEnd(DragEndDetails details) {
    _pokeDash();
    if (!_sheetController.isAttached) return;
    final velocity = details.primaryVelocity ?? 0;
    final size = _sheetController.size;
    final snaps = <double>[_safeMinSize, _safeMidSize, _safeMaxSize];

    // 🚀 FIX: iOS-style snappy velocity release using easeOutCubic
    if (velocity < -300) {
      final next =
          snaps.firstWhere((s) => s > size + 0.02, orElse: () => _safeMaxSize);
      _safeAnimateSheet(next);
    } else if (velocity > 300) {
      final next =
          snaps.lastWhere((s) => s < size - 0.02, orElse: () => _safeMinSize);
      _safeAnimateSheet(next);
    } else {
      final closest =
          snaps.reduce((a, b) => (a - size).abs() < (b - size).abs() ? a : b);
      _safeAnimateSheet(closest);
    }
  }

  void _safeAnimateSheet(double targetSize) {
    // 1. Defers execution until the current layout frame is completely finished
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sheetController.isAttached) {
        // 2. Strict bounds check to prevent Flutter Engine crashes
        double safeSize = targetSize.clamp(_safeMinSize, 1.0);
        _sheetController.animateTo(
          safeSize,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _hideDashTimer?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    _originCtrl.dispose();
    _destCtrl.dispose();
    _originFocus.dispose();
    _destFocus.dispose();
    _searchFocus.dispose();
    _sheetProgress.dispose();
    _slideController.dispose();
    _locationPickerController.sheetState
        .removeListener(_onLocationPickerStateChanged);
    _locationPickerController.dispose();
    super.dispose();
  }

  Widget _buildGlassyBackground({
    required bool isDark,
    required Color sheetBgColor,
    required BorderRadius premiumRadius,
    required Color sheetBorderColor,
    required Widget child,
  }) {
    final innerContainer = Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: sheetBgColor,
        borderRadius: premiumRadius,
        border: Border(top: BorderSide(color: sheetBorderColor, width: 1.0)),
      ),
      child: child,
    );

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 35.0, sigmaY: 35.0),
      child: innerContainer,
    );
  }

  Widget _buildDynamicDragHandle(bool isDark) {
    return MouseRegion(
      onEnter: (_) => _pokeDash(),
      onHover: (_) => _pokeDash(),
      child: GestureDetector(
        onTapDown: (_) => _pokeDash(),
        onVerticalDragUpdate: _handleManualDragUpdate,
        onVerticalDragEnd: _handleManualDragEnd,
        behavior: HitTestBehavior.translucent,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _isDashVisible ? 1.0 : 0.0,
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
    final provider = Provider.of<MapProvider>(context, listen: false);
    final isActiveNavigation =
        context.select<MapProvider, bool>((p) => p.isActiveNavigation);
    final screenSize = MediaQuery.sizeOf(context);
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardOpen = keyboardHeight > 0;

    if (isKeyboardOpen && !_wasKeyboardOpen) {
      _wasKeyboardOpen = true;
      AppHaptics.lightImpact();
    } else if (!isKeyboardOpen && _wasKeyboardOpen) {
      _wasKeyboardOpen = false;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = screenSize.width > 600;

    // Header height is computed inside the builder where progress is available

    final isNav = isActiveNavigation;
    final navCollapsedHeight = 110.0 + MediaQuery.paddingOf(context).bottom;
    final navExpandedHeight = screenSize.height * 0.90;

    final navExpandedS =
        (navExpandedHeight / screenSize.height).clamp(0.0, 1.0);
    final navCollapsedS =
        (navCollapsedHeight / screenSize.height).clamp(0.0, 1.0);

    final minS = isNav ? navCollapsedS : _safeMinSize;
    final midS = isNav ? navExpandedS : _safeMidSize;
    final maxS = isNav ? navExpandedS : _safeMaxSize;

    // ❌ DELETE OR COMMENT OUT THIS ENTIRE ANIMATION BLOCK:
    /* 
    if ((_lastScreenHeight != 0 &&
            (_lastScreenHeight - screenSize.height).abs() > 20) ||
        (_lastScreenWidth != 0 &&
            (_lastScreenWidth - screenSize.width).abs() > 20)) {
      // 🚀 CRITICAL FIX: DO NOT ANIMATE SHEET HERE. IT CAUSES THE GHOST POP-OPEN BUG!
    }
    */
    // _lastScreenHeight and _lastScreenWidth removed

    final double currentMaxS = (isKeyboardOpen && !isNav)
        ? 1.0
        : (isNav
            ? maxS
            : ((_searchFocus.hasFocus ||
                    (_sheetController.isAttached &&
                        _sheetController.size > _safeMidSize + 0.02))
                ? maxS
                : _safeMidSize));

    var snaps = isNav
        ? <double>[minS, midS, maxS]
        : ((_searchFocus.hasFocus ||
                (_sheetController.isAttached &&
                    _sheetController.size > _safeMidSize + 0.02))
            ? <double>[minS, midS, maxS]
            : <double>[minS, midS]);
    snaps.sort();
    snaps = snaps.toSet().toList();

    // 🚨 Dynamic Height Calculation
    final double expandedHeight =
        screenSize.height - MediaQuery.paddingOf(context).top;
    final double defaultIdleHeight = screenSize.height;

    return RepaintBoundary(
        child: Stack(
      children: [
        AnimatedOpacity(
          opacity: (isKeyboardOpen && widget.isMapTabActive) ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: (isKeyboardOpen && widget.isMapTabActive)
              ? (kIsWeb
                  ? Container(color: Colors.black.withValues(alpha: 0.85))
                  : RepaintBoundary(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                        child: Container(
                            color: Colors.black.withValues(alpha: 0.3)),
                      ),
                    ))
              : const SizedBox.shrink(),
        ),
        Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutQuart,
                height: isActiveNavigation
                    ? null
                    : (isKeyboardOpen ? expandedHeight : defaultIdleHeight),
                padding: EdgeInsets.zero,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: isActiveNavigation
                      ? _buildNavigationDashboardOverlay(isDark)
                      : NotificationListener<Notification>(
                          onNotification: (notification) {
                            if (notification is ScrollEndNotification &&
                                notification.dragDetails != null) {
                              final velocity =
                                  notification.dragDetails!.primaryVelocity ??
                                      0;
                              if (velocity < -300 &&
                                  _sheetController.isAttached) {
                                _safeAnimateSheet(_safeMaxSize);
                              } else if (velocity > 300 &&
                                  _sheetController.isAttached) {
                                _safeAnimateSheet(_safeMinSize);
                              }
                            }

                            if (notification is ScrollUpdateNotification &&
                                notification.dragDetails != null) {
                              // Unfocus keyboard if the user drags the sheet down
                              if (notification.scrollDelta != null &&
                                  notification.scrollDelta! < 0 &&
                                  _searchFocus.hasFocus) {
                                _searchFocus.unfocus();
                              }
                            }

                            if (notification
                                is DraggableScrollableNotification) {
                              _pokeDash();

                              final extent = notification.extent;

                              // CRITICAL SYNC: If the user manually drags the sheet down near the half-state,
                              // forcefully switch the content back to the Idle (Home/Work) state.
                              if (extent <= _safeMidSize + 0.05 &&
                                  _isSearchExpanded) {
                                if (_searchFocus.hasFocus) {
                                  _searchFocus.unfocus();
                                }
                                rebuildState(() => _isSearchExpanded = false);
                              }
                              // If the user drags it up near the top, ensure it switches to the Expanded content.
                              else if (extent >= _safeMaxSize - 0.05 &&
                                  !_isSearchExpanded) {
                                rebuildState(() => _isSearchExpanded = true);
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

                              final progress = notification.extent;
                              if (_sheetProgress.value != progress) {
                                _sheetProgress.value = progress;
                                if (widget.onProgressChanged != null) {
                                  widget.onProgressChanged!(progress);
                                }
                              }
                              if (progress < 0.65) {
                                try {
                                  if (_nearbyTileCtrl.isExpanded &&
                                      !_searchFocus.hasFocus) {
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
                          child: SafeArea(
                            bottom: false,
                            top: false, // Don't restrict the top
                            child: DraggableScrollableSheet(
                              controller: _sheetController,
                              initialChildSize:
                                  (isKeyboardOpen && !isNav) ? 1.0 : minS,
                              minChildSize: minS,
                              maxChildSize: currentMaxS,
                              snap: true,
snapAnimationDuration:
                                  const Duration(milliseconds: 350),
                              snapSizes: snaps,
                              builder: (context, scrollController) {
                                return ValueListenableBuilder<double>(
                                  valueListenable: _sheetProgress,
                                  builder: (context, progress, child) {
                                    // 🚀 1. DISCRETE STATE LOCKS (Kills 60fps processor recalculations)
                                    // Transforms continuous drag values into strict boolean states
                                    final bool isClosedMode = progress <= (minS + 0.05);
                                    final bool isFullyOpen = progress >= (maxS - 0.02);

                                    final double staticHeaderHeight = provider.isActiveNavigation
                                        ? (_isNavSheetExpanded ? navExpandedHeight - 40 : navCollapsedHeight)
                                        : (_showDirections ? 190.0 : 70.0);

                                    final Color sheetBgColor = isDark 
                                        ? const Color(0xFF0B0E17).withValues(alpha: 0.70) 
                                        : Colors.white.withValues(alpha: 0.70);

                                    return PointerInterceptor(
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            // 🚀 2. ABSOLUTE HEIGHT MANAGEMENT (Stops unpredictable stretching)
                                            final double shellHeight = provider.isActiveNavigation
                                                ? (_isNavSheetExpanded ? navExpandedHeight : navCollapsedHeight)
                                                : (_showDirections 
                                                    ? 190.0 // Strictly locked for Directions View
                                                    : (isClosedMode ? 70.0 : (isFullyOpen ? constraints.maxHeight : (constraints.maxHeight - 44.0))));

                                            return ConstrainedBox(
                                              constraints: BoxConstraints(maxWidth: isDesktop ? 800 : 400),
                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                // 🚀 3. BOTTOM ALIGNMENT LOCK (Anchors the pill rigidly to the floor)
                                                // Prevents the pill from ever floating upwards when sheet extent shifts!
                                                alignment: Alignment.bottomCenter, 
                                                children: [
                                                  AnimatedContainer( // Smooth morph only on state changes!
                                                      duration: const Duration(milliseconds: 250),
                                                      curve: Curves.easeOutCubic,
                                                      clipBehavior: Clip.hardEdge,
                                                      height: shellHeight,
                                                      margin: EdgeInsets.only(
                                                        left: isFullyOpen ? 0.0 : (isClosedMode ? 24.0 : 16.0),
                                                        right: isFullyOpen ? 0.0 : (isClosedMode ? 24.0 : 16.0),
                                                        // 🚀 THE PERFECT PREMIUM FIX:
                                                        // - isFullyOpen: Flush to screen (0.0)
                                                        // - isClosedMode: Stays at the original 44.0 to preserve the idle look.
                                                        // - Mid-State: Smoothly expands to 16.0 (matching the sides) + bottom safe area to clear the home bar.
                                                        bottom: isFullyOpen 
                                                            ? 0.0 
                                                            : (isClosedMode 
                                                                ? 44.0 
                                                                : 16.0 + MediaQuery.paddingOf(context).bottom),
                                                      ),
                                                      decoration: BoxDecoration(
                                                        borderRadius: BorderRadius.circular(35.0),
                                                        boxShadow: isDark
                                                            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))]
                                                            : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 32, offset: const Offset(0, 12))],
                                                      ),
                                                      child: ClipRRect(
                                                        borderRadius: BorderRadius.circular(35.0),
                                                        child: _buildGlassyBackground(
                                                          isDark: isDark,
                                                          sheetBgColor: sheetBgColor,
                                                          premiumRadius: BorderRadius.circular(35.0),
                                                          sheetBorderColor: isDark ? const Color(0xFF7CA1FF).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.9),
                                                          child: Stack(
                                                            children: [
                                                              // Bottom Layer: Scrollable Content
                                                              Positioned.fill(
                                                                child:
                                                                    ShaderMask(
                                                                  shaderCallback:
                                                                      (Rect
                                                                          bounds) {
                                                                    // Calculate exact normalized stop for the dynamic header
                                                                    final fadeStop = (staticHeaderHeight / bounds.height).clamp(0.0, 1.0);
                                                                    final fadeStart = (fadeStop -
                                                                            0.05)
                                                                        .clamp(
                                                                            0.0,
                                                                            1.0);
                                                                    return LinearGradient(
                                                                      begin: Alignment
                                                                          .topCenter,
                                                                      end: Alignment
                                                                          .bottomCenter,
                                                                      colors: const [
                                                                        Colors
                                                                            .transparent,
                                                                        Colors
                                                                            .transparent,
                                                                        Colors
                                                                            .black,
                                                                        Colors
                                                                            .black
                                                                      ],
                                                                      stops: [
                                                                        0.0,
                                                                        fadeStart,
                                                                        fadeStop,
                                                                        1.0
                                                                      ],
                                                                    ).createShader(
                                                                        bounds);
                                                                  },
                                                                  blendMode:
                                                                      BlendMode
                                                                          .dstIn,
                                                                  child:
                                                                      ScrollConfiguration(
                                                                    behavior: ScrollConfiguration.of(
                                                                            context)
                                                                        .copyWith(
                                                                      scrollbars:
                                                                          false,
                                                                      dragDevices: {
                                                                        PointerDeviceKind
                                                                            .touch,
                                                                        PointerDeviceKind
                                                                            .mouse
                                                                      },
                                                                    ),
                                                                    child:
                                                                        CustomScrollView(
                                                                      controller:
                                                                          scrollController,
                                                                      physics: const ClampingScrollPhysics(
                                                                          parent:
                                                                              AlwaysScrollableScrollPhysics()),
                                                                      keyboardDismissBehavior:
                                                                          ScrollViewKeyboardDismissBehavior
                                                                              .onDrag,
                                                                      slivers: [
                                                                        SliverPadding(
                                                                          padding: EdgeInsets.only(top: staticHeaderHeight),
                                                                        ),
                                                                        SliverToBoxAdapter(
                                                                          child:
                                                                              AnimatedOpacity(
                                                                            duration:
                                                                                const Duration(milliseconds: 150),
                                                                            opacity: (!provider.isActiveNavigation && !isClosedMode) ? 1.0 : 0.0,
                                                                            child:
                                                                                AnimatedSwitcher(
                                                                              duration: const Duration(milliseconds: 300),
                                                                              transitionBuilder: (Widget child, Animation<double> animation) {
                                                                                return FadeTransition(
                                                                                  opacity: animation,
                                                                                  child: SlideTransition(
                                                                                    position: Tween<Offset>(
                                                                                      begin: const Offset(0.0, 0.05),
                                                                                      end: Offset.zero,
                                                                                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                                                                                    child: child,
                                                                                  ),
                                                                                );
                                                                              },
                                                                              child: (!provider.isActiveNavigation && !isClosedMode) ? _buildSheetContent(isDark, progress, isExpanded: isKeyboardOpen) : const SizedBox.shrink(),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        SliverPadding(
                                                                          padding:
                                                                              EdgeInsets.only(bottom: keyboardHeight),
                                                                        ),
                                                                        SliverFillRemaining(
                                                                          hasScrollBody:
                                                                              false,
                                                                          child:
                                                                              Container(color: Colors.transparent),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              // Top Layer: Floating Header with Gradient Fade
                                                              Positioned(
                                                                top: 0,
                                                                left: 0,
                                                                right: 0,
                                                                child: Container(
                                                                  color: Colors.transparent,
                                                                  height: staticHeaderHeight,
                                                                  child:
                                                                      GestureDetector(
                                                                    onTap: () {
                                                                      if (progress <
                                                                          0.1) {
                                                                        _expandToFull();
                                                                      }
                                                                    },
                                                                    behavior:
                                                                        HitTestBehavior
                                                                            .translucent,
                                                                    child:
                                                                        AnimatedSwitcher(
                                                                      duration: const Duration(
                                                                          milliseconds:
                                                                              500),
                                                                      switchInCurve:
                                                                          Curves
                                                                              .easeInCubic,
                                                                      switchOutCurve:
                                                                          Curves
                                                                              .easeOutCubic,
                                                                      child: _showDirections
                                                                          ? _buildDirectionsHeader(staticHeaderHeight, isDark)
                                                                          : (_selectedPlace != null
                                                                              ? _buildSelectedPlaceHeader(staticHeaderHeight, progress, isDark)
                                                                              : _buildSearchHeader(staticHeaderHeight, progress, isDark)),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  Positioned(
                                                    top: -7.5,
                                                    left: 0,
                                                    right: 0,
                                                    child:
                                                        _buildDynamicDragHandle(
                                                            isDark),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                ))),
        // 🗺️ FLOATING MAP PIN OVERLAY (visible only when picking a location)
        ValueListenableBuilder<SheetState>(
          valueListenable: _locationPickerController.sheetState,
          builder: (context, state, child) {
            if (state != SheetState.selectingLocation) {
              return const SizedBox.shrink();
            }
            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: screenSize.height * 0.45, // Pin sits above the sheet
              child: IgnorePointer(
                child: Center(
                  child: child!,
                ),
              ),
            );
          },
          child: const AnimatedMapPin(),
        ),
      ],
    ));
  }
}
