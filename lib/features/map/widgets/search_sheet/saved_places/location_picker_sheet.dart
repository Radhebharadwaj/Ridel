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
import 'package:ridel/features/map/models/place_model.dart';

import 'saved_place.dart';
import 'places_repository.dart' as saved;
import 'package:ridel/core/widgets/branded_loader.dart';

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
  late AnimationController _swayController;
  late Animation<double> _swayAnimation;

  @override
  void initState() {
    super.initState();
    _swayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _swayAnimation = Tween<double>(begin: -0.06, end: 0.06).animate(
      CurvedAnimation(parent: _swayController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _swayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _swayAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _swayAnimation.value,
          alignment: Alignment.bottomCenter, // CRITICAL: Locks the sharp point to the map
          child: child,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
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
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              CupertinoIcons.location_solid,
              color: Colors.white,
              size: 25,
            ),
          ),
          // Pin shadow/tail
          Container(
            width: 4,
            height: 18,
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
            width: 10,
            height: 5,
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

  final ValueNotifier<SheetState> sheetState = ValueNotifier(SheetState.idle);

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
    _geocodeDebounce = Timer(const Duration(milliseconds: 1500), () {
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
        final homePlace = places.where((p) => p.type == 'home').firstOrNull;
        final workPlace = places.where((p) => p.type == 'work').firstOrNull;

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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SavedPlaceChip(
          icon: CupertinoIcons.house_fill,
          label: 'Home',
          subtitle: home?.address,
          isDark: isDark,
          iconColor: CupertinoColors.systemBlue,
          hasValue: home != null,
          onTap: () async {
            if (home != null) {
              // Navigate to saved home
              final provider =
                  Provider.of<MapProvider>(context, listen: false);
              await provider.cancelAndClearRoute(resetCamera: false);
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
        const SizedBox(width: 24.0),
        _SavedPlaceChip(
          icon: CupertinoIcons.briefcase_fill,
          label: 'Work',
          subtitle: work?.address,
          isDark: isDark,
          iconColor: CupertinoColors.systemBlue,
          hasValue: work != null,
          onTap: () async {
            if (work != null) {
              final provider =
                  Provider.of<MapProvider>(context, listen: false);
              await provider.cancelAndClearRoute(resetCamera: false);
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
        const SizedBox(width: 24.0),
        _SavedPlaceChip(
          icon: CupertinoIcons.add,
          label: 'Add Place',
          isDark: isDark,
          iconColor: CupertinoColors.systemBlue,
          hasValue: false,
          onTap: () {
            pickerController.startSelection('custom');
          },
          onLongPress: () {},
        ),
      ],
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: BrandedLoader(isFullScreen: false),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Locating...',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color:
                                      isDark ? Colors.white54 : Colors.black45,
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
                    color: isDark ? Colors.white38 : Colors.black38,
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
                      final provider = context.read<MapProvider>();
                      final selectedLocation = provider.targetDestination;

                      if (provider.isAddingStopMode && selectedLocation != null) {
                        AppHaptics.success();

                        // 1. Add the stop to the list
                        provider.addIntermediateStop(
                          PlaceModel(
                            placeId: 'pinned_${DateTime.now().millisecondsSinceEpoch}',
                            name: 'Dropped Pin',
                            address: '${selectedLocation.latitude.toStringAsFixed(4)}, ${selectedLocation.longitude.toStringAsFixed(4)}',
                            latitude: selectedLocation.latitude,
                            longitude: selectedLocation.longitude,
                            categories: ['unknown'],
                          ),
                        );

                        // 2. Reset the picking states
                        provider.setDropPinMode(false);
                        provider.setAddingStopMode(false);

                        // 3. Trigger route recalculation seamlessly
                        if (context.mounted) {
                          provider.calculateAndDrawRoute(context);
                        }

                        pickerController.cancelSelection();
                      } else {
                        final success = await pickerController.confirmSelection();
                        if (success && context.mounted) {
                          ToastService.showSuccess(
                            context,
                            '$label location saved!',
                          );
                        }
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
                    glassTint: Colors.white.withValues(alpha: 0.08),
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
    final icon = type == 'home'
        ? CupertinoIcons.house_fill
        : CupertinoIcons.briefcase_fill;

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
            width: 60.0,
            height: 60.0,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.15),
                  Colors.white.withValues(alpha: 0.05),
                ],
              ),
            ),
            child: Icon(
              icon, 
              size: 30.0, 
              color: iconColor,
              shadows: const [
                Shadow(
                  color: Colors.black45,
                  blurRadius: 4.0,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8.0),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500, // Medium
              color: Colors.white,
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
