import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/services/global_location_service.dart';

import 'package:ridel/features/map/map_engine/map_engine.dart';
import 'package:ridel/features/map/models/place_model.dart';
import 'package:ridel/core/services/saved_places_service.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';

class QuickActionButtons extends StatefulWidget {
  final bool isDark;
  final Function(String actionType) onRequestSearch;
  final Function(PlaceModel destination) onNavigateReady;
  final VoidCallback? onDropPinTapped;

  const QuickActionButtons({
    super.key,
    required this.isDark,
    required this.onRequestSearch,
    required this.onNavigateReady,
    this.onDropPinTapped,
  });

  @override
  State<QuickActionButtons> createState() => QuickActionButtonsState();
}

class QuickActionButtonsState extends State<QuickActionButtons> {
  PlaceModel? _homePlace;
  PlaceModel? _workPlace;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    refreshData();
  }

  // 🚀 Call this method to forcefully reload buttons when a place is saved!
  Future<void> refreshData() async {
    if (!context.mounted) return;
    setState(() => _isLoading = true);

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      final home = await SavedPlacesService.getHome();
      final work = await SavedPlacesService.getWork();
      if (mounted) {
        setState(() {
          _homePlace = home;
          _workPlace = work;
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('home_place, work_place')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted && response != null) {
        setState(() {
          if (response['home_place'] != null) {
            final h = response['home_place'];
            _homePlace = PlaceModel(
                placeId: h['place_id'] ?? 'home_${user.id}',
                name: h['name'],
                address: h['address'],
                latitude: h['latitude'],
                longitude: h['longitude'],
                categories: ['Home']);
          } else {
            _homePlace = null;
          }

          if (response['work_place'] != null) {
            final w = response['work_place'];
            _workPlace = PlaceModel(
                placeId: w['place_id'] ?? 'work_${user.id}',
                name: w['name'],
                address: w['address'],
                latitude: w['latitude'],
                longitude: w['longitude'],
                categories: ['Work']);
          } else {
            _workPlace = null;
          }
        });
      }
    } catch (e) {
      debugPrint("Failed to load places: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleHomeTap() {
    AppHaptics.mediumImpact();
    if (_homePlace == null) {
      widget.onRequestSearch('HOME');
    } else {
      widget.onNavigateReady(_homePlace!);
    }
  }

  void _handleWorkTap() {
    AppHaptics.mediumImpact();
    if (_workPlace == null) {
      widget.onRequestSearch('WORK');
    } else {
      widget.onNavigateReady(_workPlace!);
    }
  }

  void _handleAddPlaceTap() {
    AppHaptics.lightImpact();
    widget.onRequestSearch('CUSTOM');
  }

  void _handleLongPress(String type) {
    AppHaptics.heavyImpact();
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text("Manage $type",
            style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : Colors.black54)),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              widget.onRequestSearch(type.toUpperCase());
            },
            child: const Text("Edit Address"),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              final user = Supabase.instance.client.auth.currentUser;
              if (user != null) {
                String column = type == 'Home' ? 'home_place' : 'work_place';
                await Supabase.instance.client
                    .from('user_profiles')
                    .update({column: null}).eq('id', user.id);
              } else {
                if (type == 'Home') {
                  await SavedPlacesService.deleteHome();
                } else if (type == 'Work') {
                  await SavedPlacesService.deleteWork();
                }
              }
              await refreshData();
            },
            child: const Text("Remove"),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎯 PRIMARY ACTION BUTTON HANDLERS (State Machine Driven)
  // ═══════════════════════════════════════════════════════════════════════════

  void _onStartNavTap(MapProvider provider) {
    AppHaptics.heavyImpact();
    provider.startActiveNavigation(context);
  }

  void _onStopNavTap(MapProvider provider) {
    AppHaptics.heavyImpact();
    provider.cancelAndClearRoute();
  }

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLightMode;


    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _isLoading
          ? const SizedBox(
              height: 86, child: Center(child: CupertinoActivityIndicator()))
          : Selector<MapProvider, MapUIState>(
              selector: (context, provider) => provider.currentUIState,
              builder: (context, uiState, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ─── Primary Action Button (State-Morphing) ───
                    _buildPrimaryActionButton(uiState, context, isDark),

                    // ─── Home / Work / Add Row (hidden during navigation) ───
                    if (uiState == MapUIState.idle)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            GestureDetector(
                              onLongPress: _homePlace != null
                                  ? () => _handleLongPress('Home')
                                  : null,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildPremiumCircleButton(
                                    icon: CupertinoIcons.house_fill,
                                    iconColor: _homePlace != null
                                        ? const Color(0xFF0A84FF)
                                        : const Color(0xFF0A84FF),
                                    bgColor: const Color(0xFF0A84FF).withValues(alpha: 0.12),
                                    size: 52.0,
                                    iconSize: 24.0,
                                    onTap: _handleHomeTap,
                                  ),
                                  const SizedBox(height: 8),
                                  Text("Home",
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onLongPress: _workPlace != null
                                  ? () => _handleLongPress('Work')
                                  : null,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildPremiumCircleButton(
                                    icon: CupertinoIcons.briefcase_fill,
                                    iconColor: _workPlace != null
                                        ? const Color(0xFF0A84FF)
                                        : const Color(0xFF0A84FF),
                                    bgColor: const Color(0xFF0A84FF).withValues(alpha: 0.12),
                                    size: 52.0,
                                    iconSize: 24.0,
                                    onTap: _handleWorkTap,
                                  ),
                                  const SizedBox(height: 8),
                                  Text("Work",
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            Builder(
                              builder: (context) {
                                final isAddingStop = context.watch<MapProvider>().isAddingStopMode;
                                final thirdLabel = isAddingStop ? "Drop Pin" : "Add Place";
                                final thirdIcon = isAddingStop ? Icons.location_on_rounded : CupertinoIcons.add;
                                final thirdColor = isAddingStop ? Colors.amber.shade600 : const Color(0xFF0A84FF);
                                final thirdBg = isAddingStop ? Colors.amber.shade600.withValues(alpha: 0.12) : const Color(0xFF0A84FF).withValues(alpha: 0.12);

                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildPremiumCircleButton(
                                      icon: thirdIcon,
                                      iconColor: thirdColor,
                                      bgColor: thirdBg,
                                      size: 52.0,
                                      iconSize: 26.0,
                                      onTap: () {
                                        if (isAddingStop) {
                                          AppHaptics.heavyImpact();
                                          context.read<MapProvider>().setDropPinMode(true);
                                          widget.onDropPinTapped?.call();
                                        } else {
                                          _handleAddPlaceTap();
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    Text(thirdLabel,
                                        style: TextStyle(
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black54,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                );
                              }
                            ),
                          ],
                        ),
                      ),

                  ],
                );
              },
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎯 PRIMARY ACTION BUTTON — The Morphing Button
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPrimaryActionButton(
      MapUIState uiState, BuildContext context, bool isDark) {
    // Don't show anything in idle state — the Home/Work/Add row IS the UI
    if (uiState == MapUIState.idle) {
      return const SizedBox.shrink();
    }

    // Define button properties based on state
    final _ActionButtonConfig config = switch (uiState) {
      MapUIState.placeSelected => _ActionButtonConfig(
          icon: CupertinoIcons.arrow_turn_up_right,
          label: 'Directions',
          gradient: const [Color(0xFF007AFF), Color(0xFF00BFFF)],
          onTap: () async {
            AppHaptics.heavyImpact();

            // 1. Force location refresh to prevent silent routing failures
            final locService =
                Provider.of<GlobalLocationService>(context, listen: false);
            if (locService.currentPosition == null) {
              await locService.forceRefreshLocation();
            }

            // 2. Calculate and draw the route
            if (!context.mounted) return;
            final provider = Provider.of<MapProvider>(context, listen: false);
            await provider.calculateAndDrawNativeRoute(
                context, provider.currentNavMode);
          },
        ),
      MapUIState.routeDrawn => _ActionButtonConfig(
          icon: CupertinoIcons.play_fill,
          label: 'Start',
          gradient: const [Color(0xFF007AFF), Color(0xFF0055FF)],
          onTap: () => _onStartNavTap(context.read<MapProvider>()),
        ),
      MapUIState.navigating => _ActionButtonConfig(
          icon: CupertinoIcons.xmark,
          label: 'End',
          gradient: const [Color(0xFF2C2C2E), Color(0xFF1C1C1E)],
          onTap: () => _onStopNavTap(context.read<MapProvider>()),
        ),
      MapUIState.idle => _ActionButtonConfig(
          icon: CupertinoIcons.location_fill,
          label: 'Explore',
          gradient: const [Color(0xFF8E8E93), Color(0xFFC7C7CC)],
          onTap: () {},
        ),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        key: ValueKey(uiState),
        onTap: config.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: config.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: config.gradient.first.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
                spreadRadius: -2,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(config.icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                config.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔘 GLASS ACTION BUTTON (Home / Work / Add)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPremiumCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
    Color? bgColor,
    double size = 44.0,
    double iconSize = 20.0,
  }) {
    return RidelBounceButton(
      onTap: () {
        AppHaptics.lightImpact();
        onTap();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          gradient: bgColor == null ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.20),
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.06),
            ],
          ) : null,
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              spreadRadius: -2,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 📦 INTERNAL CONFIG (Maps state → button visual properties)
// ═══════════════════════════════════════════════════════════════════════════

class _ActionButtonConfig {
  final IconData icon;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _ActionButtonConfig({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });
}

class DesktopZoomPill extends StatelessWidget {
  const DesktopZoomPill({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // Blocks stray taps
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA), width: 0.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8), spreadRadius: 0),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(50),
          child: RepaintBoundary(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: kIsWeb ? 4.0 : 20.0, sigmaY: kIsWeb ? 4.0 : 20.0),
              child: Container(
                width: 48,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0B0E17).withValues(alpha: 0.80) : Colors.white.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ContinuousZoomButton(
                      icon: Icons.add_rounded, isDark: isDark,
                      onZoomStep: () {
                        final ctrl = Provider.of<MapProvider>(context, listen: false).controller;
                        final z = ctrl?.cameraPosition?.zoom ?? 14.0;
                        ctrl?.moveCamera(CameraUpdate.zoomTo(z + 0.06));
                      },
                    ),
                    // CRITICAL: NO DIVIDER HERE TO MATCH THE TOP PILL
                    _ContinuousZoomButton(
                      icon: Icons.remove_rounded, isDark: isDark,
                      onZoomStep: () {
                        final ctrl = Provider.of<MapProvider>(context, listen: false).controller;
                        final z = ctrl?.cameraPosition?.zoom ?? 14.0;
                        ctrl?.moveCamera(CameraUpdate.zoomTo(z - 0.06));
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return kIsWeb ? PointerInterceptor(child: content) : content;
  }
}

class _ContinuousZoomButton extends StatefulWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onZoomStep;
  const _ContinuousZoomButton({required this.icon, required this.isDark, required this.onZoomStep});
  @override
  State<_ContinuousZoomButton> createState() => _ContinuousZoomButtonState();
}

class _ContinuousZoomButtonState extends State<_ContinuousZoomButton> {
  // ... keep existing _startZooming / _stopZooming logic ...
  Timer? _timer; Timer? _delayTimer;
  void _startZooming() { if (_timer != null || _delayTimer != null) return; AppHaptics.lightImpact(); widget.onZoomStep(); _delayTimer = Timer(const Duration(milliseconds: 300), () { _timer = Timer.periodic(const Duration(milliseconds: 40), (timer) { widget.onZoomStep(); }); }); }
  void _stopZooming() { _delayTimer?.cancel(); _delayTimer = null; _timer?.cancel(); _timer = null; }
  @override void dispose() { _stopZooming(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _startZooming(), onTapUp: (_) => _stopZooming(), onTapCancel: _stopZooming,
      child: SizedBox(
        height: 44, // EXACTLY 44px TO MATCH TOP PILL (Was 48)
        width: 48,
        child: Center(child: Icon(widget.icon, color: widget.isDark ? Colors.white70 : Colors.black87, size: 20)), // EXACTLY 20px TO MATCH TOP PILL
      ),
    );
  }
}
