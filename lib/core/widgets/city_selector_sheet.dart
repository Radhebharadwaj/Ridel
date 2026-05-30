import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/place_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/features/profile/services/profile_repository.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';

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

  final String _configApiUrl = 'https://pixra.pages.dev/api/config/cities';

  // 🚀 THE MAGIC FIX: OFFLINE FALLBACK DATA
  // Agar API fail hui (Web CORS ya No Internet), toh ye backup data automatically load ho jayega!
  final List<Map<String, dynamic>> _fallbackRegions = [
    {
      "region_id": "delhi",
      "display_name": "Delhi NCR",
      "covered_cities": ["delhi", "new delhi", "noida", "gurugram", "gurgaon", "faridabad", "ghaziabad", "greater noida"]
    }
    // Future me yahan Mumbai, Bangalore waghera add kar sakte hain
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_fetchActiveRegions());
  }

  Future<void> _fetchActiveRegions() async {
    try {
      // 🚀 5 second ka timeout diya hai, taaki app atke nahi
      final response = await http.get(Uri.parse(_configApiUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _masterRegions = data['regions'] as List<dynamic>;
      } else {
        // API failed (500, 404), use fallback
        _masterRegions = _fallbackRegions;
      }
    } catch (e) {
      debugPrint('API Error/CORS failed, using Offline Fallback: $e');
      // 🚀 Network Error (CORS on Web), use fallback
      _masterRegions = _fallbackRegions;
    } finally {
      if (mounted) {
        setState(() {
          _searchResults = List.from(_masterRegions);
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _searchCityLive(String query) {
    if (query.isEmpty) {
      setState(() => _searchResults = List.from(_masterRegions));
      return;
    }

    final q = query.toLowerCase();
    setState(() {
      _searchResults = _masterRegions.where((region) {
        final matchesName =
            region['display_name'].toString().toLowerCase().contains(q);
        final matchesSubCity = (region['covered_cities'] as List)
            .any((city) => city.toString().toLowerCase().contains(q));
        return matchesName || matchesSubCity;
      }).toList();
    });
  }

  Future<void> _handleGpsSelection() async {
    final previousCityState = ProfileRepository.userCity.value; 
    ProfileRepository.userCity.value = 'Locating...';

    final locationService = Provider.of<GlobalLocationService>(context, listen: false);
    
    if (!locationService.hasValidLocation) {
      await locationService.initializeEcoLocation();
    }

    final position = locationService.currentPosition;

    if (position != null) {
      // 🚀 FIX 1: "Fake GPS" wala block hamesha ke liye hata diya gaya hai!
      // Ab Web ka IP fallback bhi perfectly allow hoga.

      final detectedCity = await PlaceService.getCityFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (detectedCity != null) {
        final detectedLower = detectedCity.toLowerCase().trim();
        dynamic matchedRegion;

        // 🚀 FIX 2: UI Par Hamesha User Ki Asli City Dikhao
        String displayCity = detectedCity[0].toUpperCase() + detectedCity.substring(1).toLowerCase();
        ProfileRepository.userCity.value = displayCity; 

        // Ab Database match check karo
        for (final region in _masterRegions) {
          final coveredCities = region['covered_cities'] as List;
          bool isMatch = coveredCities.any((c) {
            String dbCity = c.toString().toLowerCase().trim();
            return detectedLower.contains(dbCity) || dbCity.contains(detectedLower);
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
          if (mounted) Navigator.pop(context); 
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                title: Text(
                  'Coming Soon to $displayCity 🚀', 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                ),
                content: Text(
                  "We haven't mapped $displayCity yet, but we're expanding our ecosystem fast! Check our roadmap to see when we'll be live in your city.",
                  style: const TextStyle(color: Colors.white70, height: 1.5),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Okay', style: TextStyle(color: Colors.grey)),
                  ),
                  TextButton(
                    onPressed: () {
                       // 🚀 Yahan aap apne website ke roadmap page ka link daal sakte hain
                       Navigator.pop(ctx);
                       if (mounted) {
                         ToastService.showSuccess(context, "Opening Roadmap...");
                       }
                    },
                    child: const Text('Check Roadmap', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            );
          }
        }
      } else {
        ProfileRepository.userCity.value = previousCityState;
        if (mounted) {
          ToastService.showError(context, 'Could not fetch city name from coordinates.');
        }
        AppHaptics.error();
      }
    } else {
      ProfileRepository.userCity.value = previousCityState;
      if (mounted) {
        ToastService.showError(context, 'Location Denied. Please select manually.');
      }
      AppHaptics.error();
    }
  }

  void _onRegionSelected(dynamic region) async {
    AppHaptics.selectionClick();
    
    ProfileRepository.userCity.value = region['display_name']?.toString() ?? '';
    
    await DatabaseHelper.instance.switchCity(region['region_id']?.toString() ?? '');
    
    if (mounted) Navigator.pop(context);
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
            onTap: () {
              AppHaptics.heavyImpact();
              unawaited(_handleGpsSelection());
            },
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
                  Text(
                    'Auto-detect my region',
                    style: GoogleFonts.inter(
                      color: accentColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            _searchCtrl.text.isEmpty ? 'AVAILABLE REGIONS' : 'SEARCH RESULTS',
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
                : _searchResults.isEmpty
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
                          physics: const BouncingScrollPhysics(),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final region = _searchResults[index];
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