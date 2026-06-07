import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';

import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart';
import 'package:ridel/features/map/services/place_api_services.dart';

import 'saved_place.dart';
import 'places_repository.dart' as saved;

// ============================================================
// 🧭 SHEET STATE MACHINE
// ============================================================
enum SheetState { idle, selectingLocation, editing }

// ============================================================
// 🗺️ ANIMATED MAP PIN (Floating center pin overlay)
// ============================================================
class AnimatedMapPin extends StatefulWidget {
  const AnimatedMapPin({super.key});

  @override
  State<AnimatedMapPin> createState() => _AnimatedMapPinState();
}

class _AnimatedMapPinState extends State<AnimatedMapPin>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _bounceAnimation = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounceAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _bounceAnimation.value),
          child: child,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0A84FF), Color(0xFF5AC8FA)],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0A84FF).withValues(alpha: 0.4),
                  blurRadius: 16,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              CupertinoIcons.location_solid,
              color: Colors.white,
              size: 20,
            ),
          ),
          // Pin shadow/tail
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0A84FF),
                  const Color(0xFF0A84FF).withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          Container(
            width: 8,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🏠 LOCATION PICKER CONTROLLER
// Manages the picker's state independently from the sheet,
// so the sheet only reacts to high-level events.
// ============================================================
class LocationPickerController extends ChangeNotifier {
  final saved.PlacesRepository _repository;

  final ValueNotifier<SheetState> sheetState =
      ValueNotifier(SheetState.idle);

  String? _activePickerType; // 'home', 'work', 'custom'
  String get activePickerType => _activePickerType ?? '';

  LatLng? _pickedCoordinates;
  LatLng? get pickedCoordinates => _pickedCoordinates;

  String _pickedAddress = '';
  String get pickedAddress => _pickedAddress;

  bool _isReverseGeocoding = false;
  bool get isReverseGeocoding => _isReverseGeocoding;

  Timer? _geocodeDebounce;
  final PlaceEnrichmentService _enrichmentService = PlaceEnrichmentService();

  LocationPickerController(this._repository);

  /// Begin selecting a location for a given type (home/work/custom)
  void startSelection(String type) {
    _activePickerType = type;
    _pickedAddress = '';
    _pickedCoordinates = null;
    sheetState.value = SheetState.selectingLocation;
    AppHaptics.mediumImpact();
    notifyListeners();
  }

  /// Begin editing an existing saved place
  void startEditing(String type) {
    _activePickerType = type;
    sheetState.value = SheetState.editing;
    AppHaptics.selectionClick();
    notifyListeners();
  }

  /// Called when the map camera moves — debounced reverse geocoding
  void onCameraMove(LatLng center) {
    _pickedCoordinates = center;
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(const Duration(milliseconds: 500), () {
      _performReverseGeocode(center);
    });
  }

  Future<void> _performReverseGeocode(LatLng coords) async {
    _isReverseGeocoding = true;
    notifyListeners();

    try {
      final place = await _enrichmentService.reverseGeocode(
        coords.latitude,
        coords.longitude,
      );
      _pickedAddress = place.address;
    } catch (e) {
      _pickedAddress =
          '${coords.latitude.toStringAsFixed(5)}, ${coords.longitude.toStringAsFixed(5)}';
    }

    _isReverseGeocoding = false;
    notifyListeners();
  }

  /// Confirm the picked location and persist it
  Future<bool> confirmSelection() async {
    if (_pickedCoordinates == null || _activePickerType == null) return false;

    final place = SavedPlace(
      id: _activePickerType!,
      type: _activePickerType!,
      title: _activePickerType == 'home'
          ? 'Home'
          : _activePickerType == 'work'
              ? 'Work'
              : 'Custom',
      address: _pickedAddress,
      lat: _pickedCoordinates!.latitude,
      lng: _pickedCoordinates!.longitude,
    );

    await _repository.addOrUpdatePlace(place);
    AppHaptics.success();

    cancelSelection();
    return true;
  }

  /// Delete a saved place
  Future<void> deleteSavedPlace(String type) async {
    await _repository.deletePlace(type);
    AppHaptics.mediumImpact();
    cancelSelection();
  }

  /// Cancel and reset to idle
  void cancelSelection() {
    _activePickerType = null;
    _pickedAddress = '';
    _pickedCoordinates = null;
    _geocodeDebounce?.cancel();
    sheetState.value = SheetState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    sheetState.dispose();
    super.dispose();
  }
}

// ============================================================
// 🏠 SAVED PLACES ROW (Home / Work / Add Place with state management)
// ============================================================
class SavedPlacesRow extends StatelessWidget {
  final bool isDark;
  final LocationPickerController pickerController;
  final saved.PlacesRepository repository;
  final VoidCallback? onPlaceTapped; // To fly to a saved place

  const SavedPlacesRow({
    super.key,
    required this.isDark,
    required this.pickerController,
    required this.repository,
    this.onPlaceTapped,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<SavedPlace>>(
      valueListenable: repository.savedPlacesNotifier,
      builder: (context, places, _) {
        final homePlace =
            places.where((p) => p.type == 'home').firstOrNull;
        final workPlace =
            places.where((p) => p.type == 'work').firstOrNull;

        return ValueListenableBuilder<SheetState>(
          valueListenable: pickerController.sheetState,
          builder: (context, state, _) {
            // When selectingLocation or editing, show the picker UI
            if (state == SheetState.selectingLocation) {
              return _buildSelectionUI(context);
            }
            if (state == SheetState.editing) {
              return _buildEditUI(context, homePlace, workPlace);
            }

            // Default idle: show Home / Work / Add Place buttons
            return _buildIdleRow(context, homePlace, workPlace);
          },
        );
      },
    );
  }

  Widget _buildIdleRow(
      BuildContext context, SavedPlace? home, SavedPlace? work) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SavedPlaceChip(
            icon: CupertinoIcons.house_fill,
            label: 'Home',
            subtitle: home?.address,
            isDark: isDark,
            iconColor: const Color(0xFF0A84FF),
            hasValue: home != null,
            onTap: () {
              if (home != null) {
                // Navigate to saved home
                final provider =
                    Provider.of<MapProvider>(context, listen: false);
                provider.flyToPlace(home.lat, home.lng);
                onPlaceTapped?.call();
              } else {
                pickerController.startSelection('home');
              }
            },
            onLongPress: () {
              if (home != null) {
                pickerController.startEditing('home');
              } else {
                pickerController.startSelection('home');
              }
            },
          ),
          const SizedBox(width: 16),
          _SavedPlaceChip(
            icon: CupertinoIcons.briefcase_fill,
            label: 'Work',
            subtitle: work?.address,
            isDark: isDark,
            iconColor: const Color(0xFF5856D6),
            hasValue: work != null,
            onTap: () {
              if (work != null) {
                final provider =
                    Provider.of<MapProvider>(context, listen: false);
                provider.flyToPlace(work.lat, work.lng);
                onPlaceTapped?.call();
              } else {
                pickerController.startSelection('work');
              }
            },
            onLongPress: () {
              if (work != null) {
                pickerController.startEditing('work');
              } else {
                pickerController.startSelection('work');
              }
            },
          ),
          const SizedBox(width: 16),
          _SavedPlaceChip(
            icon: CupertinoIcons.add,
            label: 'Add Place',
            isDark: isDark,
            iconColor: const Color(0xFF34C759),
            hasValue: false,
            onTap: () {
              pickerController.startSelection('custom');
            },
            onLongPress: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionUI(BuildContext context) {
    final type = pickerController.activePickerType;
    final label = type == 'home'
        ? 'Home'
        : type == 'work'
            ? 'Work'
            : 'Place';

    return ListenableBuilder(
      listenable: pickerController,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Address display bar
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.location_solid,
                    size: 18,
                    color: Color(0xFF0A84FF),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: pickerController.isReverseGeocoding
                        ? Row(
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black38,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Locating...',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black45,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            pickerController.pickedAddress.isNotEmpty
                                ? pickerController.pickedAddress
                                : 'Move the map to pick a location',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ],
              ),
            ),

            // Instructional label
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.move,
                    size: 14,
                    color:
                        isDark ? Colors.white38 : Colors.black38,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Adjust pin to set your $label location',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),

            // Confirm & Cancel buttons
            Row(
              children: [
                Expanded(
                  child: RidelLiquidButton(
                    width: double.infinity,
                    height: 50,
                    enableStretch: true,
                    glassTint: const Color(0xFF0A84FF).withValues(alpha: 0.2),
                    onTap: () async {
                      AppHaptics.mediumImpact();
                      final success =
                          await pickerController.confirmSelection();
                      if (success && context.mounted) {
                        ToastService.showSuccess(
                          context,
                          '$label location saved!',
                        );
                      }
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_rounded,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          'Confirm',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RidelLiquidButton(
                    width: double.infinity,
                    height: 50,
                    enableStretch: true,
                    glassTint:
                        Colors.white.withValues(alpha: 0.08),
                    onTap: () {
                      AppHaptics.lightImpact();
                      pickerController.cancelSelection();
                    },
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Colors.white70,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildEditUI(
      BuildContext context, SavedPlace? home, SavedPlace? work) {
    final type = pickerController.activePickerType;
    final place = type == 'home' ? home : work;
    final label = type == 'home' ? 'Home' : 'Work';
    final icon =
        type == 'home' ? CupertinoIcons.house_fill : CupertinoIcons.briefcase_fill;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Current saved info
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A84FF).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: const Color(0xFF0A84FF), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      place?.address ?? 'Not set',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Edit / Delete / Cancel row
        Row(
          children: [
            // Re-pick location
            Expanded(
              child: RidelLiquidButton(
                width: double.infinity,
                height: 50,
                enableStretch: true,
                glassTint: const Color(0xFF0A84FF).withValues(alpha: 0.2),
                onTap: () {
                  pickerController.startSelection(type);
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.edit_location_alt_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Change',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Delete
            Expanded(
              child: RidelLiquidButton(
                width: double.infinity,
                height: 50,
                enableStretch: true,
                glassTint: const Color(0xFFFF3B30).withValues(alpha: 0.18),
                onTap: () async {
                  await pickerController.deleteSavedPlace(type);
                  if (context.mounted) {
                    ToastService.showSuccess(
                      context,
                      '$label location removed',
                    );
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.delete,
                        color: Color(0xFFFF3B30), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Delete',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: const Color(0xFFFF3B30),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Cancel
            Expanded(
              child: RidelLiquidButton(
                width: double.infinity,
                height: 50,
                enableStretch: true,
                glassTint: Colors.white.withValues(alpha: 0.08),
                onTap: () {
                  AppHaptics.lightImpact();
                  pickerController.cancelSelection();
                },
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================
// 🏠 INDIVIDUAL SAVED PLACE CHIP
// ============================================================
class _SavedPlaceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool isDark;
  final Color iconColor;
  final bool hasValue;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SavedPlaceChip({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.isDark,
    required this.iconColor,
    required this.hasValue,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AppHaptics.lightImpact();
        onTap();
      },
      onLongPress: () {
        AppHaptics.heavyImpact();
        onLongPress();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  iconColor.withValues(alpha: 0.25),
                  iconColor.withValues(alpha: 0.12),
                ],
              ),
              border: Border.all(
                color: hasValue
                    ? iconColor.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.18),
                width: hasValue ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: hasValue
                      ? iconColor.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.35),
                  blurRadius: 20,
                  spreadRadius: -2,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
              letterSpacing: 0.3,
            ),
          ),
          if (hasValue && subtitle != null) ...[
            const SizedBox(height: 2),
            SizedBox(
              width: 72,
              child: Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
