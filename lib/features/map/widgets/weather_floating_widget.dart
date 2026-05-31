import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/weather_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/map/services/weather_cache_service.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';

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
  State<WeatherFloatingWidget> createState() => _WeatherFloatingWidgetState();
}

class _WeatherFloatingWidgetState extends State<WeatherFloatingWidget> {
  static const Color accentColor = Color(0xFF00E5FF);

  WeatherModel? _weather;
  WeatherState _currentState = WeatherState.compact;

  // 🚀 OPTIMIZATION: State variables to prevent infinite API loops
  bool _isInitialized = false;
  double? _lastLat;
  double? _lastLng;
  bool _isLoading = true;
  bool _hasError = false;

  // 🚀 OPTIMIZATION: Haversine distance formula to calculate distance in meters
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295; // Math.PI / 180
    final double a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a)) * 1000;
  }

  final WeatherCacheService _weatherCache = WeatherCacheService();
  String _currentCityName = "Locating...";
  String _currentStateName = "";

  double? _dragHeight;
  final double _compactHeight = 68;
  final double _compactWidth = 82;
  final double _expandedHeight = 265;
  final double _fullHeight = 440;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveLocationAndFetchWeather();
  }

  Future<void> _resolveLocationAndFetchWeather() async {
    final locService =
        Provider.of<GlobalLocationService>(context, listen: false);

    double? lat;
    double? lng;

    if (locService.currentPosition != null) {
      lat = locService.currentPosition!.latitude;
      lng = locService.currentPosition!.longitude;
    }

    if (lat == null || lng == null) {
      await locService.forceRefreshLocation();
      if (locService.currentPosition != null) {
        lat = locService.currentPosition!.latitude;
        lng = locService.currentPosition!.longitude;
      } else {
        lat = 28.6139; // Fallback Delhi
        lng = 77.2090;
      }
    }

    // 🚀 OPTIMIZATION: Strict distance threshold check (3km) to prevent API spam
    if (_isInitialized && _lastLat != null && _lastLng != null && _weather != null) {
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
    await _fetchSmartWeatherAndName(lat, lng);
  }

  Future<void> _fetchSmartWeatherAndName(double lat, double lng) async {
    try {
      final locService = Provider.of<GlobalLocationService>(context, listen: false);
      String fullName = locService.currentCity;
      String stateName = locService.currentState;

      if (mounted) {
        setState(() {
          _currentCityName = fullName;
          _currentStateName = stateName;
        });
      }

      final data = await _weatherCache.getSmartWeather(lat, lng, fullName);

      if (mounted) {
        setState(() {
          if (data != null) {
            _weather = data;
            _hasError = false;
          } else {
            _hasError = true;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Weather Widget Fetch Error: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  void _handleTap() {
    if (_hasError || _weather == null) {
      _resolveLocationAndFetchWeather(); // Retry tap
      return;
    }

    AppHaptics.sheetInteraction();
    if (mounted) {
      setState(() {
        _dragHeight = null;
        if (_currentState == WeatherState.compact) {
          _currentState = WeatherState.expanded;
        } else if (_currentState == WeatherState.expanded) {
          _currentState = WeatherState.full;
        } else {
          _currentState = WeatherState.compact;
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
          } else {
            _currentState = WeatherState.full;
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
    final mapProvider = context.watch<MapProvider>();
    if (mapProvider.currentZoomLevel < 11.0) return const SizedBox.shrink();

    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final glassColor = isLightMode 
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF0B0E17).withValues(alpha: 0.75);
    final borderColor = isLightMode
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.white.withValues(alpha: 0.1);

    // 🚀 OPTIMIZATION: Dynamic max width instead of hardcoded 340 to fix overflow
    double maxWidth = MediaQuery.sizeOf(context).width - 32;

    // 🚀 NEW: Handled Error & Loading States smoothly
    if (_isLoading || _hasError || _weather == null) {
      return PointerInterceptor(
        child: RidelBounceButton(
          onTap: _hasError ? _handleTap : null, // Tap to retry
          scaleFactor: 0.95,
          child: Container(
            width: _compactWidth,
            height: _compactHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                isLightMode 
                  ? BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 32,
                      spreadRadius: 0,
                      offset: const Offset(0, 12))
                  : BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 12)),
              ],
            ),
            // 🚀 OPTIMIZATION: Wrap BackdropFilter in RepaintBoundary for performance
            child: RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: glassColor,
                    border: Border.all(
                        color: borderColor,
                        width: 1.0),
                  ),
                  child: Center(
                      child: _hasError
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.refresh_rounded,
                                    color: isLightMode ? Colors.black54 : Colors.white54, size: 24),
                                Text("Retry",
                                    style: GoogleFonts.inter(
                                        color: isLightMode ? Colors.black54 : Colors.white54,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600)),
                              ],
                            )
                          : CupertinoActivityIndicator(
                              color: isLightMode ? Colors.black54 : Colors.white, radius: 10)),
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
      child: TapRegion(
        onTapOutside: (_) {
          if (_currentState != WeatherState.compact) {
            if (mounted) {
              setState(() {
                _dragHeight = null;
                _currentState = WeatherState.compact;
              });
            }
          }
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: _handleVerticalDragUpdate,
            onVerticalDragEnd: _handleVerticalDragEnd,
            child: RidelBounceButton(
              onTap: _handleTap,
              scaleFactor: 0.95,
              child: AnimatedContainer(
                duration:
                    Duration(milliseconds: _dragHeight != null ? 50 : 650),
                // 🚀 Apple-like native physics curve
                curve:
                    _dragHeight != null ? Curves.linear : Curves.fastOutSlowIn,
                width: targetWidth,
                height: targetHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(currentRadius),
                  boxShadow: [
                    isLightMode
                      ? BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 32,
                          spreadRadius: 0,
                          offset: const Offset(0, 12))
                      : BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 24,
                          offset: const Offset(0, 12)),
                    if (!isLightMode)
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4)),
                  ],
                ),
                // 🚀 OPTIMIZATION: Wrap BackdropFilter in RepaintBoundary for performance
                child: RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(currentRadius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        decoration: BoxDecoration(
                          color: glassColor,
                          border: Border.all(
                              color: borderColor,
                              width: 1.0),
                        ),
                        child: OverflowBox(
                          maxWidth: maxWidth,
                          maxHeight: _fullHeight,
                          alignment: Alignment.topLeft,
                          child: Stack(
                            children: [
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _currentState == WeatherState.compact
                                    ? 0.0
                                    : 1.0,
                                child: IgnorePointer(
                                  ignoring: _currentState == WeatherState.compact,
                                  child: SizedBox(
                                      width: maxWidth,
                                      height: _fullHeight,
                                      child: _buildExpandedAndFullView(isNight, isLightMode)),
                                ),
                              ),
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: _currentState == WeatherState.compact
                                  ? 1.0
                                  : 0.0,
                              child: IgnorePointer(
                                ignoring: _currentState != WeatherState.compact,
                                child: SizedBox(
                                    width: _compactWidth,
                                    height: _compactHeight,
                                    child: _buildCompactView(isNight, isLightMode)),
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

  Widget _buildExpandedAndFullView(bool isNight, bool isLightMode) {
    int high = _weather!.tempMax.toInt();
    int low = _weather!.tempMin.toInt();
    String aqiStatus = _getAqiDescription(_weather!.aqi);

    final primaryText = isLightMode ? Colors.black87 : Colors.white;
    final secondaryText = isLightMode ? Colors.black54 : Colors.white60;
    final dividerColor = isLightMode 
        ? Colors.black.withValues(alpha: 0.08) 
        : Colors.white.withValues(alpha: 0.15);

    return ScrollConfiguration(
      behavior: _NoScrollbarBehavior(),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding:
              const EdgeInsets.only(top: 24, left: 20, right: 20, bottom: 0),
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
                                  Text(_currentCityName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                          color: primaryText,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                          height: 1.1)),
                                  if (_currentStateName.isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.only(
                                            top: 2, bottom: 4),
                                        child: Text(_currentStateName,
                                            maxLines: 1,
                                            style: GoogleFonts.inter(
                                                color: secondaryText,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                height: 1.2))),
                                  Text(
                                      WeatherService.getWeatherCondition(
                                          _weather!.weatherCode),
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
              Row(
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
              ShaderMask(
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
                  child: SizedBox(
                    height: 160,
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
        ),
      ),
    );
  }

  // 🚀 COMPLETELY FIXED: REAL HOURLY DATA PARSING
  List<Widget> _generate24Hours(bool isLightMode) {
    if (_weather!.hourly.isEmpty) return [const Text("No hourly data")];

    return _weather!.hourly.map((hourData) {
      String displayTime = "Now";
      bool isHourNight = false;

      try {
        if (hourData.time.isNotEmpty) {
          int h = int.parse(hourData.time.split(':')[0]);
          if (h != DateTime.now().hour) {
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
          displayTime, hourData.temp.toInt(), hourData.code, isHourNight, isLightMode);
    }).toList();
  }

  Widget _buildHourlyItem(String time, int temp, int code, bool isNight, bool isLightMode) {
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Column(
        children: [
          Text(time,
              style: GoogleFonts.inter(
                  color: isLightMode ? Colors.black87 : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          PremiumWeatherIcon(code: code, size: 24, isNight: isNight),
          const SizedBox(height: 10),
          Text("$temp°",
              style: GoogleFonts.inter(
                  color: isLightMode ? Colors.black54 : Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // 🚀 COMPLETELY FIXED: REAL DAILY 7-DAY DATA PARSING
  List<Widget> _generate7Days(bool isLightMode) {
    if (_weather!.daily.isEmpty) return [const Text("No forecast available")];

    List<String> weekdays = [
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
      "Sunday"
    ];

    return _weather!.daily.map((dayData) {
      String dayName = dayData.time; // Fallback
      try {
        DateTime date = DateTime.parse(dayData.time);
        DateTime now = DateTime.now();
        if (date.day == now.day && date.month == now.month) {
          dayName = "Today";
        } else if (date.day == now.add(const Duration(days: 1)).day) {
          dayName = "Tomorrow";
        } else {
          dayName = weekdays[date.weekday - 1];
        }
      } catch (e) {/* Ignore */}

      return _buildDailyItem(dayName, dayData.code, dayData.minTemp.toInt(),
          dayData.maxTemp.toInt(), isLightMode);
    }).toList()
      ..add(const SizedBox(height: 20)); // Bottom padding
  }

  Widget _buildDailyItem(String day, int code, int minT, int maxT, bool isLightMode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
              width: 95,
              child: Text(day,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      color: isLightMode ? Colors.black87 : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500))),
          PremiumWeatherIcon(
              code: code,
              size: 22,
              isNight: false), // Forecast icon usually daytime
          Row(
            children: [
              Text("$minT°",
                  style:
                      GoogleFonts.inter(color: isLightMode ? Colors.black54 : Colors.white54, fontSize: 15)),
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
              Text("$maxT°",
                  style: GoogleFonts.inter(
                      color: isLightMode ? Colors.black87 : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
            ],
          )
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
