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
import 'package:ridel/core/services/place_service.dart';
import 'package:ridel/features/map/services/place_api_services.dart';
import 'package:ridel/features/map/services/route_visualizer.dart';
import 'package:ridel/features/map/services/route_engine_service.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart';
import 'package:ridel/features/map/widgets/quick_action_buttons.dart';
import 'package:ridel/core/services/notification_service.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/services/saved_places_service.dart';

part 'search_sheet_headers.dart';
part 'search_sheet_views.dart';
part 'search_sheet_premium.dart';

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
  MapProvider? _mapProviderRef;
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
  final ExpansionTileController _nearbyTileCtrl = ExpansionTileController();

  final MasterSearchService _searchService = MasterSearchService();
  final RouteEngineService _routeEngineService = RouteEngineService();
  List<PlaceModel> _searchResults = [];

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

  bool _showDragHandle = true;
  Timer? _dragHandleTimer;

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  final ValueNotifier<bool> _isDraggingNotifier = ValueNotifier(false);

  static const Color premiumBlue = Color(0xFF0A84FF);

  // ignore: unused_field
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
    if (!mounted) {
      return 0.15;
    }
    final screenSize = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final requiredHeight = 86.0 + safeBottom;
    return (requiredHeight / screenSize.height).clamp(0.05, 0.40);
  }

  double get _safeMidSize => 0.35;
  double get _safeMaxSize => 0.55;

  void rebuildState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

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

      Map<String, dynamic>? data;
      if (user != null) {
        data = await supabase
            .from('user_profiles')
            .select('home_place, work_place')
            .eq('id', user.id)
            .maybeSingle();
      }

      if (!mounted) {
        return;
      }

      final column = type == 'HOME' ? 'home_place' : 'work_place';
      final savedPlace = data?[column];

      if (savedPlace != null && savedPlace['latitude'] != null) {
        _searchFocus.unfocus();
        if (_sheetController.isAttached) {
          _safeAnimateSheet(_safeMinSize);
        }

        final lat = (savedPlace['latitude'] as num).toDouble();
        final lng = (savedPlace['longitude'] as num).toDouble();

        final mapProvider = Provider.of<MapProvider>(context, listen: false);
        await mapProvider.flyToPlace(lat, lng);
        if (!mounted) {
          return;
        }
        mapProvider.setDestinationSelected(true);
        await mapProvider.calculateAndDrawNativeRoute(
            context, mapProvider.currentNavMode);
        AppHaptics.success();
      } else {
        setState(() => _selectedActionType = type);

        final mapProvider = Provider.of<MapProvider>(context, listen: false);
        mapProvider.setMapSelectionMode(type);

        if (_sheetController.isAttached) {
          _safeAnimateSheet(_safeMinSize);
        }

        _showPremiumNotification('Tap anywhere on the map to set $type');
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
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 1.2), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOutExpo,
      ),
    );

    if (widget.isMapTabActive) {
      unawaited(_slideController.forward());
    }

    _searchFocus.addListener(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapProviderRef = Provider.of<MapProvider>(context, listen: false);
      _mapProviderRef?.addListener(_onMapProviderUpdated);
    });

    _searchCtrl.addListener(_onSearchChanged);
    unawaited(_handleGuestSessionHistory());
  }

  void _wakeUpDragHandle({bool forceReset = false}) {
    if (!mounted) {
      return;
    }
    if (!_showDragHandle) {
      setState(() => _showDragHandle = true);
    }

    if (!forceReset && _isDraggingNotifier.value) return;

    _dragHandleTimer?.cancel();
    _dragHandleTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_isDraggingNotifier.value) {
        setState(() => _showDragHandle = false);
      }
    });
  }

  void _onSearchChanged() {
    _wakeUpDragHandle();

    // 🚀 FIX 1: ALWAYS cancel the previous timer first!
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    final currentQuery = _searchCtrl.text.trim();

    if (currentQuery.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
          if (!_showSearchList) {
            _showSearchList = true;
          }
        });
      }
      return;
    }

    setState(() {
      _isSearching = true;
      _showSearchList = true;
    });

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return; // 🚀 FIX 2: Prevent Unmounted Context Crash
      final globalLoc =
          Provider.of<GlobalLocationService>(context, listen: false);
      final pos = globalLoc.currentPosition;
      final latLng = pos != null ? LatLng(pos.latitude, pos.longitude) : null;

      final results = await MasterSearchService().searchPlaces(
        currentQuery,
        userLocation: latLng,
      );

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

  void _handleCancelRoute(BuildContext context, MapProvider provider) {
    final cachedPlace = _selectedPlace;
    final cachedCoords = provider.targetDestination;
    final cachedNavMode = provider.currentNavMode;
    final wasRouteCalculated = provider.isRouteCalculated;

    provider.cancelAndClearRoute();

    ToastService.showActionToast(context,
        message: "Route cleared", actionLabel: "UNDO", onActionTap: () async {
      AppHaptics.selectionClick();
      if (cachedPlace != null) {
        await _selectPlaceFromList(cachedPlace);
        if (wasRouteCalculated) {
          provider.currentNavMode = cachedNavMode;
          if (!context.mounted) {
            return;
          }
          await provider.calculateAndDrawNativeRoute(context, cachedNavMode);
        }
      } else if (cachedCoords != null) {
        provider.addNativeDestinationPin(cachedCoords);
        provider.setTargetDestination(cachedCoords);
        provider.setDestinationSelected(true);
        provider.engine.setUIState(MapUIState.placeSelected);
      }
    });
  }

  Future<void> _selectPlaceFromList(PlaceModel place) async {
    final safeProvider = Provider.of<MapProvider>(context, listen: false);

    try {
      safeProvider.saveNewSearch(place);
      safeProvider.setDestinationSelected(true);
      safeProvider.engine.setUIState(MapUIState.placeSelected);

      if (_sheetController.isAttached) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_sheetController.isAttached) {
            _sheetController.animateTo(
              _safeMinSize,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }

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

      if (lat != 0.0 && lng != 0.0) {
        if (!mounted) return;
        safeProvider.setTargetDestination(LatLng(lat, lng));
        setState(() => _selectedPlace = place);
        if (_sheetController.isAttached) {
          _sheetController.animateTo(
            _safeMinSize,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
        await safeProvider.flyToPlace(lat, lng);
        safeProvider.addNativeDestinationPin(LatLng(lat, lng));
      } else {
        if (mounted) {
          ToastService.showError(context, "Location coordinates not found.");
        }
      }

      widget.onSearchSubmitted(place.name);
    } catch (e) {
      debugPrint("💥 CRITICAL ERROR: $e");
    }
  }

  Future<void> _handleSearchExecution(String query,
      [PlaceModel? savedPlace]) async {
    _searchFocus.unfocus();
    if (query.trim().isEmpty) {
      return;
    }

    if (savedPlace != null &&
        savedPlace.latitude != 0.0 &&
        savedPlace.longitude != 0.0) {
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
      return;
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

        if (placeToSubmit.latitude == 0.0 || placeToSubmit.longitude == 0.0) {
          if (placeToSubmit.placeId.isNotEmpty) {
            try {
              final exactCoords =
                  await PlaceService.getPlaceDetails(placeToSubmit.placeId);
              if (exactCoords != null &&
                  exactCoords.latitude != 0.0 &&
                  exactCoords.longitude != 0.0) {
                // 🚀 UX/LINT FIX: copyWith undefined error replaced with manual constructor
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
            } catch (_) {}
          }
        }

        if (!mounted) return;
        setState(() {
          _selectedPlace = placeToSubmit;
          _showSearchList = false;
          _showDirections = false;
          _isLoadingDetails = true;
        });

        await _searchService.saveToHistory(placeToSubmit);
        if (!mounted) {
          return;
        }

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

        if (!mounted) {
          return;
        }

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
              if (!mounted) {
                return;
              }
              _showPremiumNotification(
                  "${_selectedActionType == 'HOME' ? 'Home' : 'Work'} location updated successfully!");
            } else {
              if (_selectedActionType == 'HOME') {
                await SavedPlacesService.saveHome(placeToSubmit);
              } else {
                await SavedPlacesService.saveWork(placeToSubmit);
              }
              if (!mounted) return;
              _showPremiumNotification(
                  "${_selectedActionType == 'HOME' ? 'Home' : 'Work'} location updated locally!");
            }
          } catch (_) {}
          _selectedActionType = null;
        }

        widget.onSearchSubmitted(
            '${placeToSubmit.latitude},${placeToSubmit.longitude}');

        if (mounted) {
          try {
            if (placeToSubmit.latitude != 0.0 &&
                placeToSubmit.longitude != 0.0) {
              final validLatLng =
                  LatLng(placeToSubmit.latitude, placeToSubmit.longitude);
              final provider = Provider.of<MapProvider>(context, listen: false);
              provider.setTargetDestination(validLatLng);
              provider.addNativeDestinationPin(validLatLng);
              await provider.flyToPlace(
                  validLatLng.latitude, validLatLng.longitude);
            } else {
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
          if (mounted) {
            setState(() => _isLoadingDetails = false);
          }
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
      _safeAnimateSheet(_safeMinSize);
    }

    _searchFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _searchCtrl.clear();
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
      _safeAnimateSheet(_safeMidSize);
    }
    unawaited(_checkAndFetchRoute());
  }

  void _onMapProviderUpdated() async {
    if (!mounted) {
      return;
    }
    final provider = Provider.of<MapProvider>(context, listen: false);

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
          _safeAnimateSheet(_safeMidSize);
        }
        unawaited(_fetchExtraDetailsForPlace(tappedPlace));
      }
    }
  }

  Future<void> _checkAndFetchRoute() async {
    if (_destPlace == null && _selectedPlace == null) {
      return;
    }

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
        if (!mounted) return; // 🚀 FIX: Prevent orphaned execution
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
      if (!mounted) {
        return;
      }
      final provider = Provider.of<MapProvider>(context, listen: false);
      final activeMode = provider.currentNavMode;

      final route = await _routeEngineService
          .getRoute(originLoc, destLoc, mode: activeMode)
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          _currentRoute = route;
          _isLoadingRoute = false;
          if (route == null) {
            _routeErrorMessage = 'Route unavailable.';
          }
        });
      }

      if (route != null) {
        if (!mounted) {
          return;
        }
        final mapCtrl = provider.controller;

        if (mapCtrl != null) {
          await RouteVisualizer.drawRoute(
              mapCtrl, route.coordinates, provider.currentTheme);
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
      final enrichedResult = await PlaceEnrichmentService()
          .getRichPlaceDetails(place.name, place.latitude, place.longitude);
      if (mounted) {
        setState(() {
          _enrichedDetails = enrichedResult;
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDetails = false);
      }
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

  // ignore: unused_element
  Future<void> _initiatePhoneCall() async {
    if (_enrichedDetails?.osmPhone == null) {
      return;
    }
    final url = Uri.parse('tel:${_enrichedDetails!.osmPhone!}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  // ignore: unused_element
  Future<void> _openWebsite() async {
    if (_enrichedDetails?.osmWebsite == null) {
      return;
    }
    final url = Uri.parse(_enrichedDetails!.osmWebsite!);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _expandToFull() {
    _wakeUpDragHandle();
    if (!_sheetController.isAttached) {
      return;
    }
    if (_sheetController.size < (_safeMaxSize - 0.02)) {
      _safeAnimateSheet(_safeMaxSize);
    }
  }

  void _handleCancelTap() {
    AppHaptics.lightImpact();

    final provider = Provider.of<MapProvider>(context, listen: false);

    if (provider.targetDestination == null) {
      FocusScope.of(context).unfocus();

      bool hasText = _searchCtrl.text.isNotEmpty;
      bool isExpanded = _sheetController.isAttached &&
          _sheetController.size > (_safeMinSize + 0.05);
      bool isActivelySearching = hasText ||
          provider.engine.mapUIState.value != MapUIState.idle ||
          isExpanded;

      if (isActivelySearching) {
        _searchCtrl.clear();
        if (_sheetController.isAttached) {
          _safeAnimateSheet(_safeMinSize);
        }
        if (provider.engine.mapUIState.value != MapUIState.idle) {
          provider.engine.setUIState(MapUIState.idle);
        }
      } else {
        setState(() => _isSearchMode = false);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => widget.onSearchModeChanged(false));
        widget.onBackToPreviousTab();
      }
      return;
    }

    final backupCoords = provider.targetDestination!;
    final bool wasRouteDrawn = provider.isRouteCalculated;
    // 🚀 FIX: Resolved isNavigating property mismatch error
    final bool wasNavigating = provider.isActiveNavigation;

    final backupPlace = _selectedPlace;
    final backupDestPlace = _destPlace;
    final backupOriginPlace = _originPlace;
    final backupSearchText = _searchCtrl.text;
    final backupActiveField = _activeRoutingField;
    final backupRoute = _currentRoute;
    final backupShowSearchList = _showSearchList;
    final backupShowDirections = _showDirections;
    final double backupSheetSize =
        _sheetController.isAttached ? _sheetController.size : _safeMinSize;

    provider.clearNativeRoute();
    provider.clearNativeDestinationPin();
    provider.setTargetDestination(null);
    provider.setDestinationSelected(false);
    FocusScope.of(context).unfocus();

    ToastService.showActionToast(
      context,
      message: 'Route cancelled',
      actionLabel: 'UNDO',
      onActionTap: () async {
        provider.setTargetDestination(backupCoords);
        provider.setDestinationSelected(true);

        setState(() {
          _selectedPlace = backupPlace;
          _destPlace = backupDestPlace;
          _originPlace = backupOriginPlace;
          _searchCtrl.text = backupSearchText;
          _activeRoutingField = backupActiveField;
          _currentRoute = backupRoute;
          _showSearchList = backupShowSearchList;
          _showDirections = backupShowDirections;
        });

        await provider.addNativeDestinationPin(backupCoords);
        if (wasRouteDrawn || wasNavigating) {
          if (mounted) {
            await provider.calculateAndDrawNativeRoute(
                context, provider.currentNavMode);
            if (wasNavigating) {
              await provider.start3DNavigation();
            }
          }
        }

        if (mounted && _sheetController.isAttached) {
          _safeAnimateSheet(backupSheetSize);
        }
      },
    );
  }

  // ignore: unused_element
  Map<String, String>? _getBookingInfoForCurrentPlace() {
    if (_selectedPlace == null) {
      return null;
    }
    return _ticketBookingInfo[_selectedPlace!.name];
  }

  void _handleManualDragUpdate(DragUpdateDetails details) {
    _wakeUpDragHandle();
    _isDraggingNotifier.value = true;
    if (!_sheetController.isAttached) {
      return;
    }
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (screenHeight == 0) {
      return;
    }
    final delta = -details.primaryDelta! / screenHeight;
    final newSize =
        (_sheetController.size + delta).clamp(_safeMinSize, _safeMaxSize);
    _sheetController.jumpTo(newSize);
  }

  void _handleManualDragEnd(DragEndDetails details) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _isDraggingNotifier.value = false;
        _wakeUpDragHandle(forceReset: true); // 🚀 FIX: Call AFTER state resets
      }
    });

    if (!_sheetController.isAttached) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final size = _sheetController.size;
    final snaps = <double>[_safeMinSize, _safeMidSize, _safeMaxSize];

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sheetController.isAttached) {
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
    _mapProviderRef?.removeListener(_onMapProviderUpdated);

    _dragHandleTimer?.cancel();
    _debounce?.cancel();
    _sheetController.dispose();
    _searchCtrl.dispose();
    _originCtrl.dispose();
    _destCtrl.dispose();

    _searchFocus.unfocus();
    _originFocus.unfocus();
    _destFocus.unfocus();

    _originFocus.dispose();
    _destFocus.dispose();
    _searchFocus.dispose();
    _sheetProgress.dispose();
    _isDraggingNotifier.dispose();
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
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardOpen = keyboardHeight > 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = screenSize.width > 600;

    final minS = _safeMinSize;
    final midS = _safeMidSize;
    final maxS = _safeMaxSize;

    var snaps = <double>[minS, midS, maxS];
    snaps.sort();
    snaps = snaps.toSet().toList();

    final double expandedHeight = screenSize.height -
        keyboardHeight -
        MediaQuery.paddingOf(context).top -
        20;
    final double defaultIdleHeight = screenSize.height;

    return Stack(
      children: [
        AnimatedOpacity(
          opacity: (isKeyboardOpen && widget.isMapTabActive) ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          // 🚀 FIX: Keep child in tree for smooth fade-out, just ignore touches
          child: IgnorePointer(
            ignoring: !(isKeyboardOpen && widget.isMapTabActive),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
              child: Container(color: Colors.black.withValues(alpha: 0.3)),
            ),
          ),
        ),
        Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                height: isKeyboardOpen ? expandedHeight : defaultIdleHeight,
                padding: const EdgeInsets.only(bottom: 0),
                child: SlideTransition(
                  position: _slideAnimation,
                  child: NotificationListener<Notification>(
                    onNotification: (notification) {
                      if (notification is ScrollStartNotification &&
                          notification.depth == 0) {
                        if (!_isDraggingNotifier.value) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _isDraggingNotifier.value = true;
                          });
                        }
                      }
                      if (notification is ScrollEndNotification &&
                          notification.depth == 0) {
                        if (_isDraggingNotifier.value) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              _isDraggingNotifier.value = false;
                              _wakeUpDragHandle(forceReset: true);
                            }
                          });
                        }
                      }

                      if (notification is ScrollEndNotification &&
                          notification.dragDetails != null) {
                        final velocity =
                            notification.dragDetails!.primaryVelocity ?? 0;
                        if (velocity < -300 && _sheetController.isAttached) {
                          _safeAnimateSheet(_safeMaxSize);
                        } else if (velocity > 300 &&
                            _sheetController.isAttached) {
                          _safeAnimateSheet(_safeMinSize);
                        }
                      }

                      if (notification is ScrollUpdateNotification &&
                          notification.dragDetails != null) {
                        if (notification.scrollDelta != null &&
                            notification.scrollDelta! < 0 &&
                            _searchFocus.hasFocus) {
                          _searchFocus.unfocus();
                        }
                      }

                      if (notification is DraggableScrollableNotification) {
                        _wakeUpDragHandle();

                        final extent = notification.extent;
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

                        final progress =
                            ((notification.extent - notification.minExtent) /
                                    (notification.maxExtent -
                                        notification.minExtent))
                                .clamp(0.0, 1.0);
                        if ((_sheetProgress.value - progress).abs() > 0.005) {
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
                    child: DraggableScrollableSheet(
                      controller: _sheetController,
                      initialChildSize: isKeyboardOpen ? 1.0 : midS,
                      minChildSize: minS,
                      maxChildSize: isKeyboardOpen ? 1.0 : maxS,
                      snap: true,
                      snapAnimationDuration: const Duration(milliseconds: 350),
                      snapSizes: snaps,
                      builder: (BuildContext context,
                          ScrollController scrollController) {
                        // 🚀 FIX: Pure static sliver height to prevent layout recalculations
                        final double staticHeaderHeight =
                            _showDirections ? 190.0 : 76.0;
                        const double sheetRadius = 50.0;

                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: PointerInterceptor(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: isDesktop ? 800 : 450,
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    margin: EdgeInsets.only(
                                      left: 16.0,
                                      right: 16.0,
                                      bottom: 10.0 +
                                          MediaQuery.paddingOf(context).bottom,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(sheetRadius),
                                      boxShadow: [
                                        BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.15),
                                            blurRadius: 10,
                                            offset: const Offset(0, -2)),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(sheetRadius),
                                      child: ValueListenableBuilder<bool>(
                                        valueListenable: _isDraggingNotifier,
                                        builder: (context, isDragging, child) {
                                          final double blurAmount =
                                              isDragging ? 0.0 : 12.0;
                                          final double bgOpacity = isDragging
                                              ? 0.95
                                              : (isDark ? 0.80 : 0.65);
                                          final Color sheetBgColor = isDark
                                              ? const Color(0xFF0B0E17)
                                                  .withValues(alpha: bgOpacity)
                                              : Colors.white
                                                  .withValues(alpha: bgOpacity);

                                          return BackdropFilter(
                                            filter: ImageFilter.blur(
                                                sigmaX: blurAmount,
                                                sigmaY: blurAmount),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: sheetBgColor,
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.12),
                                                  width: 1.0,
                                                ),
                                              ),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: RepaintBoundary(
                                          child: ScrollConfiguration(
                                            behavior:
                                                ScrollConfiguration.of(context)
                                                    .copyWith(
                                              scrollbars: false,
                                              dragDevices: {
                                                PointerDeviceKind.touch,
                                                PointerDeviceKind.mouse,
                                              },
                                            ),
                                            child: CustomScrollView(
                                              controller: scrollController,
                                              physics: isKeyboardOpen
                                                  ? const NeverScrollableScrollPhysics()
                                                  : const ClampingScrollPhysics(
                                                      parent:
                                                          AlwaysScrollableScrollPhysics()),
                                              keyboardDismissBehavior:
                                                  ScrollViewKeyboardDismissBehavior
                                                      .onDrag,
                                              slivers: [
                                                SliverAppBar(
                                                  pinned: true,
                                                  elevation: 0,
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  collapsedHeight:
                                                      staticHeaderHeight,
                                                  toolbarHeight:
                                                      staticHeaderHeight,
                                                  flexibleSpace:
                                                      ValueListenableBuilder<
                                                          double>(
                                                    valueListenable:
                                                        _sheetProgress,
                                                    builder: (context, progress,
                                                        child) {
                                                      return GestureDetector(
                                                        onTap: () {
                                                          if (progress < 0.1) {
                                                            _expandToFull();
                                                          }
                                                        },
                                                        behavior:
                                                            HitTestBehavior
                                                                .translucent,
                                                        child: AnimatedSwitcher(
                                                          duration:
                                                              const Duration(
                                                                  milliseconds:
                                                                      500),
                                                          switchInCurve: Curves
                                                              .easeInCubic,
                                                          switchOutCurve: Curves
                                                              .easeOutCubic,
                                                          child: _showDirections
                                                              ? _buildDirectionsHeader(
                                                                  staticHeaderHeight,
                                                                  isDark)
                                                              : (_selectedPlace !=
                                                                      null
                                                                  ? _buildSelectedPlaceHeader(
                                                                      staticHeaderHeight,
                                                                      progress,
                                                                      isDark)
                                                                  : _buildSearchHeader(
                                                                      staticHeaderHeight,
                                                                      progress,
                                                                      isDark)),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                                SliverToBoxAdapter(
                                                  child: ValueListenableBuilder<
                                                      double>(
                                                    valueListenable:
                                                        _sheetProgress,
                                                    builder:
                                                        (BuildContext context,
                                                            double progress,
                                                            Widget? child) {
                                                      return AnimatedOpacity(
                                                        duration:
                                                            const Duration(
                                                                milliseconds:
                                                                    150),
                                                        opacity: progress > 0.05
                                                            ? 1.0
                                                            : 0.0,
                                                        child: progress > 0.05
                                                            ? _buildSheetContent(
                                                                isDark,
                                                                progress,
                                                              )
                                                            : const SizedBox(),
                                                      );
                                                    },
                                                  ),
                                                ),
                                                SliverFillRemaining(
                                                  hasScrollBody: false,
                                                  child: Container(
                                                      color:
                                                          Colors.transparent),
                                                ),
                                              ],
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
                    ),
                  ),
                ))),
      ],
    );
  }
}
