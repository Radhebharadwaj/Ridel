import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/providers/app_navigation_provider.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/universal_mic_button.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ridel/core/utils/ridel_bounce_button.dart';

class NearestStationSheetContent extends StatefulWidget {
  final bool isBus;
  const NearestStationSheetContent({super.key, required this.isBus});

  @override
  State<NearestStationSheetContent> createState() =>
      _NearestStationSheetContentState();
}

class _NearestStationSheetContentState
    extends State<NearestStationSheetContent> {
  bool _isLoading = true;
  String? _errorMessage;
  String _errorType = 'unknown';

  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _allLocationsCache = [];
  List<Map<String, dynamic>> _displayLocations = [];
  Map<String, dynamic>? _selectedLocation;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateNearestLocationsOffline();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  Future<void> _calculateNearestLocationsOffline() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          ToastService.showError(context, "Location Permission Required!");
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorType = 'location';
              _errorMessage = "Please allow location permissions.";
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorType = 'location';
            _errorMessage =
                "Permissions permanently denied. Enable in settings.";
          });
        }
        return;
      }

      if (!mounted) return;
      final locService =
          Provider.of<GlobalLocationService>(context, listen: false);
      Position? pos = locService.currentPosition;

      if (pos == null) {
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(accuracy: LocationAccuracy.high),
          ).timeout(const Duration(seconds: 5));
        } catch (e) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorType = 'location';
              _errorMessage = "Unable to fetch coordinates. Turn ON GPS.";
            });
          }
          return;
        }
      }

      List<Map<String, dynamic>> allLocations = [];
      try {
        if (widget.isBus) {
          allLocations = await DatabaseHelper.instance
              .getAllBusStops()
              .timeout(const Duration(seconds: 8));
        } else {
          allLocations = await DatabaseHelper.instance
              .getAllStations()
              .timeout(const Duration(seconds: 8));
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorType = 'database';
            String transportName =
                widget.isBus ? "Bus database" : "Metro database";
            _errorMessage = "$transportName is still downloading. Tap Retry.";
          });
        }
        return;
      }

      if (allLocations.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorType = 'database';
            _errorMessage = "Database is missing. Please restart app.";
          });
        }
        return;
      }

      List<Map<String, dynamic>> calculatedList = [];
      for (var rawLoc in allLocations) {
        double lat = double.tryParse(rawLoc['lat'].toString()) ?? 0.0;
        double lng =
            double.tryParse((rawLoc['lon'] ?? rawLoc['lng']).toString()) ?? 0.0;
        String name = (rawLoc['stop_name'] ?? rawLoc['name']).toString();
        String id = (rawLoc['stop_id'] ?? rawLoc['id']).toString();

        if (lat == 0.0 || lng == 0.0) continue;

        double distanceInMeters =
            Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
        calculatedList.add({
          'location': {'id': id, 'name': name, 'lat': lat, 'lng': lng},
          'distance': distanceInMeters
        });
      }

      calculatedList.sort((a, b) =>
          (a['distance'] as double).compareTo(b['distance'] as double));

      _allLocationsCache = calculatedList;
      _filterTopLocations();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorType = 'unknown';
          _errorMessage = "Something went wrong. Please try again.";
        });
      }
    }
  }

  void _filterTopLocations({String query = ""}) {
    List<Map<String, dynamic>> uniqueLocations = [];
    Set<String> seenNames = {};

    for (var item in _allLocationsCache) {
      String rawName = item['location']['name'].toString();

      if (query.isNotEmpty &&
          !rawName.toLowerCase().contains(query.toLowerCase())) {
        continue;
      }

      String cleanName =
          rawName.toLowerCase().replaceAll(RegExp(r'\s*[\(\-\,].*'), '').trim();

      if (!seenNames.contains(cleanName)) {
        seenNames.add(cleanName);
        uniqueLocations.add(item);
      }

      if (uniqueLocations.length >= (query.isEmpty ? 5 : 15)) break;
    }

    if (mounted) {
      setState(() {
        _displayLocations = uniqueLocations;
        if (_displayLocations.isNotEmpty && !_isSearching) {
          _selectedLocation = _displayLocations[0]['location'];
        }
        _errorMessage = null;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String val) {
    setState(() {
      _isSearching = val.isNotEmpty;
    });
    _filterTopLocations(query: val.trim());
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return "${meters.toInt()}m";
    return "${(meters / 1000).toStringAsFixed(1)}km";
  }

  Future<void> _openExternalMap() async {
    if (_selectedLocation == null) return;
    AppHaptics.mediumImpact();

    if (!mounted) return;
    final locService =
        Provider.of<GlobalLocationService>(context, listen: false);
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    final pos = locService.currentPosition;

    if (pos == null) {
      ToastService.showError(context, "Unable to fetch current location.");
      return;
    }

    final double destLat = _selectedLocation!['lat'];
    final double destLng = _selectedLocation!['lng'];
    final String destName = _selectedLocation!['name'];

    double distanceInMeters = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, destLat, destLng);
    String googleMode = distanceInMeters <= 300 ? 'walking' : 'driving';
    String appleMode = distanceInMeters <= 300 ? 'w' : 'd';

    final Uri googleUrl = Uri.parse(
        "https://www.google.com/maps/dir/?api=1&origin=${pos.latitude},${pos.longitude}&destination=$destLat,$destLng&travelmode=$googleMode");
    final Uri appleUrl = Uri.parse(
        "http://maps.apple.com/?saddr=${pos.latitude},${pos.longitude}&daddr=$destLat,$destLng&dirflg=$appleMode");

    if (await canLaunchUrl(googleUrl)) {
      await launchUrl(googleUrl, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(appleUrl)) {
      await launchUrl(appleUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ToastService.showError(context, "No compatible map application found.");
      }
    }

    await mapProvider.startStationNavigation(
        LatLng(pos.latitude, pos.longitude),
        LatLng(destLat, destLng),
        destName);

    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _openRidelMap() async {
    if (_selectedLocation == null) return;
    AppHaptics.heavyImpact();

    if (!mounted) return;
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    final navProvider =
        Provider.of<AppNavigationProvider>(context, listen: false);
    final locService =
        Provider.of<GlobalLocationService>(context, listen: false);

    Navigator.pop(context);

    final pos = locService.currentPosition;
    if (pos != null) {
      final currentLoc = LatLng(pos.latitude, pos.longitude);
      final stationLatLng =
          LatLng(_selectedLocation!['lat'], _selectedLocation!['lng']);
      await mapProvider.startStationNavigation(
          currentLoc, stationLatLng, _selectedLocation!['name']);
    }
    navProvider.setTab(1); // Assuming 1 is the map tab
  }

  IconData _getErrorIcon() {
    switch (_errorType) {
      case 'location':
        return Icons.location_off_rounded;
      case 'database':
        return Icons.cloud_sync_rounded;
      default:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final accentColor =
        widget.isBus ? const Color(0xFFFF9F0A) : const Color(0xFF00E5FF);
    final typeName = widget.isBus ? "Stop" : "Station";

    return Padding(
      // 🚀 FIX: Clear the RidelSheet glass header with top padding of 95
      padding: const EdgeInsets.only(top: 95),
      child: Column(
        children: [
          // 🚀 SEARCH BAR
          Container(
            margin:
                const EdgeInsets.only(top: 0, left: 20, right: 20, bottom: 12),
            height: 48,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2129) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.05),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 12),
                    child:
                        Icon(Icons.search_rounded, size: 18, color: accentColor),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: accentColor,
                    decoration: InputDecoration(
                      hintText: "Search specific $typeName...",
                      hintStyle: GoogleFonts.inter(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchCtrl.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            AppHaptics.lightImpact();
                            _searchCtrl.clear();
                            _onSearchChanged('');
                            FocusScope.of(context).unfocus();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            child: Icon(Icons.close_rounded,
                                color: isDark ? Colors.white54 : Colors.black54,
                                size: 18),
                          ),
                        )
                      else
                        UniversalMicButton(
                          isDark: isDark,
                          activeColor: accentColor,
                          onTextRecognized: (text) {
                            _searchCtrl.text = text;
                            _onSearchChanged(text);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 🚀 SUBTITLE TEXT
          if (!_isSearching)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text("Based on your GPS location",
                  style: GoogleFonts.inter(
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
            ),

          if (_errorMessage != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_getErrorIcon(), color: Colors.redAccent, size: 54),
                      const SizedBox(height: 20),
                      Text(_errorMessage!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                              color: textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.5)),
                      const SizedBox(height: 28),
                      ElevatedButton.icon(
                          onPressed: () {
                            AppHaptics.mediumImpact();
                            setState(() {
                              _isLoading = true;
                              _errorMessage = null;
                            });
                            _calculateNearestLocationsOffline();
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  accentColor.withValues(alpha: 0.15),
                              foregroundColor: accentColor,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(100)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 14)),
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          label: Text("Retry",
                              style: GoogleFonts.inter(
                                  fontSize: 15, fontWeight: FontWeight.w700)))
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CupertinoActivityIndicator(
                          radius: 14, color: accentColor))
                  : _displayLocations.isEmpty
                      ? Center(
                          child: Text("No $typeName found",
                              style: GoogleFonts.inter(
                                  color: Colors.grey, fontSize: 15)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(
                              top: 8, bottom: 20, left: 20, right: 20),
                          physics: const BouncingScrollPhysics(),
                          itemCount: _displayLocations.length,
                          itemBuilder: (context, index) {
                            final data = _displayLocations[index];
                            return _buildNotificationStylePill(
                                location: data['location'],
                                distance: _formatDistance(data['distance']),
                                isSelected: _selectedLocation?['id'] ==
                                    data['location']['id'],
                                isDark: isDark,
                                accentColor: accentColor);
                          },
                        ),
            ),

          if (!_isLoading &&
              _errorMessage == null &&
              _displayLocations.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 10, 20, MediaQuery.of(context).padding.bottom + 20),
              child: Row(
                children: [
                  Expanded(
                      child: _buildGlassyButton(
                          title: "Ridel Map",
                          icon: Icons.map_rounded,
                          isDark: isDark,
                          isPrimary: true,
                          accentColor: accentColor,
                          onTap: _openRidelMap)),
                  const SizedBox(width: 14),
                  Expanded(
                      child: _buildGlassyButton(
                          title: "Device Map",
                          icon: CupertinoIcons.compass,
                          isDark: isDark,
                          isPrimary: false,
                          accentColor: accentColor,
                          onTap: _openExternalMap)),
                ],
              ),
            )
        ],
      ),
    );
  }

  // 🚀 NOTIFICATION-STYLE EXPANDABLE PILL (Like image_eccbea.png)
  Widget _buildNotificationStylePill(
      {required Map<String, dynamic> location,
      required String distance,
      required bool isSelected,
      required bool isDark,
      required Color accentColor}) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black54;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      // 🚀 Added RidelBounceButton for premium feel
      child: RidelBounceButton(
        scaleFactor: 0.98,
        onTap: () {
          setState(() => _selectedLocation = location);
          FocusScope.of(context).unfocus(); // Dismiss keyboard
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          // Similar padding as Notification Sheet
          padding:
              const EdgeInsets.only(left: 8, right: 16, top: 12, bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2129) : Colors.white,
            // 🚀 Perfect Pill Shape
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              // Selected par Accent Glow border, varna matte border
              color: isSelected
                  ? accentColor.withValues(alpha: 0.5)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.05)),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                // Selected hone par colored glow, varna soft shadow
                color: isSelected
                    ? accentColor.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: isSelected ? 20 : 12,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Row(
              children: [
                // 🚀 ICON CONTAINER
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF121419)
                        : accentColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.transparent,
                    ),
                  ),
                  child: Icon(
                      widget.isBus
                          ? Icons.directions_bus_rounded
                          : Icons.train_rounded,
                      color: isSelected
                          ? accentColor // Selected par pura color
                          : (isDark
                              ? Colors.white70
                              : Colors.black87), // Not selected par neutral
                      size: 18),
                ),
                const SizedBox(width: 12),

                // 🚀 TEXT CONTENT
                Row(
                  children: [
                    // Dot indicator if selected
                    if (isSelected) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.5),
                              blurRadius: 6,
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _toTitleCase(location['name']),
                      style: GoogleFonts.inter(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
                const SizedBox(width: 8),

                // 🚀 DISTANCE TEXT
                Text(
                  distance,
                  style: GoogleFonts.inter(
                    color: subColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassyButton(
      {required String title,
      required IconData icon,
      required bool isDark,
      required bool isPrimary,
      required Color accentColor,
      required VoidCallback onTap}) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return RidelBounceButton(
      scaleFactor: 0.95,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 56,
        decoration: BoxDecoration(
            color: isPrimary
                ? accentColor.withValues(alpha: 0.15)
                : (isDark ? const Color(0xFF1E2129) : const Color(0xFFF2F2F7)),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
                color: isPrimary
                    ? accentColor.withValues(alpha: 0.5)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.05)),
                width: 1.0),
            boxShadow: [
              if (isPrimary)
                BoxShadow(
                    color: accentColor.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
            ]),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: isPrimary ? accentColor : textColor, size: 20),
          const SizedBox(width: 8),
          Flexible(
              child: Text(title,
                  style: GoogleFonts.inter(
                      color: isPrimary
                          ? (isDark ? Colors.white : Colors.black87)
                          : textColor,
                      fontSize: 15,
                      letterSpacing: -0.2,
                      fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}
