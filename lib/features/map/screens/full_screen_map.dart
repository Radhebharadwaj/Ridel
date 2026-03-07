import 'package:flutter/material.dart';
import 'package:ridel/features/map/screens/custom_map_screen.dart';
import 'package:ridel/features/map/widgets/weather_floating_widget.dart';

import 'package:provider/provider.dart';
import 'package:ridel/core/map/map_provider.dart';

class FullScreenMapPage extends StatefulWidget {
  const FullScreenMapPage({super.key});

  @override
  State<FullScreenMapPage> createState() => _FullScreenMapPageState();
}

class _FullScreenMapPageState extends State<FullScreenMapPage> {
  bool _isDarkMode = true;
  double _modesCardProgress = 0.0;
  bool _isWeatherVisible = true;
  bool _isFullUiHidden = false; 

  // 🔥 NAYA CODE START (Listener for Network Errors)
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MapProvider>(context, listen: false).addListener(_onProviderUpdate);
    });
  }

  @override
  void dispose() {
    Provider.of<MapProvider>(context, listen: false).removeListener(_onProviderUpdate);
    super.dispose();
  }

  void _onProviderUpdate() {
    if (!mounted) return;
    final provider = Provider.of<MapProvider>(context, listen: false);
    
    // Agar Backend me network error aaya hai, toh use UI pe Snackbar me dikhao
    if (provider.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.wifi_off_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(provider.lastError!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
            ],
          ),
          backgroundColor: Colors.redAccent.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
          duration: const Duration(seconds: 4),
        )
      );
      provider.clearError(); // Dikhane ke baad error clear kardo
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomMapScreen(
              isDark: _isDarkMode,
              onThemeChanged: (isDark) => setState(() => _isDarkMode = isDark),
              onCardProgress: (progress) {
                setState(() {
                  _modesCardProgress = progress;
                });
              },
              onWeatherVisibilityChanged: (visible) {
                if (_isWeatherVisible != visible) {
                  setState(() {
                    _isWeatherVisible = visible;
                  });
                }
              },
              // Ye ab sirf Tilt par "true" bhejega (Custom Map Screen se)
              onMapInteraction: (hideAll) {
                if (_isFullUiHidden != hideAll) {
                  setState(() {
                    _isFullUiHidden = hideAll;
                  });
                }
              },
            ),
          ),

          // TOP LAYER: WEATHER WIDGET
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: SafeArea(
              top: false,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300), 
                // Hides automatically if Tilt Gesture active OR radius > 6km
                opacity: (_isWeatherVisible && !_isFullUiHidden) ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_isWeatherVisible || _isFullUiHidden, 
                  child: WeatherFloatingWidget(
                    onMapThemeChanged: (isDark) => setState(() => _isDarkMode = isDark),
                  ),
                ),
              ),
            ),
          ),
          
        ],
      ),
    );
  }
}