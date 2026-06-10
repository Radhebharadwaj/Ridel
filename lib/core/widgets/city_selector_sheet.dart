import 'dart:async';


import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';
import 'package:ridel/core/services/global_location_service.dart';

import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/features/profile/services/profile_repository.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';
import 'package:ridel/core/utils/location_guard.dart';

class CitySelectorSheet extends StatefulWidget {
  const CitySelectorSheet({super.key});

  static void show(BuildContext context) {
    unawaited(
      RidelSheet.show(
        context,
        title: 'Select Region',
        showCloseButton: true,
        child: const CitySelectorSheet(),
      ),
    );
  }

  @override
  State<CitySelectorSheet> createState() => _CitySelectorSheetState();
}

class _CitySelectorSheetState extends State<CitySelectorSheet> {
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
  List<dynamic> _masterRegions = [];
  List<dynamic> _searchResults = [];

  // Pixra API removed to rely entirely on internal configuration.
  // 🚀 THE MAGIC FIX: OFFLINE FALLBACK DATA
  // Agar API fail hui (Web CORS ya No Internet), toh ye backup data automatically load ho jayega!
  final List<Map<String, dynamic>> _fallbackRegions = [
    {
      "region_id": "delhi",
      "display_name": "Delhi NCR",
      "covered_cities": [
        "delhi",
        "new delhi",
        "noida",
        "gurugram",
        "gurgaon",
        "faridabad",
        "ghaziabad",
        "greater noida"
      ]
    }
    // Future me yahan Mumbai, Bangalore waghera add kar sakte hain
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_fetchActiveRegions());
  }

  Future<void> _fetchActiveRegions() async {
    // 🚀 Using local regions directly, Pixra API call removed to prevent CORS/303 errors
    _masterRegions = _fallbackRegions;
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _searchCityLive('');
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _searchCityLive(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = _masterRegions.map((r) {
          final map = Map<String, dynamic>.from(r as Map);
          map['type'] = 'region';
          return map;
        }).toList();
      });
      return;
    }

    final q = query.toLowerCase();
    final List<dynamic> flatResults = [];

    for (final region in _masterRegions) {
      final regionMap = region as Map<String, dynamic>? ?? {};
      final regionName = regionMap['display_name']?.toString() ?? '';

      if (regionName.toLowerCase().contains(q)) {
        final map = Map<String, dynamic>.from(regionMap);
        map['type'] = 'region';
        flatResults.add(map);
      }

      final coveredCities = regionMap['covered_cities'] as List? ?? [];
      for (final city in coveredCities) {
        final cityString = city.toString();
        if (cityString.toLowerCase().contains(q)) {
          flatResults.add({
            'type': 'sub_city',
            'city_name': cityString,
            'region_id': regionMap['region_id'],
            'region_name': regionName,
          });
        }
      }
    }

    setState(() {
      _searchResults = flatResults;
    });
  }

  Future<void> _handleGpsSelection() async {
    bool hasLocation = await LocationGuard.checkAndRequestLocation(context);
    if (!hasLocation || !mounted) return;

    final previousCityState = ProfileRepository.userCity.value;
    ProfileRepository.userCity.value = 'Locating...';

    final locationService =
        Provider.of<GlobalLocationService>(context, listen: false);

    // Always trigger location fetch so it can handle settings popup and IP fallback
    await locationService.initializeEcoLocation(isManualTrigger: true);

    final position = locationService.currentPosition;

    if (position != null) {
      // 🚀 FIX 1: "Fake GPS" wala block hamesha ke liye hata diya gaya hai!
      // Ab Web ka IP fallback bhi perfectly allow hoga.

      final detectedCity = locationService.currentCityName.value;

      if (detectedCity.isNotEmpty && detectedCity != "Locating..." && detectedCity != "Detecting...") {
        final detectedLower = detectedCity.toLowerCase().trim();
        dynamic matchedRegion;

        // 🚀 FIX 2: UI Par Hamesha User Ki Asli City Dikhao
        String displayCity = detectedCity[0].toUpperCase() +
            detectedCity.substring(1).toLowerCase();
        ProfileRepository.userCity.value = displayCity;

        // Ab Database match check karo
        for (final region in _masterRegions) {
          final coveredCities = region['covered_cities'] as List;
          bool isMatch = coveredCities.any((c) {
            String dbCity = c.toString().toLowerCase().trim();
            return detectedLower.contains(dbCity) ||
                dbCity.contains(detectedLower);
          });

          if (isMatch) {
            matchedRegion = region;
            break;
          }
        }

        if (matchedRegion != null) {
          // ✅ Data Available Hai: Database switch karo aur sheet band karo
          await DatabaseHelper.instance.switchCity(matchedRegion['region_id']);
          AppHaptics.success();
          if (mounted) {
            ToastService.showSuccess(context, "Region detected successfully!");
            Navigator.pop(context);
          }
        } else {
          // ❌ Data Available Nahi Hai: Pyar se Sorry bolo!
          AppHaptics.heavyImpact();
          if (mounted) {
            // Sheet ko band karo aur polite dialog dikhao
            Navigator.pop(context);
            showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1E2129),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      title: Text('Coming Soon to $displayCity 🚀',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      content: Text(
                        "We haven't mapped $displayCity yet, but we're expanding our ecosystem fast! Check our roadmap to see when we'll be live in your city.",
                        style:
                            const TextStyle(color: Colors.white70, height: 1.5),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Okay',
                              style: TextStyle(color: Colors.grey)),
                        ),
                        TextButton(
                          onPressed: () {
                            // 🚀 Yahan aap apne website ke roadmap page ka link daal sakte hain
                            Navigator.pop(ctx);
                            if (mounted) {
                              ToastService.showSuccess(
                                  context, "Opening Roadmap...");
                            }
                          },
                          child: const Text('Check Roadmap',
                              style: TextStyle(
                                  color: Color(0xFF00E5FF),
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ));
          }
        }
      } else {
        ProfileRepository.userCity.value = previousCityState;
        if (mounted) {
          ToastService.showError(
              context, 'Could not fetch city name from coordinates.');
        }
        AppHaptics.error();
      }
    } else {
      ProfileRepository.userCity.value = previousCityState;
      if (mounted) {
        ToastService.showError(
            context, 'Location Denied. Please select manually.');
      }
      AppHaptics.error();
    }
  }

  dynamic
      _selectedRegion; // 🚀 PHASE 7: Tracking selected region for sub-cities

  void _onRegionSelected(dynamic region) {
    AppHaptics.selectionClick();

    final coveredCities = region['covered_cities'] as List?;
    if (coveredCities != null && coveredCities.isNotEmpty) {
      setState(() {
        _selectedRegion = region;
      });
    } else {
      // Fallback if no sub-cities are defined
      _finalizeCitySelection(region['display_name']?.toString() ?? '',
          region['region_id']?.toString() ?? '');
    }
  }

  void _onSubCitySelected(String subCity) {
    AppHaptics.selectionClick();

    // Capitalize properly: "new delhi" -> "New Delhi"
    String displayCity = subCity
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '')
        .join(' ');

    _finalizeCitySelection(
        displayCity, _selectedRegion['region_id']?.toString() ?? '');
  }

  Future<void> _finalizeCitySelection(
      String displayCity, String regionId) async {
    ProfileRepository.userCity.value = displayCity;
    await DatabaseHelper.instance.switchCity(regionId);

    if (mounted) {
      final locService =
          Provider.of<GlobalLocationService>(context, listen: false);
      locService.setMockLocationForCity(displayCity);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    const accentColor = Color(0xFF00E5FF);

    return Padding(
      padding: const EdgeInsets.only(top: 90, left: 24, right: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🚀 SHOW BACK BUTTON IF REGION SELECTED
          if (_selectedRegion != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    AppHaptics.lightImpact();
                    setState(() => _selectedRegion = null);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12.0, horizontal: 8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_ios_new_rounded,
                            color: isDark ? Colors.white70 : Colors.black87,
                            size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Back to Regions',
                          style: GoogleFonts.inter(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.w600,
                              fontSize: 15),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),

          if (_selectedRegion == null) ...[
            Container(
              height: 52,
              padding: const EdgeInsets.only(left: 16, right: 8),
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
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _searchCityLive,
                      style: GoogleFonts.inter(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      cursorColor: accentColor,
                      decoration: InputDecoration(
                        hintText: 'Search city (e.g., Noida)...',
                        hintStyle: GoogleFonts.inter(
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        AppHaptics.lightImpact();
                        _searchCtrl.clear();
                        _searchCityLive('');
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          color: isDark ? Colors.white54 : Colors.black54,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleGpsSelection,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.my_location_rounded,
                          color: accentColor, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Auto-detect my region',
                        style: GoogleFonts.inter(
                          color: accentColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
          Text(
            _selectedRegion != null
                ? 'SELECT YOUR CITY IN ${_selectedRegion['display_name'].toString().toUpperCase()}'
                : _searchCtrl.text.isEmpty
                    ? 'AVAILABLE REGIONS'
                    : 'SEARCH RESULTS',
            style: GoogleFonts.inter(
              color: isDark ? Colors.white54 : Colors.black54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: accentColor),
                  )
                : (_selectedRegion == null && _searchResults.isEmpty)
                    ? Center(
                        child: Text(
                          'City not available yet',
                          style: GoogleFonts.inter(
                              color: isDark ? Colors.white54 : Colors.black54,
                              fontSize: 14),
                        ),
                      )
                    : ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context)
                            .copyWith(scrollbars: false),
                        child: ListView.builder(
                          itemExtent: 72.0,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _selectedRegion != null
                              ? (_selectedRegion['covered_cities'] as List)
                                  .length
                              : _searchResults.length,
                          itemBuilder: (context, index) {
                            // 🚀 SUB-CITY LISTING
                            if (_selectedRegion != null) {
                              final subCity = (_selectedRegion['covered_cities']
                                  as List)[index] as String;
                              String displaySubCity = subCity
                                  .split(' ')
                                  .map((word) => word.isNotEmpty
                                      ? '${word[0].toUpperCase()}${word.substring(1)}'
                                      : '')
                                  .join(' ');

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _onSubCitySelected(subCity),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14, horizontal: 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.place_rounded,
                                          color: isDark
                                              ? Colors.white24
                                              : Colors.black26,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Text(
                                            displaySubCity,
                                            style: GoogleFonts.inter(
                                              color: textColor,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }

                            final item = _searchResults[index];
                            final bool isSubCity =
                                item is Map && item['type'] == 'sub_city';

                            if (isSubCity) {
                              final subCityName = item['city_name'] as String;
                              final displaySubCity = subCityName
                                  .split(' ')
                                  .map((word) => word.isNotEmpty
                                      ? '${word[0].toUpperCase()}${word.substring(1)}'
                                      : '')
                                  .join(' ');

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    AppHaptics.selectionClick();
                                    _finalizeCitySelection(displaySubCity,
                                        item['region_id'].toString());
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14, horizontal: 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.location_on_rounded,
                                          color: isDark
                                              ? Colors.white24
                                              : Colors.black26,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                displaySubCity,
                                                style: GoogleFonts.inter(
                                                  color: textColor,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                "In ${item['region_name']}",
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  color: isDark
                                                      ? Colors.white54
                                                      : Colors.black54,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }

                            // 🚀 MASTER REGION LISTING
                            final region = item;
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _onRegionSelected(region),
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14, horizontal: 8),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.location_city_rounded,
                                        color: isDark
                                            ? Colors.white24
                                            : Colors.black26,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              region['display_name'] as String,
                                              style: GoogleFonts.inter(
                                                color: textColor,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              "Covers: ${(region['covered_cities'] as List).take(3).join(', ')}...",
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color: isDark
                                                    ? Colors.white54
                                                    : Colors.black54,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: isDark
                                            ? Colors.white24
                                            : Colors.black26,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
