import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ridel/core/services/weather_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:ridel/features/profile/services/profile_repository.dart'; 

enum WeatherState { compact, expanded, full }

// 🔥 NAYA: Scrollbar ko force-hide karne ke liye custom behavior
class _NoScrollbarBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
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
  WeatherModel? _weather;
  bool _isLoading = true;
  WeatherState _currentState = WeatherState.compact;
  Position? _lastFetchedLocation; 

  double? _dragHeight;
  final double _compactHeight = 68;
  final double _compactWidth = 82;
  final double _expandedHeight = 265;
  final double _fullHeight = 440;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locService = Provider.of<GlobalLocationService>(context);
    final currentPos = locService.currentPosition;

    if (currentPos != null) {
      if (_lastFetchedLocation == null) {
        _fetchWeather(currentPos);
      } else {
        double distanceKm = Geolocator.distanceBetween(
              _lastFetchedLocation!.latitude,
              _lastFetchedLocation!.longitude,
              currentPos.latitude,
              currentPos.longitude,
            ) /
            1000;

        if (distanceKm > 5.0) {
          _fetchWeather(currentPos);
        }
      }
    }
  }

  Future<void> _fetchWeather(Position pos) async {
    _lastFetchedLocation = pos;
    setState(() => _isLoading = true);

    try {
      final data = await WeatherService.getWeather(pos.latitude, pos.longitude)
          .timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() {
          _weather = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleTap() {
    AppHaptics.mediumImpact();
    setState(() {
      _dragHeight = null;
      if (_currentState == WeatherState.full) {
        _currentState = WeatherState.expanded;
      } else {
        _currentState = _currentState == WeatherState.compact
            ? WeatherState.expanded
            : WeatherState.compact;
      }
    });
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
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

  void _handleVerticalDragEnd(DragEndDetails details) {
    double velocity = details.primaryVelocity ?? 0;
    double currentHeight = _dragHeight ?? _getCurrentTargetHeight();

    setState(() {
      _dragHeight = null;

      if (velocity > 300) {
        AppHaptics.heavyImpact();
        if (currentHeight > _expandedHeight * 0.8) {
          _currentState = WeatherState.full;
        } else {
          _currentState = WeatherState.expanded;
        }
      } else if (velocity < -300) {
        AppHaptics.lightImpact();
        if (currentHeight > _expandedHeight * 1.2) {
          _currentState = WeatherState.expanded;
        } else {
          _currentState = WeatherState.compact;
        }
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
    final Color glassBaseColor = const Color(0xFF1E1E1E).withOpacity(0.65);
    final Border glassBorder =
        Border.all(color: Colors.white.withOpacity(0.15), width: 1.0);
    const double glassBlur = 25.0;

    if (_isLoading || _weather == null) {
      return PointerInterceptor(
        child: Container(
          width: _compactWidth,
          height: _compactHeight,
          decoration: BoxDecoration(
            color: glassBaseColor,
            borderRadius: BorderRadius.circular(20),
            border: glassBorder,
          ),
          child: const Center(
              child: CupertinoActivityIndicator(color: Colors.white, radius: 10)),
        ),
      );
    }

    final isNight = DateTime.now().hour > 18 || DateTime.now().hour < 6;

    double targetWidth =
        _currentState == WeatherState.compact ? _compactWidth : 340;
    double targetHeight = _dragHeight ?? _getCurrentTargetHeight();

    return PointerInterceptor(
      child: TapRegion(
        onTapOutside: (event) {
          if (_currentState != WeatherState.compact) {
            setState(() {
              _dragHeight = null;
              _currentState = WeatherState.compact;
            });
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onVerticalDragUpdate: _handleVerticalDragUpdate,
          onVerticalDragEnd: _handleVerticalDragEnd,
          child: AnimatedContainer(
            duration:
                Duration(milliseconds: _dragHeight != null ? 50 : 650),
            curve: _dragHeight != null
                ? Curves.linear
                : Curves.fastLinearToSlowEaseIn,
            width: targetWidth,
            height: targetHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                  _currentState == WeatherState.compact ? 20 : 32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(
                      _currentState == WeatherState.compact ? 0.20 : 0.40),
                  blurRadius: 35,
                  spreadRadius: 2,
                  offset: const Offset(0, 15),
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                  _currentState == WeatherState.compact ? 20 : 32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
                child: Container(
                  decoration: BoxDecoration(
                    color: glassBaseColor,
                    border: glassBorder,
                    borderRadius: BorderRadius.circular(
                        _currentState == WeatherState.compact ? 20 : 32),
                  ),
                  child: OverflowBox(
                    maxWidth: 340,
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
                              width: 340,
                              height: _fullHeight,
                              child: _buildExpandedAndFullView(isNight),
                            ),
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
                              child: _buildCompactView(isNight),
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
    );
  }

  Widget _buildCompactView(bool isNight) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PremiumWeatherIcon(code: _weather!.weatherCode, size: 22, isNight: isNight),
              const SizedBox(width: 4),
              Text(
                "${_weather!.temp.toInt()}°",
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                    height: 1.0),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "AQI ${_weather!.aqi}",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.0),
              ),
              const SizedBox(width: 4),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _getAqiColor(_weather!.aqi),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedAndFullView(bool isNight) {
    int high = _weather!.temp.toInt() + 4;
    int low = _weather!.temp.toInt() - 3;
    String aqiStatus = _getAqiDescription(_weather!.aqi);

    // 🔥 OUTERMOST SCROLL CONFIGURATION: Ye sabse bahar wali patli line ko gayab karega
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
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
                            PremiumWeatherIcon(code: _weather!.weatherCode, size: 26, isNight: isNight),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: ProfileRepository.userCity,
                                builder: (context, cityName, child) {
                                  final displayCity = (cityName.isEmpty || cityName == "Locating...") 
                                      ? "Current Location" 
                                      : cityName;
                                      
                                  return Text(
                                    displayCity,
                                    maxLines: 1, 
                                    overflow: TextOverflow.ellipsis, 
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Mostly Clear",
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 15), 
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "${_weather!.temp.toInt()}°",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.w300,
                            height: 1.0),
                      ),
                      Text(
                        "H:$high°  L:$low°",
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  )
                ],
              ),

              const SizedBox(height: 25),
              Row(
                children: [
                  Text(
                    "AQI ${_weather!.aqi}",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 6,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              gradient: const LinearGradient(
                                colors: [
                                  Colors.green,
                                  Colors.yellow,
                                  Colors.orange,
                                  Colors.red,
                                  Colors.purple
                                ],
                                stops: [0.1, 0.3, 0.5, 0.7, 0.9],
                              ),
                            ),
                          ),
                          Align(
                            alignment:
                                Alignment((_weather!.aqi / 500).clamp(0.0, 1.0) * 2 - 1, 0),
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black, width: 2),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    aqiStatus,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Divider(color: Colors.white.withOpacity(0.15), height: 1),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  if (_currentState == WeatherState.expanded) {
                    AppHaptics.mediumImpact();
                    setState(() {
                      _currentState = WeatherState.full;
                    });
                  }
                },
                behavior: HitTestBehavior.translucent,
                child: ShaderMask(
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
                      stops: [0.0, 0.08, 0.92, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  // 🔥 INNER LIST 1: Horizontal Hourly Forecast
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                    child: SizedBox(
                      height: 100,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        children: _generate24Hours(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Divider(color: Colors.white.withOpacity(0.15), height: 1),
              const SizedBox(height: 16),
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0.0, 0.65, 1.0],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                // 🔥 INNER LIST 2: Vertical Daily Forecast
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: SizedBox(
                    height: 160,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _buildDailyItem(_getDayName(-3), 2, low - 4, high - 3),
                        _buildDailyItem(_getDayName(-2), 1, low - 1, high - 1),
                        _buildDailyItem("Yesterday", 0, low - 2, high - 2),
                        _buildDailyItem("Today", _weather!.weatherCode, low, high),
                        _buildDailyItem("Tomorrow", 1, low + 1, high + 2),
                        _buildDailyItem(_getDayName(2), 51, low - 1, high - 3),
                        _buildDailyItem(_getDayName(3), 3, low + 2, high + 1),
                        _buildDailyItem(_getDayName(4), 0, low + 3, high + 4),
                        _buildDailyItem(_getDayName(5), 0, low + 1, high + 3),
                        _buildDailyItem(_getDayName(6), 95, low - 2, high - 4),
                        _buildDailyItem(_getDayName(7), 51, low - 3, high - 5),
                        const SizedBox(height: 20),
                      ],
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

  List<Widget> _generate24Hours() {
    List<Widget> hours = [];
    final currentHourNight = DateTime.now().hour > 18 || DateTime.now().hour < 6;
    hours.add(_buildHourlyItem("Now", _weather!.temp.toInt(), _weather!.weatherCode, currentHourNight));
    
    for (int i = 1; i <= 24; i++) {
      int code = (i % 8 == 0) ? 51 : _weather!.weatherCode;
      int tempDiff = (i < 12) ? -(i % 4) : (i % 3);
      int futureHour = (DateTime.now().hour + i) % 24;
      bool isFutureNight = futureHour > 18 || futureHour < 6;
      
      hours.add(_buildHourlyItem(_formatHour(i), _weather!.temp.toInt() + tempDiff, code, isFutureNight));
    }
    return hours;
  }

  String _getDayName(int dayOffset) {
    List<String> days = [
      "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ];
    int currentDay = DateTime.now().weekday;
    int targetDay = (currentDay + dayOffset - 1) % 7;
    if (targetDay < 0) targetDay += 7;
    return days[targetDay];
  }

  String _formatHour(int hoursAhead) {
    int hour = (DateTime.now().hour + hoursAhead) % 24;
    String ampm = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return "$hour $ampm";
  }

  Widget _buildHourlyItem(String time, int temp, int code, bool isNight) {
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Column(
        children: [
          Text(time,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          PremiumWeatherIcon(code: code, size: 24, isNight: isNight),
          const SizedBox(height: 10),
          Text("$temp°",
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildDailyItem(String day, int code, int minT, int maxT) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              day,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
          ),
          // Daily me mostly hum 'din' (day) ka icon dikhate hain, isliye isNight = false
          PremiumWeatherIcon(code: code, size: 22, isNight: false),
          Row(
            children: [
              Text("$minT°",
                  style: const TextStyle(color: Colors.white54, fontSize: 15)),
              const SizedBox(width: 10),
              Container(
                width: 60,
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  gradient: LinearGradient(colors: [
                    Colors.lightBlueAccent.withOpacity(0.8),
                    Colors.orangeAccent.withOpacity(0.9)
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Text("$maxT°",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
            ],
          )
        ],
      ),
    );
  }
}

// 🔥 NAYA WIDGET: Premium 3D Weather Icons with Gradients & Shadows
class PremiumWeatherIcon extends StatelessWidget {
  final int code;
  final double size;
  final bool isNight;

  const PremiumWeatherIcon({
    super.key,
    required this.code,
    this.size = 24,
    this.isNight = false,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Glowing Sun Component
    Widget sun = Container(
      width: size * 0.85,
      height: size * 0.85,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE082), Color(0xFFFF8F00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8F00).withOpacity(0.5),
            blurRadius: size * 0.35,
            spreadRadius: size * 0.05,
          )
        ],
      ),
    );

    // 2. Beautiful Moon Component with Stars
    Widget moon = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFE3F2FD), Color(0xFF90CAF9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: Icon(Icons.nightlight_round, color: Colors.white, size: size * 0.85),
        ),
        Positioned(
          top: -size * 0.1, right: -size * 0.15,
          child: Icon(Icons.star, color: Colors.white.withOpacity(0.8), size: size * 0.3),
        ),
        Positioned(
          bottom: -size * 0.05, left: -size * 0.15,
          child: Icon(Icons.star, color: Colors.white.withOpacity(0.5), size: size * 0.2),
        ),
      ],
    );

    // 3. Volumetric Light Cloud
    Widget lightCloud = Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 2, left: 2,
          child: Icon(Icons.cloud_rounded, color: Colors.black.withOpacity(0.25), size: size),
        ),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, Color(0xFFE0E0E0)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(bounds),
          child: Icon(Icons.cloud_rounded, color: Colors.white, size: size),
        ),
      ],
    );

    // 4. Volumetric Dark Cloud
    Widget darkCloud = Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 2, left: 2,
          child: Icon(Icons.cloud_rounded, color: Colors.black.withOpacity(0.35), size: size),
        ),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFB0BEC5), Color(0xFF78909C)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(bounds),
          child: Icon(Icons.cloud_rounded, color: Colors.white, size: size),
        ),
      ],
    );

    // Render Logic based on Weather Code
    if (code == 0) return isNight ? moon : sun; // Clear

    if (code == 1 || code == 2) { // Partly Cloudy
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: -size * 0.18, top: -size * 0.18,
            child: Transform.scale(
              scale: 0.7, 
              child: isNight ? moon : sun
            ),
          ),
          lightCloud,
        ],
      );
    }

    if (code == 3 || code == 45 || code == 48) { // Cloudy or Fog
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: -size * 0.15, top: -size * 0.15,
            child: Transform.scale(scale: 0.85, child: darkCloud),
          ),
          lightCloud,
        ],
      );
    }

    if (code >= 51 && code <= 65) { // Rain
      return Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 2, left: 2,
            child: Icon(CupertinoIcons.cloud_rain_fill, color: Colors.black.withOpacity(0.3), size: size),
          ),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Colors.white, Color(0xFF4FC3F7), Color(0xFF0288D1)],
              stops: [0.1, 0.6, 1.0],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(bounds),
            child: Icon(CupertinoIcons.cloud_rain_fill, color: Colors.white, size: size),
          ),
        ],
      );
    }
    
    if (code >= 71 && code <= 85) { // Snow
      return Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 2, left: 2,
            child: Icon(CupertinoIcons.snow, color: Colors.black.withOpacity(0.3), size: size),
          ),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Colors.white, Color(0xFF81D4FA)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(bounds),
            child: Icon(CupertinoIcons.snow, color: Colors.white, size: size),
          ),
        ],
      );
    }

    if (code >= 95) { // Thunderstorm
      return Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 2, left: 2,
            child: Icon(CupertinoIcons.cloud_bolt_fill, color: Colors.black.withOpacity(0.35), size: size),
          ),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFE0E0E0), Color(0xFF9575CD), Color(0xFF512DA8)],
              stops: [0.1, 0.5, 1.0],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(bounds),
            child: Icon(CupertinoIcons.cloud_bolt_fill, color: Colors.white, size: size),
          ),
        ],
      );
    }

    // Default fallback
    return lightCloud;
  }
}