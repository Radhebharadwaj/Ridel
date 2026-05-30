import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/services/universal_mic_button.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';

// 🚀 IMPORTED FOR UNIFORM RIDEL DESIGN & SEARCH BAR
import 'package:ridel/core/widgets/ridel_liquid_button.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';

class StationSelectorSheet extends StatefulWidget {
  const StationSelectorSheet({
    required this.onStationSelected,
    super.key,
    this.currentFromStation,
    this.currentToStation,
    this.isSelectingSource = true,
    this.isBusMode = false,
  });
  final void Function(Map<String, dynamic> station, bool isSourceSelected)
      onStationSelected;
  final Map<String, dynamic>? currentFromStation;
  final Map<String, dynamic>? currentToStation;
  final bool isSelectingSource;
  final bool isBusMode;

  @override
  State<StationSelectorSheet> createState() => _StationSelectorSheetState();
}

class _StationSelectorSheetState extends State<StationSelectorSheet> {
  late Future<List<Map<String, dynamic>>> _dataFuture;

  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _allMasterStations = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  List<String>? _selectedLineIds;
  Color? _selectedLineColor;
  List<Map<String, dynamic>> _stations = [];

  List<Map<String, dynamic>> _nearbyStops = [];
  bool _isLoadingStations = false;
  late bool _isCurrentlySelectingSource;
  bool _showNearbyStops = true;
  double _lastHapticOffset = 0.0;

  // 🚀 Premium Title Case Formatter
  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  String get _locationTerm => widget.isBusMode ? 'Stop' : 'Station';

  @override
  void initState() {
    super.initState();
    _isCurrentlySelectingSource = widget.isSelectingSource;
    _loadData();
    if (widget.isBusMode) unawaited(_fetchNearbyStops());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (widget.isBusMode) {
      _dataFuture = DatabaseHelper().getStationsByMode(1);
    } else {
      _dataFuture = DatabaseHelper().getAllLines();
    }

    final rawStations =
        await DatabaseHelper().getStationsByMode(widget.isBusMode ? 1 : 0);

    // 🚀 DEDUPLICATION LOGIC: Same Bus Stop ya Station ke duplicates remove
    Set<String> seenNames = {};
    List<Map<String, dynamic>> uniqueStations = [];

    for (var s in rawStations) {
      String rawName = s['stop_name'].toString();
      // Remove generic tags like (Up), (Down), - Terminal, etc.
      String cleanName =
          rawName.toLowerCase().replaceAll(RegExp(r'\s*[\(\-\,].*'), '').trim();

      if (!seenNames.contains(cleanName)) {
        seenNames.add(cleanName);
        uniqueStations.add(s);
      }
    }
    _allMasterStations = uniqueStations;
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    final lowerQuery = query.toLowerCase();
    final results = _allMasterStations.where((s) {
      return s['stop_name'].toString().toLowerCase().contains(lowerQuery);
    }).toList();

    setState(() {
      _isSearching = true;
      _searchResults = results;
    });
  }

  Future<void> _fetchNearbyStops() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition();
        final allStops = await DatabaseHelper().getStationsByMode(1);

        final nearby = allStops.where((s) {
          final dist = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            s['lat'] is num ? (s['lat'] as num).toDouble() : double.tryParse(s['lat']?.toString() ?? '0.0') ?? 0.0,
            s['lon'] is num ? (s['lon'] as num).toDouble() : double.tryParse(s['lon']?.toString() ?? '0.0') ?? 0.0,
          );
          return dist < 2000;
        }).toList();

        nearby.sort((a, b) {
          final distA = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            a['lat'] is num ? (a['lat'] as num).toDouble() : double.tryParse(a['lat']?.toString() ?? '0.0') ?? 0.0,
            a['lon'] is num ? (a['lon'] as num).toDouble() : double.tryParse(a['lon']?.toString() ?? '0.0') ?? 0.0,
          );
          final distB = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            b['lat'] is num ? (b['lat'] as num).toDouble() : double.tryParse(b['lat']?.toString() ?? '0.0') ?? 0.0,
            b['lon'] is num ? (b['lon'] as num).toDouble() : double.tryParse(b['lon']?.toString() ?? '0.0') ?? 0.0,
          );
          return distA.compareTo(distB);
        });

        // 🚀 DEDUPLICATION FOR NEARBY STOPS
        Set<String> seenNearbyNames = {};
        List<Map<String, dynamic>> uniqueNearby = [];
        for (var s in nearby) {
          String rawName = s['stop_name'].toString();
          String cleanName = rawName
              .toLowerCase()
              .replaceAll(RegExp(r'\s*[\(\-\,].*'), '')
              .trim();
          if (!seenNearbyNames.contains(cleanName)) {
            seenNearbyNames.add(cleanName);
            uniqueNearby.add(s);
          }
        }

        if (mounted) {
          // 🚀 FIX: Added curly braces here
          setState(() => _nearbyStops = uniqueNearby.take(10).toList());
        }
      }
    } catch (e) {
      debugPrint('Location Error: $e');
    }
  }

  Future<void> _onLineSelected(List<String> lineIds, Color lineColor) async {
    AppHaptics.selectionClick();
    setState(() {
      _selectedLineIds = lineIds;
      _selectedLineColor = lineColor;
      _isLoadingStations = true;
      _stations = [];
    });

    if (!widget.isBusMode) {
      final stations = await DatabaseHelper().getStationsByLineIds(lineIds);
      if (mounted) {
        setState(() {
          _stations = stations;
          _isLoadingStations = false;
        });
      }
    }
  }

  void _onStationTap(Map<String, dynamic> station) {
    AppHaptics.heavyImpact();

    final otherStation = _isCurrentlySelectingSource
        ? widget.currentToStation
        : widget.currentFromStation;
    if (otherStation != null &&
        otherStation['stop_name'] == station['stop_name']) {
      ToastService.showInfo(context, 'Source & Destination cannot be same');
      return;
    }

    final updatedStation = Map<String, dynamic>.from(station);
    if (_selectedLineColor != null) {
      updatedStation['line_color'] = _selectedLineColor;
    }

    widget.onStationSelected(updatedStation, _isCurrentlySelectingSource);

    final isDestinationEmpty = widget.currentToStation == null;

    if (_isCurrentlySelectingSource && isDestinationEmpty) {
      ToastService.showSuccess(context, 'Now Select Destination');
      setState(() {
        _isCurrentlySelectingSource = false;
        _selectedLineIds = null;
        _stations = [];
        _searchCtrl.clear();
        _isSearching = false;
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey : Colors.grey.shade700;

    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: Colors.transparent,
            child: _isSearching
                ? _buildStationsView(textColor, bgColor, _searchResults)
                : (widget.isBusMode
                    ? _buildBusContent(textColor, bgColor)
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _selectedLineIds == null
                            ? _buildLinesView(textColor, subTextColor)
                            : _buildStationsView(textColor, bgColor, _stations),
                      )),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 110,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  bgColor,
                  bgColor.withValues(alpha: 0.95),
                  bgColor.withValues(alpha: 0),
                ],
                stops: const [0.0, 0.65, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTransparentHeader(isDark),
        ),
        if (widget.isBusMode && !_isSearching)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 120,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    bgColor,
                    bgColor.withValues(alpha: 0.9),
                    bgColor.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        if (widget.isBusMode && !_isSearching)
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: _buildFloatingToggle(isDark),
          ),
      ],
    );
  }

  // 🚀 COMPLETELY OVERHAULED TO MATCH RIDEL SHEET HEADER
  Widget _buildTransparentHeader(bool isDark) {
    final title = _isCurrentlySelectingSource
        ? 'Search Start $_locationTerm...'
        : 'Search Destination...';

    final glassBtnColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final btnIconColor = isDark ? Colors.white : Colors.black87;
    final accentColor = _isCurrentlySelectingSource
        ? const Color(0xFF00E5FF)
        : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      color: Colors.transparent,
      child: Row(
        children: [
          // 🚀 EXACT MATCH: RidelSheet's Back Button (Liquid Component)
          SizedBox(
            width: 44,
            height: 44,
            child: RidelLiquidButton(
              width: 44,
              height: 44,
              shapeType: LiquidShapeType.circle,
              glassTint: glassBtnColor,
              onTap: () {
                AppHaptics.lightImpact();
                if (_isSearching) {
                  setState(() {
                    _isSearching = false;
                    _searchCtrl.clear();
                  });
                } else if (_selectedLineIds != null) {
                  setState(() => _selectedLineIds = null);
                } else {
                  Navigator.pop(context);
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 2.0),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: btnIconColor,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 🚀 REUSABLE MASTER GLASS SEARCH BAR USED HERE
          Expanded(
            child: RidelGlassSearchBar(
              controller: _searchCtrl,
              hintText: title,
              accentColor: accentColor,
              onChanged: _onSearchChanged,
              onClear: () {
                AppHaptics.lightImpact();
                _searchCtrl.clear();
                _onSearchChanged('');
                FocusScope.of(context).unfocus();
              },
              trailing: UniversalMicButton(
                isDark: isDark,
                activeColor: accentColor,
                onTextRecognized: (text) {
                  _searchCtrl.text = text;
                  _onSearchChanged(text);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusContent(Color textColor, Color bgColor) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _showNearbyStops
          ? (_nearbyStops.isEmpty
              ? _buildEmptyLocationState()
              : _buildStationsView(
                  textColor,
                  bgColor,
                  _nearbyStops,
                  isNearby: true,
                ))
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: _dataFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF9F0A)),
                  );
                }
                return _buildStationsView(textColor, bgColor, snapshot.data!);
              },
            ),
    );
  }

  Widget _buildFloatingToggle(bool isDark) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2129) : Colors.white,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.05),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / 2;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                left: _showNearbyStops ? 0 : width,
                top: 0,
                bottom: 0,
                child: Container(
                  width: width,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F0A),
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF9F0A).withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  _buildToggleItem('Nearby Stops 📍', true, isDark),
                  _buildToggleItem('All Stops 🚏', false, isDark),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToggleItem(String text, bool isNearby, bool isDark) {
    final isSelected = _showNearbyStops == isNearby;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_showNearbyStops != isNearby) {
            AppHaptics.switchToggle();
            setState(() => _showNearbyStops = isNearby);
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: GoogleFonts.inter(
              color: isSelected
                  ? Colors.black
                  : (isDark ? Colors.white60 : Colors.black54),
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
            ),
            child: Text(text),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyLocationState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_disabled_rounded,
            color: Colors.grey.shade800,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'No nearby stops found',
            style: GoogleFonts.inter(color: Colors.grey, fontSize: 14),
          ),
          TextButton(
            onPressed: () {
              AppHaptics.mediumImpact();
              _fetchNearbyStops();
            },
            child: Text(
              'Retry Location',
              style: GoogleFonts.inter(color: const Color(0xFFFF9F0A)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinesView(Color textColor, Color subTextColor) {
    if (widget.isBusMode) return const SizedBox();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
        }

        final lines = snapshot.data!;
        if (lines.isEmpty) {
          return Center(
            child: Text('No lines found', style: TextStyle(color: textColor)),
          );
        }

        final groupedLines = <String, Map<String, dynamic>>{};
        final mergedIds = <String, List<String>>{};

        for (final line in lines) {
          var rawColor = line['route_color']?.toString() ?? '808080';
          rawColor = rawColor.replaceAll('#', '');

          if (!groupedLines.containsKey(rawColor)) {
            groupedLines[rawColor] = line;
            mergedIds[rawColor] = [];
          }
          mergedIds[rawColor]!.add(line['route_id'].toString());
        }
        final uniqueList = groupedLines.values.toList();

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ListView.builder(
            key: const ValueKey('LinesView'),
            padding: const EdgeInsets.fromLTRB(20, 100, 20, 40),
            itemCount: uniqueList.length,
            itemBuilder: (context, index) {
              final line = uniqueList[index];
              final isLast = index == uniqueList.length - 1;

              var colorHex = line['route_color']?.toString() ?? '808080';
              colorHex = colorHex.replaceAll('#', '');
              Color color;
              try {
                color = Color(int.parse('0xFF$colorHex'));
              } catch (e) {
                color = Colors.grey;
              }
              final colorKey = colorHex;

              final rawName = line['route_short_name']?.toString() ?? 'Metro';
              String displayName;
              if (rawName.contains('RMGL')) {
                displayName = 'Rapid Line';
              } else if (rawName.contains('FOB')) {
                displayName = 'Grey Line';
              } else if (rawName.contains('Orange')) {
                displayName = 'Airport Line';
              } else if (!rawName.toLowerCase().contains('line')) {
                displayName = '$rawName Line';
              } else {
                displayName = rawName;
              }

              return InkWell(
                onTap: () => _onLineSelected(mergedIds[colorKey]!, color),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 30,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (!isLast)
                              Positioned(
                                top: 25,
                                bottom: -25,
                                child: Container(
                                  width: 2,
                                  color: Colors.white12,
                                ),
                              ),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.6),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: textColor,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: Colors.white24,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStationsView(
    Color textColor,
    Color bgColor,
    List<Map<String, dynamic>> stations, {
    bool isNearby = false,
  }) {
    if (_isLoadingStations) {
      return Center(
        key: const ValueKey('Loader'),
        child: CircularProgressIndicator(
          color: _selectedLineColor ?? const Color(0xFF00E5FF),
        ),
      );
    }
    if (stations.isEmpty) {
      return Center(
        child: Text(
          'No stops found',
          style: GoogleFonts.inter(color: Colors.grey),
        ),
      );
    }

    final lineColor = _selectedLineColor ?? Colors.grey;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) {
          if ((notification.metrics.pixels - _lastHapticOffset).abs() > 40.0) {
            AppHaptics.selectionClick();
            _lastHapticOffset = notification.metrics.pixels;
          }
          return false;
        },
        child: ListView.builder(
          key: const ValueKey('StationsList'),
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          padding: EdgeInsets.only(
            top: 100,
            bottom: widget.isBusMode ? 100 : 40,
            left: 20,
            right: 20,
          ),
          itemCount: stations.length,
          itemBuilder: (context, index) {
            final isLast = index == stations.length - 1;
            final station = stations[index];
            final otherStation = _isCurrentlySelectingSource
                ? widget.currentToStation
                : widget.currentFromStation;
            final isDisabled = otherStation != null &&
                otherStation['stop_name'] == station['stop_name'];

            return InkWell(
              onTap: isDisabled ? null : () => _onStationTap(station),
              child: widget.isBusMode
                  ? _buildBusStopRow(station, isDisabled, textColor, isNearby)
                  : _buildMetroStationRow(
                      station,
                      isDisabled,
                      textColor,
                      bgColor,
                      lineColor,
                      isLast,
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBusStopRow(
    Map<String, dynamic> station,
    bool isDisabled,
    Color textColor,
    bool isNearby,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isNearby
                  ? const Color(0xFFFF9F0A).withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isNearby
                  ? Icons.my_location_rounded
                  : Icons.directions_bus_rounded,
              color: isNearby ? const Color(0xFFFF9F0A) : Colors.grey,
              size: 16,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _toTitleCase(station['stop_name']?.toString() ?? ''),
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color:
                    isDisabled ? Colors.grey.withValues(alpha: 0.5) : textColor,
                fontSize: 15,
              ),
            ),
          ),
          if (isNearby)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'NEARBY',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: const Color(0xFFFF9F0A),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetroStationRow(
    Map<String, dynamic> station,
    bool isDisabled,
    Color textColor,
    Color bgColor,
    Color lineColor,
    bool isLast,
  ) {
    const dotBgColor = Color(0xFF1C1C1E);
    final activeLineColor = _isSearching ? Colors.grey : lineColor;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!isLast)
                  Positioned(
                    top: 25,
                    bottom: -25,
                    child: Container(width: 2, color: Colors.white12),
                  ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isDisabled ? Colors.grey : dotBgColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDisabled ? Colors.grey : activeLineColor,
                      width: 2.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              child: Text(
                _toTitleCase(station['stop_name']?.toString() ?? ''),
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: isDisabled
                      ? Colors.grey.withValues(alpha: 0.5)
                      : textColor,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
