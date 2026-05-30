import 'dart:math';
import 'dart:ui'; // 🌟 Added for ImageFilter

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/universal_mic_button.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/app_shadows.dart'; // 🚀 Added for premium shadows
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/features/commute/bus/services/bus_service.dart';
import 'package:ridel/features/commute/metro/services/metro_service.dart';
import 'package:ridel/features/commute/shared/screens/route_result_screen.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';
import 'package:ridel/features/commute/shared/widgets/station_selector_sheet.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart'; // 🚀 MASTER BUTTON IMPORT
import 'package:ridel/core/widgets/ridel_premium_loader.dart';
import 'package:url_launcher/url_launcher.dart';

class CommuteSearchCard extends StatefulWidget {
  final bool isDark;
  final int selectedMode;
  final String? activeTicketingMode;
  final Function(String?)? onTicketingModeChanged;

  const CommuteSearchCard(
      {super.key,
      required this.isDark,
      required this.selectedMode,
      this.activeTicketingMode,
      this.onTicketingModeChanged});

  @override
  State<CommuteSearchCard> createState() => _CommuteSearchCardState();
}

class _CommuteSearchCardState extends State<CommuteSearchCard> {
  final TextEditingController _fromCtrl = TextEditingController();
  final TextEditingController _toCtrl = TextEditingController();

  String _metroFrom = "";
  String _metroTo = "";
  String _busFrom = "";
  String _busTo = "";

  List<Map<String, dynamic>> _allStationsCache = [];
  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _nearestLocationsCache = [];

  bool _isSearchingFrom = true;
  bool _isRouteLoading = false;

  // 🚀 Naye Animation Variables for Floating Swap Button
  double _swapTurns = 0.0;
  bool _isSwapPressed = false;
  int _ticketCount = 1;

  String _calculatedFare = "₹0";
  bool _isCalculatingFare = false;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  Color get _accentColor => widget.selectedMode == 0
      ? (widget.isDark ? const Color(0xFF00E5FF) : Colors.cyan.shade600)
      : (widget.isDark ? const Color(0xFFFF9F0A) : Colors.orange.shade700);
  String get _locationTerm => widget.selectedMode == 0 ? "Station" : "Stop";

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllStationsForFuzzySearch()
          .then((_) => _calculateNearestLocationsInBackground());
    });
  }

  @override
  void didUpdateWidget(CommuteSearchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTicketingMode != widget.activeTicketingMode &&
        widget.activeTicketingMode == 'fare_calc') {
      _calculateDynamicFare();
    }
    if (oldWidget.selectedMode != widget.selectedMode) {
      if (oldWidget.selectedMode == 0) {
        _metroFrom = _fromCtrl.text;
        _metroTo = _toCtrl.text;
      } else {
        _busFrom = _fromCtrl.text;
        _busTo = _toCtrl.text;
      }

      if (widget.selectedMode == 0) {
        _fromCtrl.text = _metroFrom;
        _toCtrl.text = _metroTo;
      } else {
        _fromCtrl.text = _busFrom;
        _toCtrl.text = _busTo;
      }

      _loadAllStationsForFuzzySearch()
          .then((_) => _calculateNearestLocationsInBackground());
    }
  }

  // 🚀 FIXED REAL-TIME FARE CALCULATOR
  Future<void> _calculateDynamicFare() async {
    if (_fromCtrl.text.isEmpty ||
        _toCtrl.text.isEmpty ||
        widget.selectedMode != 0) {
      return;
    }

    setState(() {
      _isCalculatingFare = true;
      _calculatedFare = "Calc..."; // Loading indicator text
    });

    try {
      // 1. Pehle route find karo
      final result =
          await MetroService().findBestRoute(_fromCtrl.text, _toCtrl.text);

      if (!mounted) return;

      if (result != null && result.path.isNotEmpty) {
        // 2. Agar `totalFare` directly populated nahi hai, toh safe fallback logic lagao
        // MetroFareConfig use karke ya fir existing totalFare property use karke.
        int finalFare = 0;

        // Kabhi-kabhi result.totalFare double hoti hai, kabhi int. Isliye safe parsing.
        if (result.totalFare > 0) {
          finalFare = result.totalFare.toInt();
        } else {
          // Agar 0 aa raha hai (backend se route mein fare nahi aaya),
          // toh fallback to minimum fare or generic calculation (DMRC rules approx)
          // Hum route result page ki tarah fare service yahan bhi inject kar sakte hain.
          // For now, let's strictly use the result's calculated value if MetroService is working.
          debugPrint(
              "Warning: Route returned 0 fare. Check MetroService config.");
        }

        setState(() {
          _calculatedFare = finalFare > 0 ? "₹$finalFare" : "N/A";
          _isCalculatingFare = false;
        });
      } else {
        setState(() {
          _calculatedFare = "N/A";
          _isCalculatingFare = false;
        });
      }
    } catch (e) {
      debugPrint("Fare Calc Error: $e");
      if (mounted) {
        setState(() {
          _calculatedFare = "Err";
          _isCalculatingFare = false;
        });
      }
    }
  }

  Future<void> _loadAllStationsForFuzzySearch() async {
    final results =
        await DatabaseHelper.instance.getStationsByMode(widget.selectedMode);
    if (mounted) {
      setState(() {
        _allStationsCache = results;
        _suggestions = [];
      });
    }
  }

  Future<void> _calculateNearestLocationsInBackground() async {
    try {
      if (_allStationsCache.isEmpty) return;

      final locService =
          Provider.of<GlobalLocationService>(context, listen: false);

      if (!locService.hasValidLocation) {
        await locService.initializeEcoLocation();
      }

      final pos = locService.currentPosition;
      if (pos == null) return;

      List<Map<String, dynamic>> calculatedList = [];

      for (var rawLoc in _allStationsCache) {
        double lat = double.tryParse(rawLoc['lat'].toString()) ?? 0.0;
        double lng =
            double.tryParse((rawLoc['lon'] ?? rawLoc['lng']).toString()) ?? 0.0;
        if (lat == 0.0 || lng == 0.0) continue;

        double distance =
            Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);

        calculatedList.add({...rawLoc, 'distance': distance});
      }

      calculatedList.sort((a, b) =>
          (a['distance'] as double).compareTo(b['distance'] as double));

      List<Map<String, dynamic>> uniqueLocations = [];
      Set<String> seenNames = {};

      for (var item in calculatedList) {
        String cleanName = item['stop_name'].toString().toLowerCase().trim();
        if (!seenNames.contains(cleanName)) {
          seenNames.add(cleanName);
          uniqueLocations.add(item);
        }
        if (uniqueLocations.length >= 5) break;
      }

      if (mounted && uniqueLocations.isNotEmpty) {
        setState(() {
          _nearestLocationsCache = uniqueLocations;
        });

        if (_fromCtrl.text.isEmpty) {
          ToastService.showSuccess(
            context,
            _toTitleCase(uniqueLocations.first['stop_name']),
            title: "Nearest $_locationTerm",
            onTap: () {
              AppHaptics.heavyImpact();
              setState(() => _fromCtrl.text =
                  _toTitleCase(uniqueLocations.first['stop_name']));
            },
          );
        }
      }
    } catch (e) {
      debugPrint("Nearest Location Error: $e");
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query, bool isFrom) {
    _isSearchingFrom = isFrom;

    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }

    final String currentFrom = _fromCtrl.text.toLowerCase().trim();
    final String currentTo = _toCtrl.text.toLowerCase().trim();

    bool isAlreadySelected(String stationName) {
      final name = stationName.toLowerCase().trim();
      return name == currentFrom || name == currentTo;
    }

    if (query.isEmpty) {
      if (_nearestLocationsCache.isNotEmpty) {
        final filteredNearest = _nearestLocationsCache
            .where((s) => !isAlreadySelected(s['stop_name']))
            .toList();

        setState(() => _suggestions = filteredNearest);
        if (_suggestions.isNotEmpty) {
          _showOverlay();
        } else {
          _removeOverlay();
        }
      } else {
        setState(() => _suggestions = []);
        _removeOverlay();
      }
      return;
    }

    final lowerQuery = query.toLowerCase();
    final Set<String> seenNames = {};
    final List<Map<String, dynamic>> uniqueResults = [];

    final exactMatches = _allStationsCache.where((s) {
      if (isAlreadySelected(s['stop_name'])) return false;
      return s['stop_name']
          .toString()
          .toLowerCase()
          .trim()
          .contains(lowerQuery);
    });

    for (var s in exactMatches) {
      if (seenNames.add(s['stop_name'])) {
        uniqueResults.add(s);
      }
    }

    if (uniqueResults.length < 3 && query.length > 2) {
      final fuzzyMatches = _allStationsCache.where((s) {
        if (isAlreadySelected(s['stop_name'])) return false;
        if (seenNames.contains(s['stop_name'])) return false;

        return _levenshtein(
                s['stop_name'].toString().toLowerCase().trim(), lowerQuery) <=
            2;
      });

      for (var s in fuzzyMatches) {
        if (seenNames.add(s['stop_name'])) {
          uniqueResults.add(s);
        }
      }
    }

    setState(() => _suggestions = uniqueResults.take(5).toList());

    if (_suggestions.isNotEmpty) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _showOverlay() {
    if (_overlayEntry == null) {
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
    } else {
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;

    return OverlayEntry(
      builder: (context) {
        double yOffset = _isSearchingFrom ? 65.0 : 125.0;

        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, yOffset),
            child: TapRegion(
              groupId: 'search_card',
              child: Material(
                  color: Colors.transparent, child: _buildMatteSuggestions()),
            ),
          ),
        );
      },
    );
  }

  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;
    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);
    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j < t.length + 1; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }

  void _onSuggestionTap(Map<String, dynamic> station) {
    AppHaptics.selectionClick();
    setState(() {
      if (_isSearchingFrom) {
        _fromCtrl.text = station['stop_name'];
      } else {
        _toCtrl.text = station['stop_name'];
      }
      _suggestions = [];
      FocusScope.of(context).unfocus();
    });
    _removeOverlay();
    if (widget.activeTicketingMode == 'fare_calc') {
      _calculateDynamicFare();
    }
  }

  void _swapLocations() {
    AppHaptics.lightImpact();
    final temp = _fromCtrl.text;
    setState(() {
      _fromCtrl.text = _toCtrl.text;
      _toCtrl.text = temp;
    });
  }

  void _detectNearestStation() async {
    AppHaptics.heavyImpact();
    setState(() => _fromCtrl.text = "Locating...");

    final locService =
        Provider.of<GlobalLocationService>(context, listen: false);

    await locService.forceRefreshLocation();

    if (mounted) {
      if (_nearestLocationsCache.isNotEmpty) {
        setState(
            () => _fromCtrl.text = _nearestLocationsCache.first['stop_name']);
        ToastService.showSuccess(context, "Nearest $_locationTerm located");
      } else {
        setState(() => _fromCtrl.text =
            widget.selectedMode == 0 ? "Rajiv Chowk" : "Kashmere Gate ISBT");
        ToastService.showError(
            context, "Could not get exact location, using default.");
      }
    }
  }

  Future<void> _openStationSheet({required bool isFrom}) async {
    AppHaptics.lightImpact();
    FocusScope.of(context).unfocus();
    _removeOverlay();

    await RidelSheet.show(
      context,
      title: "",
      customHeader: true,
      child: StationSelectorSheet(
        isSelectingSource: isFrom,
        isBusMode: widget.selectedMode == 1,
        currentFromStation: _fromCtrl.text.isEmpty
            ? null
            : {'stop_name': _fromCtrl.text, 'stop_id': 'mock_id_1'},
        currentToStation: _toCtrl.text.isEmpty
            ? null
            : {'stop_name': _toCtrl.text, 'stop_id': 'mock_id_2'},
        onStationSelected: (station, isSourceSelected) {
          setState(() {
            if (isSourceSelected) {
              _fromCtrl.text = station['stop_name'];
            } else {
              _toCtrl.text = station['stop_name'];
            }
          });
          if (widget.activeTicketingMode == 'fare_calc') {
            _calculateDynamicFare();
          }
        },
      ),
    );
  }

  void _handleMainButton() async {
    if (_fromCtrl.text.isEmpty && _toCtrl.text.isEmpty) {
      _openStationSheet(isFrom: true);
    } else if (_fromCtrl.text.isNotEmpty && _toCtrl.text.isEmpty) {
      _openStationSheet(isFrom: false);
    } else if (_fromCtrl.text.isNotEmpty && _toCtrl.text.isNotEmpty) {
      setState(() {
        _isRouteLoading = true;
      });
      ToastService.showSuccess(context, "Finding best route...");
      try {
        if (widget.selectedMode == 0) {
          final result =
              await MetroService().findBestRoute(_fromCtrl.text, _toCtrl.text);

          if (!mounted) return;

          if (result != null && result.path.isNotEmpty) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => RouteResultScreen(
                        fromStation: _fromCtrl.text,
                        toStation: _toCtrl.text,
                        routeData: result)));
          } else {
            ToastService.showError(context, "No route found.");
          }
        } else {
          final result =
              await BusService().findBusRoute(_fromCtrl.text, _toCtrl.text);

          if (!mounted) return;

          if (result != null && result.path.isNotEmpty) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => RouteResultScreen(
                          fromStation: _fromCtrl.text,
                          toStation: _toCtrl.text,
                          routeData: result,
                          isMetro: false,
                        )));
          } else {
            ToastService.showError(context, "No bus route found.");
          }
        }
      } catch (e) {
        debugPrint("Route Error: $e");
        if (!mounted) {
          return;
        }
        ToastService.showError(context, "Error finding route.");
      } finally {
        if (mounted) {
          setState(() {
            _isRouteLoading = false;
          });
        }
      }
    } else {
      _openStationSheet(isFrom: true);
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return "${meters.toInt()}m";
    return "${(meters / 1000).toStringAsFixed(1)}km";
  }

  // 🚀 BULLETPROOF BUTTON BUILDER: Original design safe via existing glassTint
  Widget _buildLiquidSearchButton({
    required VoidCallback onPressed,
    required String label,
    required IconData icon,
    required bool isReady,
    Color?
        customTint, // 🌟 Safe fallback: Only uses Color, perfectly compatible!
  }) {
    final defaultTint = isReady
        ? const Color(0xFF00E5FF).withValues(alpha: 0.18) // Deep Neon Cyan
        : const Color(0xFFFFFFFF).withValues(alpha: 0.75); // Premium white

    return RidelLiquidButton(
      width: double.infinity,
      height: 56,
      enableStretch: true,
      glassTint: customTint ?? defaultTint,
      onTap: onPressed,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.2),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: Row(
          key: ValueKey<bool>(isReady),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: isReady ? Colors.white : const Color(0xFF121419),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              icon,
              size: 20,
              color: isReady ? Colors.white : const Color(0xFF121419),
            ),
          ],
        ),
      ),
    );
  }

  // 🚀 NAYA HELPER: Third Input Bar (Capsule)
  Widget _buildInfoCapsule({required Widget child}) {
    final bool isLightMode = !widget.isDark;
    final Color inputBg = isLightMode
        ? Colors.white
        : const Color(0xFF000000).withValues(alpha: 0.6);

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: inputBg,
        borderRadius:
            BorderRadius.circular(100), // Same From/To jaisa oval shape
        border: Border.all(
          color: isLightMode
              ? Colors.black.withValues(alpha: 0.04)
              : Colors.white.withValues(alpha: 0.03),
          width: 1.0,
        ),
        boxShadow: isLightMode
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))]
            : null,
      ),
      child: child,
    );
  }

  // 🚀 UI MORPHING LOGIC (Perfected!)
  Widget _buildMorphedActionUI(
      String? mode, bool isReady, String btnLabel, IconData btnIcon) {
    if (_isRouteLoading) {
      return Padding(
        key: const ValueKey('loading'),
        padding: const EdgeInsets.only(top: 20),
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RidelPremiumLoader(size: 28, isDark: widget.isDark, primaryColor: _accentColor),
              const SizedBox(width: 16),
              Text(
                "Finding best route...",
                style: GoogleFonts.inter(
                  color: widget.isDark ? Colors.white70 : Colors.black54,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!isReady || mode == null) {
      return Padding(
        key: const ValueKey('normal'),
        padding: const EdgeInsets.only(top: 20),
        child: _buildLiquidSearchButton(
          onPressed: _handleMainButton,
          label: btnLabel,
          icon: btnIcon,
          isReady: isReady,
        ),
      );
    }

    if (mode == 'whatsapp') {
      return Padding(
        key: const ValueKey('whatsapp'),
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            _buildInfoCapsule(
                child: Row(
              children: [
                Text('Ticket Count',
                    style: GoogleFonts.inter(
                        color: widget.isDark ? Colors.white70 : Colors.black54,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const Spacer(), // Baaki ki space ko push karne ke liye

                // 🌟 SLIDE INDICATOR (Left)
                Icon(Icons.chevron_left_rounded,
                    size: 18,
                    color: widget.isDark ? Colors.white24 : Colors.black26),

                // 🌟 COMPACT DIAL CONTAINER
                SizedBox(
                  width:
                      110, // Dial ko compact aur premium rakhne ke liye fix width
                  child: ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return const LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black,
                          Colors.black,
                          Colors.transparent
                        ],
                        stops: [0.0, 0.3, 0.7, 1.0],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.dstIn,
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: ListWheelScrollView.useDelegate(
                        itemExtent:
                            40, // 🚀 FIX: Isko 50 se 40 kiya taaki numbers paas-paas aayein
                        perspective: 0.005,
                        diameterRatio: 1.5,
                        squeeze:
                            1.15, // 🚀 FIX: Numbers ko vertically aur tight squeeze karne ke liye
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (index) {
                          AppHaptics.selectionClick();
                          setState(() => _ticketCount = index + 1);
                        },
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: 6,
                          builder: (context, index) {
                            final count = index + 1;
                            final isSelected = count == _ticketCount;
                            return RotatedBox(
                              quarterTurns: 1,
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: GoogleFonts.inter(
                                    // 🚀 FIX: Neon hatakar pure white aur deeply faded colors
                                    color: isSelected
                                        ? (widget.isDark ? Colors.white : Colors.black87)
                                        : (widget.isDark
                                            ? Colors.white38
                                            : Colors.black38),
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    fontSize: isSelected ? 24 : 15,
                                  ),
                                  child: Text('$count'),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // 🌟 SLIDE INDICATOR (Right)
                Icon(Icons.chevron_right_rounded,
                    size: 18,
                    color: widget.isDark ? Colors.white24 : Colors.black26),
                const SizedBox(width: 4), // Halka sa right padding
              ],
            )),
            const SizedBox(height: 16),
            _buildLiquidSearchButton(
              onPressed: () async {
                // 🚀 DYNAMIC INTENT: Metro (0) vs Bus (1)
                final String phoneNumber = widget.selectedMode == 0
                    ? "919650855800" // DMRC Official WhatsApp Bot
                    : "918744073223"; // DTC Official WhatsApp Bot

                final text =
                    "Book $_ticketCount tickets from ${_fromCtrl.text} to ${_toCtrl.text}";

                // 🚀 FIX: Hardcoded number ki jagah $phoneNumber use kiya hai!
                final url = Uri.parse(
                    'https://wa.me/$phoneNumber?text=${Uri.encodeComponent(text)}');

                if (await canLaunchUrl(url)) {
                  // 🚀 BONUS FIX: externalApplication se WhatsApp app seedha khulega, browser nahi
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              label: "Confirm",
              icon: Icons.check_circle_outline,
              isReady: true,
              customTint: const Color(0xFF25D366)
                  .withValues(alpha: 0.35), // Premium WhatsApp Green Glass Tint
            ),
          ],
        ),
      );
    }

    if (mode == 'fare_calc') {
      return Padding(
        key: const ValueKey('fare'),
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            _buildInfoCapsule(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Fare',
                      style: GoogleFonts.inter(
                          color:
                              widget.isDark ? Colors.white70 : Colors.black54,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  _isCalculatingFare
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.cyanAccent))
                      : Text(_calculatedFare,
                          style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: widget.isDark ? Colors.cyanAccent : Colors.cyan.shade700)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildLiquidSearchButton(
                    onPressed: _handleMainButton,
                    label: "Find Route",
                    icon: Icons.directions_transit_filled_rounded,
                    isReady: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildLiquidSearchButton(
                    onPressed: () =>
                        widget.onTicketingModeChanged?.call('whatsapp'),
                    label: "Pay Now",
                    icon: Icons.payment_rounded,
                    isReady: true,
                    customTint: const Color(0xFF1A56DB).withValues(
                        alpha: 0.35), // Premium Deep Blue Glass Tint
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final bool isReady = _fromCtrl.text.isNotEmpty && _toCtrl.text.isNotEmpty;
    final String btnLabel = isReady ? "Find Route" : "Select  $_locationTerm";
    final IconData btnIcon = isReady
        ? Icons.directions_transit_filled_rounded
        : Icons.list_alt_rounded;

    final bool isLightMode = !widget.isDark;

    final Color glassColor = isLightMode
        ? Colors.white.withValues(alpha: 0.90)
        : const Color(0xFF161A25).withValues(alpha: 0.75);

    final Color inputBg = isLightMode
        ? Colors.white
        : const Color(0xFF000000).withValues(alpha: 0.6);
    final textColor = isLightMode ? Colors.black87 : Colors.white;
    final hintColor = isLightMode ? Colors.grey.shade500 : Colors.grey.shade400;

    return TapRegion(
      groupId: 'search_card',
      onTapOutside: (event) {
        FocusManager.instance.primaryFocus?.unfocus();
        _removeOverlay();
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(35),
                    boxShadow: isLightMode
                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))]
                        : [
                            ...AppShadows.cardFloating,
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.8),
                              blurRadius: 40,
                              spreadRadius: 8,
                              offset: const Offset(0, 15),
                            ),
                          ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(35),
                    clipBehavior: Clip.antiAliasWithSaveLayer,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                      child: Container(
                        decoration: BoxDecoration(
                          color: glassColor,
                          borderRadius: BorderRadius.circular(35),
                          border: Border.all(
                            color: isLightMode
                                ? Colors.black.withValues(alpha: 0.04)
                                : Colors.white.withValues(alpha: 0.12),
                            width: 1.0,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 108,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Column(
                                      children: [
                                        _buildSlimCapsule(
                                          leftIcon: Icons.my_location_rounded,
                                          leftIconColor: _accentColor,
                                          hint: "From $_locationTerm",
                                          controller: _fromCtrl,
                                          bgColor: inputBg,
                                          textColor: textColor,
                                          hintColor: hintColor,
                                          onLeftIconTap: _detectNearestStation,
                                          isDark: widget.isDark,
                                          onChanged: (val) =>
                                              _onSearchChanged(val, true),
                                          isFrom: true,
                                        ),
                                        const SizedBox(height: 8),
                                        _buildSlimCapsule(
                                          leftIcon: Icons.location_on_rounded,
                                          leftIconColor: Colors.redAccent,
                                          hint: "To $_locationTerm",
                                          controller: _toCtrl,
                                          bgColor: inputBg,
                                          textColor: textColor,
                                          hintColor: hintColor,
                                          onLeftIconTap: () {},
                                          isDark: widget.isDark,
                                          onChanged: (val) =>
                                              _onSearchChanged(val, false),
                                          isFrom: false,
                                        ),
                                      ],
                                    ),
                                    Positioned(
                                      right: 42,
                                      top: 0,
                                      bottom: 0,
                                      child: Center(
                                        child: GestureDetector(
                                          onTapDown: (_) => setState(
                                              () => _isSwapPressed = true),
                                          onTapUp: (_) {
                                            setState(() {
                                              _isSwapPressed = false;
                                              _swapTurns += 0.5;
                                            });
                                            _swapLocations();
                                          },
                                          onTapCancel: () => setState(
                                              () => _isSwapPressed = false),
                                          child: AnimatedScale(
                                            scale: _isSwapPressed ? 0.85 : 1.0,
                                            duration: const Duration(
                                                milliseconds: 150),
                                            curve: Curves.easeOutQuart,
                                            child: AnimatedRotation(
                                              turns: _swapTurns,
                                              duration: const Duration(
                                                  milliseconds: 600),
                                              curve: Curves.elasticOut,
                                              child: Container(
                                                height: 36,
                                                width: 36,
                                                decoration: BoxDecoration(
                                                  color: isLightMode
                                                      ? Colors.white
                                                      : const Color(0xFF1C1F26),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: isLightMode
                                                        ? Colors.black.withValues(alpha: 0.04)
                                                        : Colors.white.withValues(alpha: 0.15),
                                                    width: 1,
                                                  ),
                                                  boxShadow: isLightMode
                                                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))]
                                                      : AppShadows.cardFloating,
                                                ),
                                                child: Icon(
                                                  Icons.swap_vert_rounded,
                                                  size: 20,
                                                  color: isLightMode
                                                      ? Colors.black87
                                                      : Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  ],
                                ),
                              ),
                              // 🚀 Morphing Animation here
                              AnimatedSize(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOutCubic,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  transitionBuilder: (child, anim) =>
                                      FadeTransition(
                                    opacity: anim,
                                    child: SizeTransition(
                                        sizeFactor: anim, child: child),
                                  ),
                                  child: _buildMorphedActionUI(
                                      widget.activeTicketingMode,
                                      isReady,
                                      btnLabel,
                                      btnIcon),
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
      ),
    );
  }

  Widget _buildMatteSuggestions() {
    final bool isLightMode = !widget.isDark;
    final bgColor = isLightMode
        ? Colors.white.withValues(alpha: 0.95)
        : const Color(0xFF1E2129).withValues(alpha: 0.9);

    final borderColor = isLightMode
        ? Colors.black.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.12);
    final textColor = isLightMode ? Colors.black87 : Colors.white;

    final bool isNearestList =
        _suggestions.isNotEmpty && _suggestions.first.containsKey('distance');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor, width: 1.0),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isNearestList)
                  Container(
                    padding:
                        const EdgeInsets.only(top: 14, bottom: 8, left: 20),
                    alignment: Alignment.centerLeft,
                    child: Text("Nearest ${_locationTerm}s",
                        style: GoogleFonts.inter(
                            color: _accentColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5)),
                  ),
                Flexible(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: isLightMode
                            ? Colors.grey.shade200
                            : Colors.white.withValues(alpha: 0.05)),
                    itemBuilder: (context, index) {
                      final station = _suggestions[index];
                      final bool hasDistance = station.containsKey('distance');
                      final colorHex = station['route_color'] ?? "808080";
                      final mainColor = Color(int.parse("0xFF$colorHex"));
                      final bool isInterchange =
                          (station['is_interchange'] == 1);

                      BorderRadius? itemBorderRadius;
                      int totalItems = _suggestions.length;
                      if (totalItems == 1 && !isNearestList) {
                        itemBorderRadius = BorderRadius.circular(24);
                      } else if (index == 0 && !isNearestList) {
                        itemBorderRadius = const BorderRadius.vertical(
                            top: Radius.circular(24));
                      } else if (index == totalItems - 1) {
                        itemBorderRadius = const BorderRadius.vertical(
                            bottom: Radius.circular(24));
                      } else {
                        itemBorderRadius = BorderRadius.zero;
                      }

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: itemBorderRadius,
                          onTap: () => _onSuggestionTap(station),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 20),
                            child: Row(
                              children: [
                                if (hasDistance)
                                  Icon(
                                      widget.selectedMode == 0
                                          ? Icons.train_rounded
                                          : Icons.directions_bus_rounded,
                                      color: _accentColor,
                                      size: 18)
                                else
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                        color: isInterchange
                                            ? Colors.white
                                            : mainColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: isInterchange
                                                ? Colors.transparent
                                                : Colors.white
                                                    .withValues(alpha: 0.2),
                                            width: 1.5)),
                                  ),
                                const SizedBox(width: 14),
                                Expanded(
                                    child:
                                        Text(_toTitleCase(station['stop_name']),
                                            style: GoogleFonts.inter(
                                              color: textColor,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ))),
                                if (hasDistance)
                                  Text(_formatDistance(station['distance']),
                                      style: GoogleFonts.inter(
                                          color: _accentColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlimCapsule({
    required IconData leftIcon,
    required Color leftIconColor,
    required String hint,
    required TextEditingController controller,
    required Color bgColor,
    required Color textColor,
    required Color hintColor,
    required VoidCallback onLeftIconTap,
    required bool isDark,
    required Function(String) onChanged,
    required bool isFrom,
  }) {
    final bool isTyping = controller.text.isNotEmpty;
    final bool isLightMode = !isDark;

    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 12, right: 8),
      decoration: BoxDecoration(
        color: isLightMode ? Colors.white : bgColor,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: isLightMode
              ? Colors.black.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.03),
          width: 1.0,
        ),
        boxShadow: isLightMode
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))]
            : null,
      ),
      child: Row(
        children: [
          GestureDetector(
              onTap: onLeftIconTap,
              child: Container(
                  padding: const EdgeInsets.all(6),
                  color: Colors.transparent,
                  child: Icon(leftIcon, color: leftIconColor, size: 20))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
            controller: controller,
            onChanged: onChanged,
            onTap: () {
              _isSearchingFrom = isFrom;
              if (controller.text.isEmpty) {
                onChanged("");
              } else {
                onChanged(controller.text);
              }
            },
            style: GoogleFonts.inter(
                color: textColor, fontWeight: FontWeight.w600, fontSize: 15),
            cursorColor: _accentColor,
            decoration: InputDecoration(
                hintText: hint,
                hintStyle:
                    TextStyle(color: hintColor, fontWeight: FontWeight.normal),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero),
          )),
          const SizedBox(width: 5),
          if (isTyping)
            GestureDetector(
              onTap: () {
                AppHaptics.lightImpact();
                controller.clear();
                onChanged("");
              },
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(Icons.close_rounded,
                    color: isDark ? Colors.white38 : Colors.black38, size: 22),
              ),
            )
          else
            UniversalMicButton(
              isDark: isDark,
              activeColor: _accentColor,
              onTextRecognized: (text) {
                controller.text = text;
                onChanged(text);
                setState(() {});
              },
            ),
        ],
      ),
    );
  }
}
