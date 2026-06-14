import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/weather_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/map/services/weather_cache_service.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';


import 'package:intl/intl.dart';

enum WeatherState { compact, expanded, full }

class _NoScrollbarBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class WeatherFloatingWidget extends StatefulWidget {
  final Function(bool isDark) onMapThemeChanged;

  const WeatherFloatingWidget({
    super.key,
    required this.onMapThemeChanged,
  });

  @override
  State<WeatherFloatingWidget> createState() => WeatherFloatingWidgetState();
}

class WeatherFloatingWidgetState extends State<WeatherFloatingWidget> {
  static const Color accentColor = Color(0xFF00E5FF);

  WeatherModel? _weather;
  WeatherState _currentState = WeatherState.compact;

  bool get isExpanded => _currentState != WeatherState.compact;

  void collapse() {
    if (mounted && _currentState != WeatherState.compact) {
      setState(() {
        _currentState = WeatherState.compact;
      });
    }
  }

  // 🚀 OPTIMIZATION: State variables to prevent infinite API loops
  bool _isExecutingFetch = false;
  bool _isInitialized = false;
  double? _lastLat;
  double? _lastLng;
  bool _isLoading = true;
  bool _hasError = false;
  bool _hasFetchedWeather = false;
  late GlobalLocationService _locService;

  // 🚀 OPTIMIZATION: Haversine distance formula to calculate distance in meters
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295; // Math.PI / 180
    final double a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a)) * 1000;
  }

  final WeatherCacheService _weatherCache = WeatherCacheService();
  final ScrollController _hourlyScrollController = ScrollController();
  
  void _scrollToNow() {
    if (_weather == null || _weather!.hourly.isEmpty) return;
    int nowIndex = 0;
    DateTime now = DateTime.now();
    for (int i = 0; i < _weather!.hourly.length; i++) {
      try {
        if (_weather!.hourly[i].time.isNotEmpty) {
          DateTime dt = DateTime.parse(_weather!.hourly[i].time);
          if (!dt.isBefore(DateTime(now.year, now.month, now.day, now.hour))) {
            nowIndex = i;
            break;
          }
        }
      } catch (_) {}
    }
    
    if (nowIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_hourlyScrollController.hasClients) {
          double offset = nowIndex * 65.0; // item width
          _hourlyScrollController.jumpTo(offset);
        }
      });
    }
  }

  double? _dragHeight;
  final double _compactHeight = 68;
  final double _compactWidth = 82;
  final double _expandedHeight = 265;
  final double _fullHeight = 550;

  @override
  void initState() {
    super.initState();
    _locService = Provider.of<GlobalLocationService>(context, listen: false);
    _locService.addListener(_onLocationUpdated);

    WeatherService.currentWeather.addListener(_onGlobalWeatherChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_locService.currentPosition != null && !_hasFetchedWeather) {
        _resolveLocationAndFetchWeather();
        _hasFetchedWeather = true;
      }
    });
  }

  void _onGlobalWeatherChanged() {
    final w = WeatherService.currentWeather.value;
    if (w != null && mounted) {
      setState(() {
        _weather = w;
        _isLoading = false;
        _hasError = false;
      });
    }
  }

  @override
  void dispose() {
    WeatherService.currentWeather.removeListener(_onGlobalWeatherChanged);
    _locService.removeListener(_onLocationUpdated);
    _hourlyScrollController.dispose();
    super.dispose();
  }

  void _onLocationUpdated() {
    if (_locService.currentPosition != null && !_hasFetchedWeather) {
      _resolveLocationAndFetchWeather();
      _hasFetchedWeather = true;
    }
  }

  Future<void> _resolveLocationAndFetchWeather() async {
    if (_isExecutingFetch) return;
    _isExecutingFetch = true;
    final locService = Provider.of<GlobalLocationService>(context, listen: false);

    double? lat;
    double? lng;
    bool isMocked = false;

    if (locService.currentPosition != null) {
      lat = locService.currentPosition!.latitude;
      lng = locService.currentPosition!.longitude;
      isMocked = locService.currentPosition!.isMocked;
    }

    if (lat == null || lng == null) {
      // Location completely unavailable; UI stays in "Locating..." loading state
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
      return;
    }

    // 🚀 OPTIMIZATION: Strict distance threshold check (3km) to prevent API spam
    if (!isMocked && _isInitialized && _lastLat != null && _lastLng != null && _weather != null) {
      final distance = _calculateDistance(_lastLat!, _lastLng!, lat, lng);
      if (distance <= 3000) return;
    }
    _isInitialized = true;

    _lastLat = lat;
    _lastLng = lng;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    try {
      WeatherModel? data;
      if (!isMocked) {
        // EXACT GPS: Smart Cache
        data = await _weatherCache.getSmartWeather(lat, lng, locService.currentCity);
      } else {
        // 🚀 PHASE 8: FALLBACK / GPS DENIED -> Fetch by City Name with coordinate failsafe
        data = await _weatherCache.getSmartWeatherByCity(locService.currentCity, lat: lat, lng: lng);
      }

      if (!mounted) return;
      setState(() {
        if (data != null) {
          _weather = data;
          _hasError = false;
          _scrollToNow();
        } else {
          _hasError = true;
        }
      });
    } catch (e) {
      debugPrint('Weather Widget Catch: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
      });
    } finally {
      _isExecutingFetch = false;
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleTap() {
    debugPrint("🟢 [WEATHER DEBUG] MAIN CARD TAPPED!");
    debugPrint("🟢 [WEATHER DEBUG] Current State: $_currentState");
    debugPrint("🟢 [WEATHER DEBUG] _hasError: $_hasError, _weather: ${_weather?.temp}");

    if (_hasError || _weather == null) {
      debugPrint("🔴 [WEATHER DEBUG] Tap blocked! (Error or Null Weather). Retrying fetch...");
      _resolveLocationAndFetchWeather(); // Retry tap
      return;
    }

    AppHaptics.sheetInteraction();
    if (mounted) {
      setState(() {
        _dragHeight = null;
        if (_currentState == WeatherState.compact) {
          _currentState = WeatherState.expanded;
          _scrollToNow();
          debugPrint("🟢 [WEATHER DEBUG] State changed to -> EXPANDED");
        } else if (_currentState == WeatherState.expanded) {
          _currentState = WeatherState.full;
          debugPrint("🟢 [WEATHER DEBUG] State changed to -> FULL");
        } else {
          _currentState = WeatherState.compact;
          debugPrint("🟢 [WEATHER DEBUG] State changed to -> COMPACT");
        }
      });
    }
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_weather == null || _hasError) return; // Disable drag if error
    if (mounted) {
      setState(() {
        double currentHeight = _dragHeight ?? _getCurrentTargetHeight();
        double newHeight = currentHeight + details.delta.dy;
        _dragHeight = newHeight.clamp(_compactHeight, _fullHeight);

        if (_dragHeight! > _compactHeight + 20) {
          if (_currentState == WeatherState.compact) {
            _currentState = WeatherState.expanded;
          }
        } else if (_dragHeight! <= _compactHeight + 20) {
          if (_currentState != WeatherState.compact) {
            _currentState = WeatherState.compact;
          }
        }
      });
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_weather == null || _hasError) return;

    double velocity = details.primaryVelocity ?? 0;
    double currentHeight = _dragHeight ?? _getCurrentTargetHeight();

    if (mounted) {
      setState(() {
        _dragHeight = null;
        if (velocity > 300) {
          AppHaptics.heavyImpact();
          _currentState = (currentHeight > _expandedHeight * 0.8)
              ? WeatherState.full
              : WeatherState.expanded;
          _scrollToNow(); // 🚀 FIX: Scroll when violently dragged open
        } else if (velocity < -300) {
          AppHaptics.lightImpact();
          _currentState = (currentHeight > _expandedHeight * 1.2)
              ? WeatherState.expanded
              : WeatherState.compact;
        } else {
          if (currentHeight < (_compactHeight + _expandedHeight) / 2) {
            _currentState = WeatherState.compact;
          } else if (currentHeight < (_expandedHeight + _fullHeight) / 2) {
            _currentState = WeatherState.expanded;
            _scrollToNow(); // 🚀 FIX: Scroll when gently dragged open
          } else {
            _currentState = WeatherState.full;
            _scrollToNow(); // 🚀 FIX: Scroll when gently dragged to full
          }
          AppHaptics.mediumImpact();
        }
      });
    }
  }

  double _getCurrentTargetHeight() {
    if (_currentState == WeatherState.compact) return _compactHeight;
    if (_currentState == WeatherState.expanded) return _expandedHeight;
    return _fullHeight;
  }

  Color _getAqiColor(int aqi) {
    if (aqi <= 50) return Colors.greenAccent;
    if (aqi <= 100) return Colors.yellowAccent;
    if (aqi <= 150) return Colors.orangeAccent;
    if (aqi <= 200) return Colors.redAccent;
    return const Color(0xFFE91E63);
  }

  String _getAqiDescription(int aqi) {
    if (aqi <= 50) return "Good";
    if (aqi <= 100) return "Moderate";
    if (aqi <= 150) return "Poor";
    if (aqi <= 200) return "Very Poor";
    return "Severe";
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 INP Optimization: Only listens to the zoom boolean, preventing 5000ms blur lag!
    // Unlike the Selector widget, this allows local setState (taps) to trigger rebuilds.
    final isZoomedIn = context.select<MapProvider, bool>(
      (provider) => provider.currentZoomLevel >= 11.0,
    );

    if (!isZoomedIn) return const SizedBox.shrink();

    return ValueListenableBuilder<WeatherModel?>(
      valueListenable: WeatherService.currentWeather,
      builder: (context, globalWeather, child) {
        if (globalWeather != null) {
          _weather = globalWeather;
          _isLoading = false;
          _hasError = false;
        }

        return _buildWeatherCore(context);
      },
    );
  }

  Widget _buildWeatherCore(BuildContext context) {
    final locService = context.read<GlobalLocationService>();
    String displayCity = locService.currentCity.isEmpty ? "Locating..." : locService.currentCity;
    String displayState = locService.currentState;

    if (displayCity.toLowerCase() == displayState.toLowerCase() && displayCity.isNotEmpty) {
      String c = displayCity.toLowerCase();
      if (c == "delhi" || c == "new delhi") {
        displayState = "National Capital Territory";
      } else {
        displayState = "Union Territory";
      }
    }

    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final bool isDragging = _dragHeight != null;
    final glassColor = isLightMode 
        ? Colors.white.withValues(alpha: isDragging ? 0.95 : 0.65)
        : const Color(0xFF0B0E17).withValues(alpha: isDragging ? 0.95 : 0.75);

    final borderColor = isLightMode
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.white.withValues(alpha: 0.1);

    // 🚀 OPTIMIZATION: Dynamic max width instead of hardcoded 340 to fix overflow
    double maxWidth = MediaQuery.sizeOf(context).width - 32;

    // 🚀 CRITICAL FIX: Removed ValueListenableBuilder to prevent double-rendering.
    // Rely exclusively on the synced local `_weather` state.
    final activeWeather = _weather;
    final bool showLoading = _isLoading && activeWeather == null;

    // 🚀 NEW: Handled Error & Loading States smoothly
    if (showLoading || _hasError || activeWeather == null) {
      return PointerInterceptor(
        child: GestureDetector(
          onTap: () async {
            debugPrint("🟡 [WEATHER DEBUG] FALLBACK BUTTON TAPPED!");
            if (_hasError || activeWeather == null) {
              AppHaptics.lightImpact();
              if (mounted) setState(() { _isLoading = true; _hasError = false; });
              await _resolveLocationAndFetchWeather();
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: _compactWidth,
            height: _compactHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                isLightMode 
                  ? BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 32, offset: const Offset(0, 12))
                  : BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 12)),
              ],
            ),
            child: RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: glassColor,
                      border: Border.all(color: borderColor, width: 1.0),
                    ),
                    child: Center(
                      child: _isLoading 
                          ? CupertinoActivityIndicator(color: isLightMode ? Colors.black54 : Colors.white, radius: 10)
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_outlined, color: isLightMode ? Colors.black54 : Colors.white60, size: 20),
                                const SizedBox(height: 5),
                                Text("Weather", style: GoogleFonts.inter(color: isLightMode ? Colors.black38 : Colors.white38, fontSize: 11, fontWeight: FontWeight.w500)),
                              ],
                            )
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
        }

        final isNight = DateTime.now().hour > 18 || DateTime.now().hour < 6;
        double targetWidth =
            _currentState == WeatherState.compact ? _compactWidth : maxWidth;
        double targetHeight = _dragHeight ?? _getCurrentTargetHeight();
        double currentRadius = _currentState == WeatherState.compact ? 24 : 35;

        return PointerInterceptor(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                debugPrint("🟢 [WEATHER DEBUG] MAIN CARD TAPPED!");
                _handleTap();
              },
              onVerticalDragUpdate: _handleVerticalDragUpdate,
              onVerticalDragEnd: _handleVerticalDragEnd,
              child: AnimatedContainer(
                duration: Duration(milliseconds: _dragHeight != null ? 0 : 650),
                curve: _dragHeight != null ? Curves.linear : Curves.fastOutSlowIn,
                width: targetWidth,
                height: targetHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(currentRadius),
                  boxShadow: [
                    isLightMode
                      ? BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 32, offset: const Offset(0, 12))
                      : BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 12)),
                    if (!isLightMode)
                      BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4)),
                  ],
                ),
                child: RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(currentRadius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: glassColor,
                          border: Border.all(color: borderColor, width: 1.0),
                        ),
                        child: OverflowBox(
                          maxWidth: maxWidth,
                          maxHeight: _fullHeight,
                          alignment: Alignment.topLeft,
                          child: Stack(
                            children: [
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _currentState == WeatherState.compact ? 0.0 : 1.0,
                                child: IgnorePointer(
                                  ignoring: _currentState == WeatherState.compact,
                                  child: SizedBox(
                                    width: maxWidth,
                                    height: _fullHeight,
                                    child: _buildExpandedAndFullView(isNight, isLightMode, displayCity, displayState),
                                  ),
                                ),
                              ),
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _currentState == WeatherState.compact ? 1.0 : 0.0,
                                child: IgnorePointer(
                                  ignoring: _currentState != WeatherState.compact,
                                  child: SizedBox(
                                    width: _compactWidth,
                                    height: _compactHeight,
                                    child: _buildCompactView(isNight, isLightMode),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
  }

  Widget _buildCompactView(bool isNight, bool isLightMode) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PremiumWeatherIcon(
                  code: _weather!.weatherCode, size: 22, isNight: isNight),
              const SizedBox(width: 4),
              Text("${_weather!.temp.toInt()}°",
                  style: GoogleFonts.inter(
                      color: isLightMode ? Colors.black87 : accentColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                      height: 1.0)),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text("AQI ${_weather!.aqi}",
                  style: GoogleFonts.inter(
                      color: isLightMode ? Colors.black87 : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.0)),
              const SizedBox(width: 4),
              Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: _getAqiColor(_weather!.aqi),
                      shape: BoxShape.circle)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedAndFullView(bool isNight, bool isLightMode, String displayCity, String displayState) {
    int high = _weather!.tempMax.toInt();
    int low = _weather!.tempMin.toInt();
    String aqiStatus = _getAqiDescription(_weather!.aqi);

    final primaryText = isLightMode ? Colors.black87 : Colors.white;
    final secondaryText = isLightMode ? Colors.black54 : Colors.white60;
    final dividerColor = isLightMode 
        ? Colors.black.withValues(alpha: 0.08) 
        : Colors.white.withValues(alpha: 0.15);

    return Padding(
      padding: const EdgeInsets.only(top: 24, left: 20, right: 20, bottom: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            PremiumWeatherIcon(
                                code: _weather!.weatherCode,
                                size: 26,
                                isNight: isNight),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ValueListenableBuilder<String>(
                                    valueListenable: context.read<GlobalLocationService>().currentCityName,
                                    builder: (context, cityValue, child) {
                                      String safeCity = cityValue;
                                      String displayCityValue = safeCity.isNotEmpty ? safeCity[0].toUpperCase() + safeCity.substring(1) : safeCity;
                                      return Text(displayCityValue,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                              color: primaryText,
                                              fontSize: 24,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.5,
                                              height: 1.1));
                                    },
                                  ),
                                  if (displayState.isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.only(
                                            top: 2, bottom: 4),
                                        child: Text(displayState,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                                color: secondaryText,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                height: 1.2))),
                                  Text(
                                      WeatherService.getWeatherCondition(
                                          _weather!.weatherCode),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                          color: secondaryText,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          height: 1.2)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("${_weather!.temp.toInt()}°",
                          style: GoogleFonts.inter(
                              color: isLightMode ? Colors.black87 : accentColor,
                              fontSize: 44,
                              fontWeight: FontWeight.w300,
                              height: 1.0)),
                      Text("H:$high°  L:$low°",
                          style: GoogleFonts.inter(
                              color: secondaryText,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 25),
              LayoutBuilder(
                builder: (context, constraints) {
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth < 250 ? 250 : constraints.maxWidth,
                      ),
                      child: Row(
                        children: [
                          Text("AQI ${_weather!.aqi}",
                              style: GoogleFonts.inter(
                                  color: primaryText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 6,
                              child: Stack(
                                alignment: Alignment.centerLeft,
                                children: [
                                  Container(
                                      decoration: BoxDecoration(
                                          color: isLightMode ? Colors.black.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.3),
                                          borderRadius: BorderRadius.circular(10))),
                                  Container(
                                      decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          gradient: const LinearGradient(colors: [
                                            Colors.green,
                                            Colors.yellow,
                                            Colors.orange,
                                            Colors.red,
                                            Colors.purple
                                          ], stops: [
                                            0.1,
                                            0.3,
                                            0.5,
                                            0.7,
                                            0.9
                                          ]))),
                                  Align(
                                    alignment: Alignment(
                                        (_weather!.aqi / 500).clamp(0.0, 1.0) * 2 - 1,
                                        0),
                                    child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.black, width: 2))),
                                  )
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(aqiStatus,
                              style: GoogleFonts.inter(
                                  color: secondaryText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  );
                }
              ),
              const SizedBox(height: 18),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 360,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildDetailItem(Icons.water_drop_outlined, "Humidity", "${_weather!.humidity}%", secondaryText, primaryText),
                      const SizedBox(width: 16),
                      _buildDetailItem(Icons.air_outlined, "Wind", "${_weather!.windSpeed.toStringAsFixed(1)} km/h", secondaryText, primaryText),
                      const SizedBox(width: 16),
                      _buildDetailItem(Icons.thermostat_outlined, "Feels Like", "${_weather!.feelsLike.toInt()}°", secondaryText, primaryText),
                      const SizedBox(width: 16),
                      _buildDetailItem(Icons.wb_sunny_outlined, "UV Index", _weather!.uvIndex.toStringAsFixed(1), secondaryText, primaryText),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Divider(color: dividerColor, height: 1),
              const SizedBox(height: 16),
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.transparent
                      ],
                      stops: [
                        0.0,
                        0.08,
                        0.92,
                        1.0
                      ]).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: ScrollConfiguration(
                  behavior: _NoScrollbarBehavior(),
                  child: SizedBox(
                    height: 100,
                    child: ListView(
                      controller: _hourlyScrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      children: _generate24Hours(isLightMode),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Divider(color: dividerColor, height: 1),
              const SizedBox(height: 16),
              Expanded(
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.white, Colors.white, Colors.transparent],
                        stops: [0.0, 0.65, 1.0]).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ScrollConfiguration(
                    behavior: _NoScrollbarBehavior(),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      physics: const BouncingScrollPhysics(),
                      children: _generate7Days(isLightMode),
                    ),
                  ),
                ),
              ),
            ],
          ),
    );
  }

  // 🚀 COMPLETELY FIXED: REAL HOURLY DATA PARSING
  List<Widget> _generate24Hours(bool isLightMode) {
    if (_weather!.hourly.isEmpty) return [const Text("No hourly data")];

    return _weather!.hourly.map((hourData) {
      String displayTime = "Now";
      bool isHourNight = false;
      bool isPast = false;

      try {
        if (hourData.time.isNotEmpty) {
          DateTime dt = DateTime.parse(hourData.time);
          DateTime now = DateTime.now();
          
          if (dt.isBefore(DateTime(now.year, now.month, now.day, now.hour))) {
            isPast = true;
          }

          int h = dt.hour;
          if (h != now.hour || isPast) {
            String ampm = h >= 12 ? "PM" : "AM";
            int displayH = h % 12 == 0 ? 12 : h % 12;
            displayTime = "$displayH $ampm";
          }
          isHourNight = h > 18 || h < 6;
        }
      } catch (e) {
        displayTime = hourData.time;
      }

      return _buildHourlyItem(
          displayTime, hourData.temp.toInt(), hourData.code, isHourNight, isLightMode, isPast);
    }).toList();
  }

  Widget _buildHourlyItem(String time, int temp, int code, bool isNight, bool isLightMode, bool isPast) {
    Color textColor = isPast 
        ? (isLightMode ? Colors.black38 : Colors.white38) 
        : (isLightMode ? Colors.black87 : Colors.white);
    Color tempColor = isPast 
        ? (isLightMode ? Colors.black38 : Colors.white38) 
        : (isLightMode ? Colors.black54 : Colors.white70);

    return SizedBox(
      width: 65,
      child: Column(
        children: [
          Text(time,
              style: GoogleFonts.inter(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          isPast 
            ? ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0,      0,      0,      0.6, 0,
                ]),
                child: PremiumWeatherIcon(code: code, size: 24, isNight: isNight),
              )
            : PremiumWeatherIcon(code: code, size: 24, isNight: isNight),
          const SizedBox(height: 10),
          Text("$temp°",
              style: GoogleFonts.inter(
                  color: tempColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatDayName(DateTime targetDate) {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime target = DateTime(targetDate.year, targetDate.month, targetDate.day);
    int diff = target.difference(today).inDays;

    if (diff == 0) return "Today";
    if (diff == 1) return "Tomorrow";
    if (diff == -1) return "Yesterday";
    return DateFormat('EEEE').format(targetDate);
  }

  // 🚀 COMPLETELY FIXED: REAL DAILY 7-DAY DATA PARSING
  List<Widget> _generate7Days(bool isLightMode) {
    if (_weather!.daily.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Center(
            child: Text("Data unavailable",
                style: GoogleFonts.inter(
                    color: isLightMode ? Colors.black54 : Colors.white54,
                    fontSize: 14)),
          ),
        )
      ];
    }

    return _weather!.daily.map((dayData) {
      String dayName = dayData.date; // Fallback
      try {
        DateTime date;
        // Handle both unix timestamp (seconds) and ISO-8601 string
        if (int.tryParse(dayData.date) != null) {
          date = DateTime.fromMillisecondsSinceEpoch(int.parse(dayData.date) * 1000);
        } else {
          date = DateTime.parse(dayData.date);
        }
        dayName = _formatDayName(date);
      } catch (e) {
        debugPrint("Date Parsing Error: $e");
      }

      return _buildDailyItem(dayName, dayData.conditionCode, dayData.minTemp.toInt(),
          dayData.maxTemp.toInt(), isLightMode);
    }).toList()
      ..add(const SizedBox(height: 20)); // Bottom padding
  }

  Widget _buildDailyItem(String day, int code, int minT, int maxT, bool isLightMode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth < 280 ? 280 : constraints.maxWidth,
                maxWidth: constraints.maxWidth < 280 ? 280 : constraints.maxWidth,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                      width: 100, // 🚀 CRITICAL FOR ALIGNMENT
                      child: Text(day,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              color: isLightMode ? Colors.black87 : Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500))),
                  Icon(
                      WeatherService.getWeatherIcon(code),
                      size: 22,
                      color: isLightMode ? Colors.black87 : Colors.white),
                  Row(
                    children: [
                      SizedBox(
                        width: 35,
                        child: Text("$minT°",
                            textAlign: TextAlign.start,
                            style: GoogleFonts.inter(color: isLightMode ? Colors.black54 : Colors.white54, fontSize: 15)),
                      ),
                      const SizedBox(width: 10),
                      Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(
                              width: 60,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: isLightMode ? Colors.black.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(5))),
                          Container(
                              width: 60,
                              height: 4,
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(5),
                                  gradient: LinearGradient(colors: [
                                    Colors.lightBlueAccent.withValues(alpha: 0.8),
                                    Colors.orangeAccent.withValues(alpha: 0.9)
                                  ]))),
                        ]
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 35,
                        child: Text("$maxT°",
                            textAlign: TextAlign.end,
                            style: GoogleFonts.inter(
                                color: isLightMode ? Colors.black87 : Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  )
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value, Color secondaryText, Color primaryText) {
    Color severityColor = Colors.blue; // Default Normal/Good

    try {
      if (label == "UV Index") {
        double uv = double.tryParse(value) ?? 0;
        if (uv <= 2) { severityColor = Colors.blue; }
        else if (uv <= 5) { severityColor = Colors.yellow; }
        else if (uv <= 7) { severityColor = Colors.orange; }
        else { severityColor = Colors.red; }
      } else if (label == "Wind") {
        double wind = double.tryParse(value.replaceAll(' km/h', '')) ?? 0;
        if (wind < 15) { severityColor = Colors.blue; }
        else if (wind <= 30) { severityColor = Colors.yellow; }
        else if (wind <= 50) { severityColor = Colors.orange; }
        else { severityColor = Colors.red; }
      } else if (label == "Humidity") {
        double hum = double.tryParse(value.replaceAll('%', '')) ?? 0;
        if (hum >= 30 && hum <= 50) { severityColor = Colors.blue; }
        else if (hum > 50 && hum <= 70) { severityColor = Colors.yellow; }
        else { severityColor = Colors.orange; }
      } else if (label == "Feels Like") {
        double feels = double.tryParse(value.replaceAll('°', '')) ?? 0;
        if (feels > 45 || feels < 5) { severityColor = Colors.red; }
        else if (feels > 35 || feels < 10) { severityColor = Colors.orange; }
        else { severityColor = Colors.blue; }
      }
    } catch (e) {
      severityColor = Colors.blue;
    }

    return Container(
      width: 75,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            severityColor.withValues(alpha: 0.15),
          ],
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: secondaryText, size: 20),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.inter(color: primaryText, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(color: secondaryText, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// 💎 PREMIUM WEATHER ICON (Unchanged - Already Perfect)
class PremiumWeatherIcon extends StatelessWidget {
  final int code;
  final double size;
  final bool isNight;

  const PremiumWeatherIcon(
      {super.key, required this.code, this.size = 24, this.isNight = false});

  @override
  Widget build(BuildContext context) {
    Widget sun = Container(
      width: size * 0.85,
      height: size * 0.85,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
            colors: [Color(0xFFFFE082), Color(0xFFFF8F00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFFF8F00).withValues(alpha: 0.5),
              blurRadius: size * 0.35,
              spreadRadius: size * 0.05)
        ],
      ),
    );

    Widget moon = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFFE3F2FD), Color(0xFF90CAF9)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomRight)
              .createShader(bounds),
          child: Icon(Icons.nightlight_round,
              color: Colors.white, size: size * 0.85),
        ),
        Positioned(
            top: -size * 0.1,
            right: -size * 0.15,
            child: Icon(Icons.star,
                color: Colors.white.withValues(alpha: 0.8), size: size * 0.3)),
        Positioned(
            bottom: -size * 0.05,
            left: -size * 0.15,
            child: Icon(Icons.star,
                color: Colors.white.withValues(alpha: 0.5), size: size * 0.2)),
      ],
    );

    Widget lightCloud = Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
            top: 2,
            left: 2,
            child: Icon(Icons.cloud_rounded,
                color: Colors.black.withValues(alpha: 0.25), size: size)),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.white, Color(0xFFE0E0E0)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter)
              .createShader(bounds),
          child: Icon(Icons.cloud_rounded, color: Colors.white, size: size),
        ),
      ],
    );

    Widget darkCloud = Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
            top: 2,
            left: 2,
            child: Icon(Icons.cloud_rounded,
                color: Colors.black.withValues(alpha: 0.35), size: size)),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFFB0BEC5), Color(0xFF78909C)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter)
              .createShader(bounds),
          child: Icon(Icons.cloud_rounded, color: Colors.white, size: size),
        ),
      ],
    );

    if (code == 0) return isNight ? moon : sun;
    if (code == 1 || code == 2) {
      return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
                left: -size * 0.18,
                top: -size * 0.18,
                child:
                    Transform.scale(scale: 0.7, child: isNight ? moon : sun)),
            lightCloud
          ]);
    }
    if (code == 3 || code == 45 || code == 48) {
      return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
                left: -size * 0.15,
                top: -size * 0.15,
                child: Transform.scale(scale: 0.85, child: darkCloud)),
            lightCloud
          ]);
    }
    if (code >= 51 && code <= 65) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
              top: 2,
              left: 2,
              child: Icon(CupertinoIcons.cloud_rain_fill,
                  color: Colors.black.withValues(alpha: 0.3), size: size)),
          ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(colors: [
                    Colors.white,
                    Color(0xFF4FC3F7),
                    Color(0xFF0288D1)
                  ], stops: [
                    0.1,
                    0.6,
                    1.0
                  ], begin: Alignment.topCenter, end: Alignment.bottomCenter)
                      .createShader(bounds),
              child: Icon(CupertinoIcons.cloud_rain_fill,
                  color: Colors.white, size: size)),
        ],
      );
    }
    if (code >= 71 && code <= 85) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
              top: 2,
              left: 2,
              child: Icon(CupertinoIcons.snow,
                  color: Colors.black.withValues(alpha: 0.3), size: size)),
          ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                      colors: [Colors.white, Color(0xFF81D4FA)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter)
                  .createShader(bounds),
              child:
                  Icon(CupertinoIcons.snow, color: Colors.white, size: size)),
        ],
      );
    }
    if (code >= 95) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
              top: 2,
              left: 2,
              child: Icon(CupertinoIcons.cloud_bolt_fill,
                  color: Colors.black.withValues(alpha: 0.35), size: size)),
          ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(colors: [
                    Color(0xFFE0E0E0),
                    Color(0xFF9575CD),
                    Color(0xFF512DA8)
                  ], stops: [
                    0.1,
                    0.5,
                    1.0
                  ], begin: Alignment.topCenter, end: Alignment.bottomCenter)
                      .createShader(bounds),
              child: Icon(CupertinoIcons.cloud_bolt_fill,
                  color: Colors.white, size: size)),
        ],
      );
    }
    return lightCloud;
  }
}
