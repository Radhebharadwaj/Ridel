// lib/features/map/screens/map_search_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';

import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/services/universal_mic_button.dart';
import 'package:ridel/features/map/models/place_model.dart';
import 'package:ridel/features/map/services/map_search_service.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/features/map/services/map_share_service.dart';
import 'package:ridel/core/widgets/notification_sheet.dart';
import 'package:ridel/features/map/widgets/map_direction_sheets.dart';

class MapSearchSheet extends StatefulWidget {
  final bool isMapTabActive;
  final Function(bool) onSearchModeChanged;
  final Function(String) onSearchSubmitted;
  final VoidCallback onBackToPreviousTab;

  const MapSearchSheet({
    super.key,
    required this.isMapTabActive,
    required this.onSearchModeChanged,
    required this.onSearchSubmitted,
    required this.onBackToPreviousTab,
  });

  @override
  State<MapSearchSheet> createState() => _MapSearchSheetState();
}

class _MapSearchSheetState extends State<MapSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  final ExpansionTileController _recentTileCtrl = ExpansionTileController();
  final ExpansionTileController _nearbyTileCtrl = ExpansionTileController();

  final MapSearchService _searchService = MapSearchService();
  List<PlaceModel> _searchResults = [];
  List<PlaceModel> _recentSearches = [];
  bool _isSearching = false;
  bool _isSearchMode = false;

  bool _showSearchList = true;
  PlaceModel? _selectedPlace;

  // 🚀 SMART API DATA HOLDERS
  bool _isLoadingDetails = false;
  WikiPlaceDetails? _wikiDetails;
  OSMPlaceDetails? _osmDetails;

  double _minSheetSize = 0.15;
  final double _midSheetSize = 0.45;
  final double _maxSheetSize = 0.90;

  final ValueNotifier<double> _sheetProgress = ValueNotifier(0.0);
  Timer? _handleTimer;
  bool _isHandleVisible = true;
  Timer? _debounceTimer;

  static const Color neonCyan = Color(0xFF00E5FF);

  // 🚀 MOCK TICKET DATA HOLDER
  // In a real app, this comes from an API. Let's mock it by place name.
  static const Map<String, Map<String, String>> _ticketBookingInfo = {
    'Lal Quila': {
      'bookingWebsite':
          'https://booking.asi.ind.in/tickets/lal-quila-booking.html',
      'ticketPhone': '1800-11-22-33 (Mock ASI Helpline)',
    },
    'Taj Mahal': {
      'bookingWebsite':
          'https://asi.paygov.in/tickets/taj-mahal-booking.html',
      'ticketPhone': '1800-11-44-55 (Mock Taj Helpline)',
    },
    // Add other places as needed...
  };

  @override
  void initState() {
    super.initState();
    _isSearchMode = widget.isMapTabActive;

    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus) {
        if (!_showSearchList) setState(() => _showSearchList = true);
        _expandToFull();
        try {
          _recentTileCtrl.expand();
        } catch (_) {}
        try {
          _nearbyTileCtrl.expand();
        } catch (_) {}
      } else {
        try {
          _recentTileCtrl.collapse();
        } catch (_) {}
        try {
          _nearbyTileCtrl.collapse();
        } catch (_) {}
      }
      setState(() {});
    });

    _searchCtrl.addListener(_onSearchChanged);
    _loadRecents();
    _wakeHandle();
  }

  Future<void> _loadRecents() async {
    final recents = await _searchService.getLocalHistory();
    final validRecents =
        recents.where((p) => p.name.trim().isNotEmpty).toList();
    if (mounted) setState(() => _recentSearches = validRecents);
  }

  Future<void> _deleteRecentSearch(PlaceModel place) async {
    AppHaptics.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('recent_searches') ?? [];
    history.removeWhere((item) => item.contains(place.name));
    await prefs.setStringList('recent_searches', history);
    _loadRecents();
  }

  Future<void> _clearAllRecents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_searches');
    _loadRecents();
  }

  void _showClearAllWarning() {
    AppHaptics.heavyImpact();
    showDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text("Clear Recent Searches?"),
        content: const Text(
            "This will permanently delete all your recent search history. Are you sure?"),
        actions: [
          CupertinoDialogAction(
              child: const Text("Cancel"), onPressed: () => Navigator.pop(context)),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text("Clear All"),
            onPressed: () {
              Navigator.pop(context);
              _clearAllRecents();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _submitSearch(
      [PlaceModel? selectedPlace, String? categoryQuery]) async {
    AppHaptics.lightImpact();
    _searchFocus.unfocus();

    if (categoryQuery != null) {
      widget.onSearchSubmitted(categoryQuery);
    } else {
      PlaceModel? placeToSubmit = selectedPlace ??
          (_searchResults.isNotEmpty ? _searchResults.first : null);
      if (placeToSubmit != null) {
        setState(() {
          _selectedPlace = placeToSubmit;
          _showSearchList = false;
          _isLoadingDetails = true;
        });

        await _searchService.onPlaceSelected(placeToSubmit);
        await _loadRecents();

        widget.onSearchSubmitted(
            "${placeToSubmit.latitude},${placeToSubmit.longitude}");

        try {
          final results = await Future.wait([
            WikipediaService.getPlaceDetails(placeToSubmit.name),
            OSMDetailsService.getDetails(
                placeToSubmit.latitude, placeToSubmit.longitude),
          ]);

          if (mounted) {
            setState(() {
              _wikiDetails = results[0] as WikiPlaceDetails?;
              _osmDetails = results[1] as OSMPlaceDetails?;
              _isLoadingDetails = false;
            });
          }
        } catch (e) {
          if (mounted) setState(() => _isLoadingDetails = false);
        }
      } else if (_searchCtrl.text.isNotEmpty) {
        if (_searchResults.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Text(
                    "Place not found. Try a different name.",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  )),
                ],
              ),
              backgroundColor: Colors.redAccent.shade400,
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(
                  bottom: MediaQuery.of(context).size.height - 150,
                  left: 20,
                  right: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              duration: const Duration(seconds: 3),
            ),
          );
          _searchCtrl.clear();
        } else {
          widget.onSearchSubmitted(_searchCtrl.text);
        }
      }
    }

    if (_sheetController.isAttached) {
      _sheetController.animateTo(_midSheetSize,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
    }

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _searchCtrl.clear();
        _loadRecents();
      }
    });
  }

  void _clearSelectedPlace() {
    AppHaptics.lightImpact();
    _searchFocus.unfocus();
    setState(() {
      _selectedPlace = null;
      _wikiDetails = null;
      _osmDetails = null;
      _searchCtrl.clear();
      _showSearchList = true;
    });

    widget.onSearchSubmitted("CLEAR_PIN_COMMAND");

    if (_sheetController.isAttached &&
        _sheetController.size > _midSheetSize) {
      _sheetController.animateTo(_midSheetSize,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
    }
  }

  void _onSearchChanged() {
    if (_searchCtrl.text.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchList = true;
      });
      return;
    }
    if (!_showSearchList) setState(() => _showSearchList = true);

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearching = true);
      final results = await _searchService.getSuggestions(_searchCtrl.text);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  void _wakeHandle() {
    if (!_isHandleVisible && mounted) setState(() => _isHandleVisible = true);
    _handleTimer?.cancel();
    _handleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isHandleVisible = false);
    });
  }

  void _initiatePhoneCall() {
    if (_osmDetails?.phone == null) return;

    AppHaptics.mediumImpact();
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text("Call ${_selectedPlace?.name ?? 'this place'}?"),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(_osmDetails!.phone!,
              style: const TextStyle(fontSize: 16, letterSpacing: 1.2)),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text("Call",
                style: TextStyle(color: CupertinoColors.activeGreen)),
            onPressed: () async {
              Navigator.pop(context);
              final Uri url = Uri.parse("tel:${_osmDetails!.phone!}");
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              }
            },
          ),
        ],
      ),
    );
  }

  void _openWebsite() async {
    if (_osmDetails?.website == null) return;
    final Uri url = Uri.parse(_osmDetails!.website!);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void didUpdateWidget(MapSearchSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isMapTabActive &&
        !oldWidget.isMapTabActive &&
        !_isSearchMode) {
      _openSearchMode();
    } else if (!widget.isMapTabActive &&
        oldWidget.isMapTabActive &&
        _isSearchMode) {
      _closeSearchMode();
    }
  }

  void _openSearchMode() {
    AppHaptics.mediumImpact();
    _wakeHandle();
    setState(() => _isSearchMode = true);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onSearchModeChanged(true));
    _sheetProgress.value = 0.0;
    if (_sheetController.isAttached) _sheetController.jumpTo(_minSheetSize);
  }

  void _closeSearchMode() {
    AppHaptics.lightImpact();
    _searchFocus.unfocus();
    setState(() => _isSearchMode = false);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onSearchModeChanged(false));
  }

  void _handleManualDragUpdate(DragUpdateDetails details) {
    if (!_sheetController.isAttached) return;
    double screenHeight = MediaQuery.sizeOf(context).height;
    double delta = -details.primaryDelta! / screenHeight;
    double newSize =
        (_sheetController.size + delta).clamp(_minSheetSize, _maxSheetSize);
    _sheetController.jumpTo(newSize);
  }

  void _handleManualDragEnd(DragEndDetails details) {
    if (!_sheetController.isAttached) return;
    double velocity = details.primaryVelocity ?? 0;
    double size = _sheetController.size;
    const duration = Duration(milliseconds: 300);

    if (velocity < -300) {
      if (size < _midSheetSize) {
        _sheetController.animateTo(_midSheetSize,
            duration: duration, curve: Curves.easeOutCubic);
      } else {
        _sheetController.animateTo(_maxSheetSize,
            duration: duration, curve: Curves.easeOutCubic);
      }
    } else if (velocity > 300) {
      if (size > _midSheetSize) {
        _sheetController.animateTo(_midSheetSize,
            duration: duration, curve: Curves.easeOutCubic);
      } else {
        _sheetController.animateTo(_minSheetSize,
            duration: duration, curve: Curves.easeOutCubic);
      }
    } else {
      double dMin = (size - _minSheetSize).abs();
      double dMid = (size - _midSheetSize).abs();
      double dMax = (size - _maxSheetSize).abs();

      if (dMin < dMin && dMin < dMax) {
        _sheetController.animateTo(_minSheetSize,
            duration: duration, curve: Curves.easeOutCubic);
      } else if (dMid < dMin && dMid < dMax) {
        _sheetController.animateTo(_midSheetSize,
            duration: duration, curve: Curves.easeOutCubic);
      } else {
        _sheetController.animateTo(_maxSheetSize,
            duration: duration, curve: Curves.easeOutCubic);
      }
    }
  }

  void _toggleSheetSize() {
    if (!_sheetController.isAttached) return;
    AppHaptics.lightImpact();
    double currentSize = _sheetController.size;
    if (currentSize < 0.40) {
      _sheetController.animateTo(_midSheetSize,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
    } else if (currentSize < 0.85) {
      _expandToFull();
    } else {
      _sheetController.animateTo(_midSheetSize,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
    }
  }

  void _expandToFull() {
    if (!_sheetController.isAttached) return;
    if (_sheetController.size < 0.85) {
      _sheetController.animateTo(_maxSheetSize,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic);
    }
  }

  void _handleCancelTap() {
    AppHaptics.lightImpact();
    bool hasFocusOrText =
        _searchFocus.hasFocus || _searchCtrl.text.isNotEmpty;
    bool isExpanded = _sheetController.isAttached &&
        _sheetController.size > (_minSheetSize + 0.05);

    if (hasFocusOrText) {
      _searchFocus.unfocus();
      _searchCtrl.clear();
      widget.onSearchSubmitted("");
      if (_sheetController.isAttached) {
        _sheetController.animateTo(_midSheetSize,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic);
      }
    } else if (isExpanded) {
      if (_sheetController.isAttached) {
        _sheetController.animateTo(_minSheetSize,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic);
      }
    } else {
      _closeSearchMode();
      widget.onBackToPreviousTab();
    }
  }

  // 🚀 New helper function to get booking info safe
  Map<String, String>? _getBookingInfoForCurrentPlace() {
    if (_selectedPlace == null) return null;
    return _ticketBookingInfo[_selectedPlace!.name];
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _handleTimer?.cancel();
    _sheetController.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _sheetProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color solidRidelBgColor = isDark
        ? const Color(0xFF1C1C1E).withOpacity(0.98)
        : Colors.white.withOpacity(0.98);
    final Color glassBaseColor = isDark
        ? const Color(0xFF1C1C1E).withOpacity(0.70)
        : Colors.white.withOpacity(0.70);

    const double glassCapsuleHeight = 64.0;
    const double externalHandleTouchGap = 26.0;
    final double totalHeaderHeight = glassCapsuleHeight + externalHandleTouchGap;

    final double initialBottomMargin = 16.0 + bottomPadding;
    _minSheetSize = (totalHeaderHeight + initialBottomMargin) / screenSize.height;
    if (_minSheetSize > 1.0) _minSheetSize = 1.0;

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        _wakeHandle();
        final progress = ((notification.extent - notification.minExtent) /
                (notification.maxExtent - notification.minExtent))
            .clamp(0.0, 1.0);

        if (_sheetProgress.value != progress) {
          _sheetProgress.value = progress;
        }

        if (progress < 0.65) {
          try {
            if (_recentTileCtrl.isExpanded && !_searchFocus.hasFocus)
              _recentTileCtrl.collapse();
            if (_nearbyTileCtrl.isExpanded && !_searchFocus.hasFocus)
              _nearbyTileCtrl.collapse();
          } catch (_) {}

          if (_showSearchList &&
              _searchCtrl.text.isNotEmpty &&
              _selectedPlace == null) {
            setState(() => _showSearchList = false);
            _searchFocus.unfocus();
          }
        }
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: _minSheetSize,
        minChildSize: _minSheetSize,
        maxChildSize: _maxSheetSize,
        snap: true,
        snapAnimationDuration: const Duration(milliseconds: 300),
        snapSizes: [_minSheetSize, _midSheetSize, _maxSheetSize],
        builder: (context, scrollController) {
          return ValueListenableBuilder<double>(
            valueListenable: _sheetProgress,
            builder: (context, progress, child) {
              final double currentSideMargin = 16.0 * (1.0 - progress);
              final double currentBottomMargin =
                  (initialBottomMargin) * (1.0 - progress);
              final double currentRadius = 35.0;
              final double dynamicHeaderHeight =
                  glassCapsuleHeight + (20.0 * progress);

              final Color currentBgColor = Color.lerp(
                      glassBaseColor, solidRidelBgColor, progress) ??
                  glassBaseColor;
              final double currentBlur =
                  lerpDouble(25.0, 0.001, progress) ?? 25.0;

              return PointerInterceptor(
                child: GestureDetector(
                  onVerticalDragUpdate: _handleManualDragUpdate,
                  onVerticalDragEnd: _handleManualDragEnd,
                  behavior: HitTestBehavior.translucent,
                  child: Container(
                    margin: EdgeInsets.only(
                        left: currentSideMargin,
                        right: currentSideMargin,
                        bottom: currentBottomMargin),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: -15,
                          left: 0,
                          right: 0,
                          height: externalHandleTouchGap + 15,
                          child: GestureDetector(
                            onTap: _toggleSheetSize,
                            onVerticalDragUpdate: _handleManualDragUpdate,
                            onVerticalDragEnd: _handleManualDragEnd,
                            behavior: HitTestBehavior.translucent,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 300),
                              opacity: _isHandleVisible ? 1.0 : 0.0,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 6.0),
                                  child: Container(
                                    width: 38,
                                    height: 4.5,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.45),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          top: externalHandleTouchGap,
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(currentRadius),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(
                                      isDark ? 0.6 : 0.15 * progress),
                                  blurRadius: 20.0,
                                  offset: Offset(0, -2 * progress),
                                )
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(currentRadius),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                    sigmaX: currentBlur, sigmaY: currentBlur),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: currentBgColor,
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.1),
                                        width: 1.0),
                                    borderRadius:
                                        BorderRadius.circular(currentRadius),
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: ScrollConfiguration(
                                          behavior:
                                              ScrollConfiguration.of(context)
                                                  .copyWith(
                                            scrollbars: false,
                                            dragDevices: {
                                              PointerDeviceKind.touch,
                                              PointerDeviceKind.mouse,
                                              PointerDeviceKind.trackpad
                                            },
                                          ),
                                          child: CustomScrollView(
                                            controller: scrollController,
                                            keyboardDismissBehavior:
                                                ScrollViewKeyboardDismissBehavior
                                                    .onDrag,
                                            // 🚀 FIX: Native Bouncing physics lagayi hai. Kyunki choti sheet me hidden items height 0 hogi, toh ye bilkul SCROLL NAHI HOGA!
                                            physics:
                                                const BouncingScrollPhysics(),
                                            slivers: [
                                              SliverToBoxAdapter(
                                                  child: SizedBox(
                                                      height:
                                                          dynamicHeaderHeight +
                                                              20)),
                                              SliverToBoxAdapter(
                                                child: AnimatedOpacity(
                                                  duration: const Duration(
                                                      milliseconds: 150),
                                                  opacity:
                                                      progress > 0.05 ? 1.0 : 0.0,
                                                  child: progress > 0.05
                                                      ? _buildSheetContent(
                                                          isDark, progress)
                                                      : const SizedBox(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        right: 0,
                                        child: IgnorePointer(
                                          child: AnimatedOpacity(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            opacity:
                                                progress > 0.8 ? 1.0 : 0.0,
                                            child: Container(
                                              height: dynamicHeaderHeight + 35,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    solidRidelBgColor,
                                                    solidRidelBgColor
                                                        .withOpacity(0.95),
                                                    solidRidelBgColor
                                                        .withOpacity(0.0)
                                                  ],
                                                  stops: const [
                                                    0.0,
                                                    0.65,
                                                    1.0
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        right: 0,
                                        height: dynamicHeaderHeight,
                                        child: GestureDetector(
                                          onTap: () {
                                            if (progress < 0.1) _expandToFull();
                                          },
                                          onVerticalDragUpdate:
                                              _handleManualDragUpdate,
                                          onVerticalDragEnd:
                                              _handleManualDragEnd,
                                          behavior: HitTestBehavior.translucent,
                                          child: _selectedPlace != null
                                              ? _buildSelectedPlaceHeader(
                                                  dynamicHeaderHeight,
                                                  progress,
                                                  isDark)
                                              : _buildSearchHeader(
                                                  dynamicHeaderHeight,
                                                  progress,
                                                  isDark),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
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
    );
  }

  Widget _buildSearchHeader(
      double headerHeight, double progress, bool isDark) {
    final Color searchBarColor = isDark
        ? const Color(0xFF767680).withOpacity(0.24)
        : const Color(0xFF767680).withOpacity(0.12);
    return SizedBox(
      height: headerHeight,
      child: Padding(
        padding: EdgeInsets.only(
            left: 10 + (12 * progress),
            top: 10 + (20 * progress),
            bottom: 10,
            right: 16 + (12 * progress)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                height: 44.0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  color: searchBarColor,
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.05),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.search,
                        color: isDark ? Colors.white54 : Colors.black54,
                        size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        textAlignVertical: TextAlignVertical.center,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w400),
                        decoration: InputDecoration(
                          hintText: "Search Ridel Maps",
                          hintStyle: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black54,
                              fontSize: 16),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) => _submitSearch(),
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: _searchCtrl,
                      builder: (context, TextEditingValue value, child) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (value.text.isNotEmpty)
                              GestureDetector(
                                onTap: () => _searchCtrl.clear(),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white30
                                        : Colors.black26,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.close,
                                    size: 12,
                                    color: isDark
                                        ? Colors.black87
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            if (value.text.isEmpty)
                              UniversalMicButton(
                                isDark: isDark,
                                onTextRecognized: (text) =>
                                    _searchCtrl.text = text,
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            ValueListenableBuilder(
              valueListenable: _searchCtrl,
              builder: (context, TextEditingValue value, child) {
                bool isTyping = value.text.isNotEmpty;
                return GestureDetector(
                  onTap: () {
                    if (isTyping) {
                      _submitSearch();
                    } else {
                      _handleCancelTap();
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Text(
                      isTyping ? "Done" : "Cancel",
                      style: TextStyle(
                        color: isDark ? neonCyan : const Color(0xFF00B8D4),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
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

  Widget _buildSelectedPlaceHeader(
      double headerHeight, double progress, bool isDark) {
    final Color textColor = isDark ? Colors.white : Colors.black;
    final Color subTextColor = isDark ? Colors.white54 : Colors.black54;
    final Color btnBgColor = isDark
        ? Colors.white.withOpacity(0.12)
        : Colors.black.withOpacity(0.08);
    final Color btnIconColor = isDark ? Colors.white : Colors.black;

    return SizedBox(
      height: headerHeight,
      child: Center(
        child: Padding(
          padding: EdgeInsets.only(
            left: 12 + (8 * progress),
            right: 12 + (8 * progress),
            top: 15 * progress,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () async {
                  AppHaptics.lightImpact();
                  String shareLink =
                      "https://maps.apple/p/~${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}";
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("Link copied: $shareLink")));
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: btnBgColor, shape: BoxShape.circle),
                  child: Icon(CupertinoIcons.share,
                      size: 20, color: btnIconColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ShaderMask(
                  shaderCallback: (Rect bounds) => const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.transparent,
                      Colors.black,
                      Colors.black,
                      Colors.transparent
                    ],
                    stops: [0.0, 0.02, 0.98, 1.0],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedPlace!.name,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                            color: textColor,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            height: 1.2),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Place • ${_selectedPlace!.address}",
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                            color: subTextColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.2),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _clearSelectedPlace,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: btnBgColor, shape: BoxShape.circle),
                  child: Icon(Icons.close, size: 20, color: btnIconColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetContent(bool isDark, double progress) {
    if (_selectedPlace != null) return _buildDetailedPlaceView(isDark);
    if (_searchCtrl.text.isNotEmpty && _showSearchList)
      return _buildSearchResultsView(isDark);
    return _buildUnifiedExploreView(isDark, progress);
  }

  // 🚀 MODIFIED: Tickets & Booking section added
  Widget _buildDetailedPlaceView(bool isDark) {
    final Color textColor = isDark ? Colors.white : Colors.black;
    final Color subTextColor = isDark ? Colors.white54 : Colors.black54;
    final Color dividerColor =
        isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05);

    bool hasPhone = _osmDetails?.phone != null && _osmDetails!.phone!.isNotEmpty;

    // 🚀 Load ticket booking info safe
    Map<String, String>? ticketInfo = _getBookingInfoForCurrentPlace();
    bool hasTicketInfo = ticketInfo != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    AppHaptics.mediumImpact();
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (context) => MapDirectionsSheet(
                        destination: _selectedPlace!,
                        onCancel: () => Navigator.pop(context),
                      ),
                    );
                  },
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                        color: neonCyan, borderRadius: BorderRadius.circular(100)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.car_detailed,
                            color: isDark ? Colors.black : Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          "Go",
                          style: TextStyle(
                              color: isDark ? Colors.black : Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: hasPhone ? _initiatePhoneCall : null,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: hasPhone
                          ? (isDark ? Colors.white12 : Colors.black12)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.phone,
                            color: hasPhone ? neonCyan : Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          "Call",
                          style: TextStyle(
                              color: hasPhone ? neonCyan : Colors.grey,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  Text("Hours",
                      style: TextStyle(color: subTextColor, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    _osmDetails?.openingHours ?? "Not available",
                    style: TextStyle(
                        color: _osmDetails?.openingHours != null
                            ? neonCyan
                            : Colors.grey,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Column(
                children: [
                  Text("Distance",
                      style: TextStyle(color: subTextColor, fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.directions, size: 16, color: textColor),
                      const SizedBox(width: 4),
                      Text("Location",
                          style: TextStyle(
                              color: textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ],
                  )
                ],
              )
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 160,
            child: _isLoadingDetails
                ? const Center(child: CupertinoActivityIndicator(color: neonCyan))
                : ListView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    children: [
                      if (_wikiDetails?.imageUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 220,
                            decoration:
                                BoxDecoration(color: Colors.grey.withOpacity(0.2)),
                            child: Image.network(
                              _wikiDetails!.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Icon(Icons.broken_image,
                                    color: Colors.grey.withOpacity(0.5)),
                              ),
                            ),
                          ),
                        )
                      else
                        _buildImagePlaceholder(),
                    ],
                  ),
          ),
          const SizedBox(height: 32),
          Text("About",
              style: TextStyle(
                  color: textColor, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_isLoadingDetails)
            Text("Loading details...", style: TextStyle(color: subTextColor))
          else if (_wikiDetails != null) ...[
            Text(
              _wikiDetails!.extract,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: textColor.withOpacity(0.9), fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final Uri url = Uri.parse(_wikiDetails!.articleUrl);
                if (await canLaunchUrl(url)) await launchUrl(url);
              },
              child: const Text("More on Wikipedia",
                  style: TextStyle(
                      color: neonCyan, fontSize: 14, fontWeight: FontWeight.w500)),
            )
          ] else
            Text("Detailed information not available for this location.",
                style: TextStyle(color: subTextColor)),

          // 🚀 Tickets & Booking Section - New feature added here!
          if (hasTicketInfo) ...[
            const SizedBox(height: 24),
            Divider(color: dividerColor),
            const SizedBox(height: 16),
            Text("Tickets & Booking",
                style: TextStyle(
                    color: textColor, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Material(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                    border: Border.all(color: dividerColor, width: 1)),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final Uri url = Uri.parse(ticketInfo['bookingWebsite']!);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      child: _buildDetailRow("Booking Website", "Book Now", isDark,
                          valueColor: neonCyan),
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow("Ticket Support", ticketInfo['ticketPhone']!,
                        isDark, valueColor: neonCyan),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          Divider(color: dividerColor),
          const SizedBox(height: 16),
          Text("Details",
              style: TextStyle(
                  color: textColor, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildDetailRow("Phone", _osmDetails?.phone ?? "Not available", isDark,
              valueColor: hasPhone ? neonCyan : Colors.grey),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _openWebsite,
            child: _buildDetailRow(
                "Website",
                _osmDetails?.website != null ? "Open Website" : "Not available",
                isDark,
                valueColor: _osmDetails?.website != null ? neonCyan : Colors.grey),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Address", style: TextStyle(color: subTextColor, fontSize: 15)),
              Expanded(
                child: Text(
                  _selectedPlace!.address.replaceAll(", ", "\n"),
                  textAlign: TextAlign.right,
                  style: TextStyle(color: textColor, fontSize: 15, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => AppHaptics.lightImpact(),
            child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                    color: neonCyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(100)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_bubble_fill,
                        color: neonCyan, size: 20),
                    const SizedBox(width: 8),
                    const Text("Report an Issue",
                        style: TextStyle(
                            color: neonCyan,
                            fontSize: 16,
                            fontWeight: FontWeight.w600))
                  ],
                )),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => AppHaptics.lightImpact(),
            child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                    color: neonCyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(100)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.pin_fill,
                        color: neonCyan, size: 20),
                    const SizedBox(width: 8),
                    const Text("Pin",
                        style: TextStyle(
                            color: neonCyan,
                            fontSize: 16,
                            fontWeight: FontWeight.w600))
                  ],
                )),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 160,
        decoration: BoxDecoration(color: Colors.grey.withOpacity(0.2)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Icon(Icons.image,
                  size: 40, color: Colors.grey.withOpacity(0.5)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark,
      {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54, fontSize: 15)),
        Text(value,
            style: TextStyle(
                color: valueColor ?? (isDark ? Colors.white : Colors.black),
                fontSize: 15,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildProfileStyleCard(BuildContext context,
      {required bool isDark, required Color bgColor, required Widget child}) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.05),
              width: 1),
        ),
        child: child,
      ),
    );
  }

  // 🚀 THE MAGIC: Flawless UI. No scrolling when small. Strict 2 capsules visible.
  Widget _buildUnifiedExploreView(bool isDark, double progress) {
    final Color textColor = isDark ? Colors.white : Colors.black;
    final Color iconColor = isDark ? Colors.white70 : Colors.black87;
    final Color glassyCardBg =
        isDark ? Colors.white.withOpacity(0.08) : Colors.white;
    final Color neonCardBg = neonCyan.withOpacity(0.10);

    bool isFocused = _searchFocus.hasFocus;

    // Yahan hum strictly check kar rahe hain ki sheet expand hona start hui hai ya nahi
    bool isExpanded = progress > (_minSheetSize + 0.05);

    // Ye custom wrapper item ka height bilkul '0' kar deta hai jab sheet chhoti ho. (Zero Scroll Bug Fix)
    Widget buildHiddenExtra(Widget child) {
      return AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: isExpanded
            ? AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: 1.0,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: child,
                ),
              )
            : const SizedBox(width: double.infinity, height: 0),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),

          // 🚀 1. HOME/WORK ROW (Always visible initially, hides on typing)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isFocused ? 0.0 : 1.0,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: isFocused
                  ? const SizedBox(width: double.infinity, height: 0)
                  : Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildNeonGlassyActionBtn(
                                CupertinoIcons.house_fill, "Home", "Add", isDark),
                            _buildNeonGlassyActionBtn(
                                CupertinoIcons.briefcase_fill, "Work", "Add", isDark),
                            _buildNeonGlassyActionBtn(
                                CupertinoIcons.add, "Add", "Place", isDark),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
            ),
          ),

          // 🚀 2. RECENT SEARCHES (Strictly HIDDEN when sheet is small, Pops up when expanded)
          buildHiddenExtra(
            _buildProfileStyleCard(
              context,
              isDark: isDark,
              bgColor: glassyCardBg,
              child: Theme(
                data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                    unselectedWidgetColor: iconColor),
                child: ExpansionTile(
                  controller: _recentTileCtrl,
                  initiallyExpanded: false,
                  collapsedShape: const Border(),
                  shape: const Border(),
                  onExpansionChanged: (expanded) {
                    if (expanded) _expandToFull();
                  },
                  leading: Icon(CupertinoIcons.clock, color: iconColor),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Recent Searches",
                          style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 16)),
                      if (_recentSearches.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _showClearAllWarning();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(100)),
                            child: const Text("Delete All",
                                style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                    ],
                  ),
                  iconColor: iconColor,
                  collapsedIconColor: iconColor,
                  children: [
                    if (_recentSearches.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 30.0, bottom: 30.0),
                        child: Column(
                          children: [
                            const _PulsingExploreIcon(),
                            const SizedBox(height: 16),
                            Text(
                              "Your search history is empty.",
                              style: TextStyle(
                                  color: isDark ? Colors.white54 : Colors.black54,
                                  fontSize: 14),
                            )
                          ],
                        ),
                      ),
                    if (_recentSearches.isNotEmpty)
                      ..._recentSearches.asMap().entries.map((entry) {
                        int index = entry.key;
                        PlaceModel place = entry.value;
                        bool isLast = index == _recentSearches.length - 1;
                        return Dismissible(
                          key: Key("recent_${index}_${place.name}"),
                          direction: DismissDirection.endToStart,
                          background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Colors.redAccent,
                              child: const Icon(CupertinoIcons.delete,
                                  color: Colors.white)),
                          onDismissed: (_) => _deleteRecentSearch(place),
                          child: Column(
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 2, horizontal: 16),
                                leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white12
                                            : Colors.black12,
                                        shape: BoxShape.circle),
                                    child: const Icon(CupertinoIcons.clock,
                                        color: Colors.grey, size: 18)),
                                title: Text(
                                  place.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16),
                                ),
                                subtitle: Text(
                                  place.address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.black54,
                                      fontSize: 13),
                                ),
                                onTap: () => _submitSearch(place),
                              ),
                              if (!isLast)
                                Divider(
                                    height: 1,
                                    color: isDark
                                        ? Colors.white.withOpacity(0.08)
                                        : Colors.black12,
                                    indent: 60)
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),

          // 🚀 3. FIND NEARBY (ALWAYS VISIBLE - Main Menu Item 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildProfileStyleCard(
              context,
              isDark: isDark,
              bgColor: glassyCardBg,
              child: Theme(
                data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                    unselectedWidgetColor: iconColor),
                child: ExpansionTile(
                  controller: _nearbyTileCtrl,
                  initiallyExpanded: false,
                  collapsedShape: const Border(),
                  shape: const Border(),
                  onExpansionChanged: (expanded) {
                    if (expanded) _expandToFull();
                  },
                  leading: Icon(Icons.travel_explore_rounded, color: iconColor),
                  title: Text("Find Nearby",
                      style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 16)),
                  iconColor: iconColor,
                  collapsedIconColor: iconColor,
                  children: [
                    _buildNearbyTile(
                        Icons.local_gas_station_rounded,
                        const [Color(0xFF4CABFF), Color(0xFF0A84FF)],
                        "Petrol Pumps",
                        isDark,
                        false),
                    _buildNearbyTile(
                        Icons.restaurant_rounded,
                        const [Color(0xFFFFB340), Color(0xFFFF9500)],
                        "Restaurants",
                        isDark,
                        false),
                    _buildNearbyTile(
                        Icons.hotel_rounded,
                        const [Color(0xFFC67AEE), Color(0xFFAF52DE)],
                        "Hotels",
                        isDark,
                        false),
                    _buildNearbyTile(
                        Icons.directions_subway_filled_rounded,
                        const [Color(0xFF5AC8FA), Color(0xFF007AFF)],
                        "Metro Station",
                        isDark,
                        false),
                    _buildNearbyTile(
                        Icons.ev_station_rounded,
                        const [Color(0xFF65D57B), Color(0xFF34C759)],
                        "EV & CNG Stations",
                        isDark,
                        false),
                    _buildNearbyTile(
                        Icons.train_rounded,
                        const [Color(0xFF4CABFF), Color(0xFF0A84FF)],
                        "Railway Stations",
                        isDark,
                        false),
                    _buildNearbyTile(
                        Icons.local_parking_rounded,
                        const [Color(0xFF64D2FF), Color(0xFF32ADE6)],
                        "Parking",
                        isDark,
                        true),
                  ],
                ),
              ),
            ),
          ),

          // 🚀 4. BOTTOM BUTTONS MANAGER
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isFocused ? 0.0 : 1.0,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: isFocused
                  ? const SizedBox(width: double.infinity, height: 0)
                  : Column(
                      children: [
                        // 4A. SHARE MY LOCATION (ALWAYS VISIBLE - Main Menu Item 2)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildProfileStyleCard(
                            context,
                            isDark: isDark,
                            bgColor: neonCardBg,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 2, horizontal: 16),
                              leading: const Icon(CupertinoIcons.share,
                                  color: neonCyan, size: 22),
                              title: const Text(
                                "Share My Location",
                                style: TextStyle(
                                    color: neonCyan,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                              ),
                              trailing: Icon(Icons.chevron_right_rounded,
                                  color: neonCyan.withOpacity(0.6)),
                              onTap: () async {
                                AppHaptics.lightImpact();
                                await MapShareService.shareCurrentLocation(
                                    context);
                              },
                            ),
                          ),
                        ),

                        // 4B. MARK MY LOCATION (Strictly HIDDEN when sheet is small)
                        buildHiddenExtra(
                          _buildProfileStyleCard(
                            context,
                            isDark: isDark,
                            bgColor: neonCardBg,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 2, horizontal: 16),
                              leading: const Icon(CupertinoIcons.pin,
                                  color: neonCyan, size: 22),
                              title: const Text(
                                "Mark My Location",
                                style: TextStyle(
                                    color: neonCyan,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                              ),
                              trailing: Icon(Icons.chevron_right_rounded,
                                  color: neonCyan.withOpacity(0.6)),
                              onTap: () {
                                AppHaptics.lightImpact();
                                Provider.of<MapProvider>(context, listen: false)
                                    .markCurrentPosition(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            "Location marked on map!")));
                              },
                            ),
                          ),
                        ),

                        // 4C. REPORT AN ISSUE (Strictly HIDDEN when sheet is small)
                        buildHiddenExtra(
                          Column(
                            children: [
                              const SizedBox(height: 4),
                              Center(
                                child: InkWell(
                                  onTap: () => AppHaptics.lightImpact(),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      "Report an Issue",
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black54,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNeonGlassyActionBtn(
      IconData icon, String title, String subtitle, bool isDark) {
    return GestureDetector(
      onTap: () => AppHaptics.lightImpact(),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
                color: neonCyan.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(
                    color: neonCyan.withOpacity(0.25), width: 1)),
            child: Icon(icon, color: neonCyan, size: 28),
          ),
          const SizedBox(height: 8),
          Text(title,
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          Text(subtitle,
              style: TextStyle(
                  color: neonCyan.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildNearbyTile(IconData icon, List<Color> gradientColors,
      String title, bool isDark, bool isLast) {
    return Column(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: gradientColors.last.withOpacity(0.5),
                    blurRadius: 6,
                    offset: const Offset(0, 3)),
                BoxShadow(
                    color: Colors.white.withOpacity(0.2),
                    blurRadius: 1,
                    offset: const Offset(0, 0),
                    spreadRadius: 1)
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          title: Text(title,
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          onTap: () => _submitSearch(null, title),
        ),
        if (!isLast)
          Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black12,
              indent: 56)
      ],
    );
  }

  Widget _buildSearchResultsView(bool isDark) {
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: CupertinoActivityIndicator(color: neonCyan)),
      );
    }
    if (_searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Text("No places found",
              style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _buildProfileStyleCard(
        context,
        isDark: isDark,
        bgColor: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
        child: Column(
          children: _searchResults.asMap().entries.map((entry) {
            int index = entry.key;
            PlaceModel place = entry.value;
            bool isLast = index == _searchResults.length - 1;
            return Column(
              children: [
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                  leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: isDark ? Colors.white12 : Colors.black12,
                          shape: BoxShape.circle),
                      child: const Icon(CupertinoIcons.location_solid,
                          color: Colors.grey, size: 18)),
                  title: Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 16),
                  ),
                  subtitle: Text(
                    place.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 13),
                  ),
                  onTap: () => _submitSearch(place),
                ),
                if (!isLast)
                  Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.black12,
                      indent: 60)
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// =========================================================================
// 🚀 SMART API SERVICES (Wikipedia + OSM Overpass)
// =========================================================================

class WikiPlaceDetails {
  final String title;
  final String extract;
  final String? imageUrl;
  final String articleUrl;
  WikiPlaceDetails(
      {required this.title,
      required this.extract,
      this.imageUrl,
      required this.articleUrl});
}

class WikipediaService {
  static Future<WikiPlaceDetails?> getPlaceDetails(String placeName) async {
    try {
      String query = placeName.split(',').first.trim().replaceAll(' ', '_');
      final url = Uri.parse(
          'https://en.wikipedia.org/api/rest_v1/page/summary/$query');
      final response = await http.get(url,
          headers: {'Accept': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['type'] == 'disambiguation') return null;

        return WikiPlaceDetails(
          title: data['title'] ?? placeName,
          extract: data['extract'] ?? 'No detailed description available.',
          imageUrl: data['originalimage']?['source'] ??
              data['thumbnail']?['source'],
          articleUrl: data['content_urls']?['desktop']?['page'] ??
              'https://wikipedia.org',
        );
      }
      return null;
    } catch (e) {
      debugPrint("Wiki API Error: $e");
      return null;
    }
  }
}

class OSMPlaceDetails {
  final String? phone;
  final String? openingHours;
  final String? website;
  OSMPlaceDetails({this.phone, this.openingHours, this.website});
}

class OSMDetailsService {
  static Future<OSMPlaceDetails?> getDetails(double lat, double lon) async {
    try {
      final query = '''
      [out:json][timeout:5];
      (
        nwr(around:30, $lat, $lon)[name];
      );
      out tags limit 1;
      ''';

      final url = Uri.parse(
          'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['elements'] != null && data['elements'].isNotEmpty) {
          final tags = data['elements'][0]['tags'];
          return OSMPlaceDetails(
            phone: tags['phone'] ?? tags['contact:phone'],
            openingHours: tags['opening_hours'],
            website: tags['website'] ?? tags['contact:website'],
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint("OSM API Error: $e");
      return null;
    }
  }
}

class _PulsingExploreIcon extends StatefulWidget {
  const _PulsingExploreIcon();
  @override
  State<_PulsingExploreIcon> createState() => _PulsingExploreIconState();
}

class _PulsingExploreIconState extends State<_PulsingExploreIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500))
      ..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.97, end: 1.03).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(scale: _animation.value, child: child);
      },
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            color: const Color(0xFF00E5FF).withOpacity(0.08),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF00E5FF).withOpacity(0.15),
                  blurRadius: 40,
                  spreadRadius: 5)
            ]),
        child: ShaderMask(
          shaderCallback: (Rect bounds) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFF00E5FF)],
          ).createShader(bounds),
          child: const Icon(Icons.rocket_launch_rounded,
              size: 54, color: Colors.white),
        ),
      ),
    );
  }
}