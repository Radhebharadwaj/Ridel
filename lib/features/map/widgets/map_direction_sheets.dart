// lib/features/map/widgets/map_directions_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
import 'package:provider/provider.dart'; 
import 'package:ridel/core/services/global_location_service.dart'; 
import '../models/place_model.dart';
import '../services/routing_service.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class MapDirectionsSheet extends StatefulWidget {
  final PlaceModel destination;
  final VoidCallback onCancel;

  const MapDirectionsSheet({
    super.key,
    required this.destination,
    required this.onCancel,
  });

  @override
  State<MapDirectionsSheet> createState() => _MapDirectionsSheetState();
}

class _MapDirectionsSheetState extends State<MapDirectionsSheet> {
  String _selectedMode = 'driving'; 
  bool _isLoading = true;
  RouteData? _currentRoute;
  String? _errorMessage; // 🚀 Proper Error Handling
  LatLng? _myRealLocation; 

  @override
  void initState() {
    super.initState();
    // 🚀 Wait for build context to be ready, then fetch from Brain
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocationAndRoute();
    });
  }

  Future<void> _initLocationAndRoute() async {
    final locService = Provider.of<GlobalLocationService>(context, listen: false);
    
    if (locService.currentPosition == null) {
      await locService.forceRefreshLocation(); // Ensure we have a lock
    }

    final pos = locService.currentPosition;
    if (pos != null) {
      _myRealLocation = LatLng(pos.latitude, pos.longitude);
      await _fetchRoute();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = "Unable to fetch GPS location.";
      });
    }
  }

  Future<void> _fetchRoute() async {
    if (_myRealLocation == null) return;
    
    setState(() { _isLoading = true; _errorMessage = null; });
    
    try {
      // 🚀 Added a 10-second timeout for World-Class Network Fallback
      final route = await RoutingService.getRoute(
        _myRealLocation!, 
        LatLng(widget.destination.latitude, widget.destination.longitude),
        mode: _selectedMode
      ).timeout(const Duration(seconds: 10));

      setState(() {
        _currentRoute = route;
        _isLoading = false;
        if (route == null) _errorMessage = "Route unavailable for this mode.";
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Network error. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E).withOpacity(0.9) : Colors.white.withOpacity(0.9);
    final neonCyan = const Color(0xFF00E5FF);

    return Align(
      alignment: Alignment.bottomCenter,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            width: double.infinity,
            height: 400, 
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Directions", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                      GestureDetector(
                        onTap: widget.onCancel,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    height: 45,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildModeIcon(CupertinoIcons.car_detailed, 'driving'),
                        _buildModeIcon(Icons.directions_walk_rounded, 'walking'),
                        _buildModeIcon(Icons.directions_transit_rounded, 'transit'),
                        _buildModeIcon(Icons.pedal_bike_rounded, 'cycling'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      children: [
                        _buildTimelineRow(CupertinoIcons.location_solid, "My Location", Colors.blueAccent),
                        Container(margin: const EdgeInsets.only(left: 10, top: 5, bottom: 5), height: 15, width: 2, color: Colors.white24, alignment: Alignment.centerLeft),
                        _buildTimelineRow(CupertinoIcons.star_fill, widget.destination.name, Colors.deepPurpleAccent),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 🚀 Enhanced Error & Loading UI
                          if (_isLoading)
                            const CupertinoActivityIndicator(color: Colors.white)
                          else if (_errorMessage != null)
                            Text(_errorMessage!, style: const TextStyle(fontSize: 16, color: Colors.redAccent, fontWeight: FontWeight.w500))
                          else ...[
                            Text(
                              "${_currentRoute?.durationMins.toStringAsFixed(0) ?? '--'} min", 
                              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: neonCyan)
                            ),
                            Text(
                              "ETA • ${_currentRoute?.distanceKm.toStringAsFixed(1) ?? '--'} km", 
                              style: const TextStyle(fontSize: 14, color: Colors.white70)
                            ),
                          ]
                        ],
                      ),
                      GestureDetector(
                        onTap: (_isLoading || _errorMessage != null) ? null : () {},
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                          decoration: BoxDecoration(
                            color: (_isLoading || _errorMessage != null) ? Colors.grey : const Color(0xFF34C759),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              if (!_isLoading && _errorMessage == null)
                                BoxShadow(color: const Color(0xFF34C759).withOpacity(0.4), blurRadius: 15, spreadRadius: 2)
                            ],
                          ),
                          child: const Text("GO", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeIcon(IconData icon, String mode) {
    bool isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() => _selectedMode = mode);
          _fetchRoute(); 
        }
      },
      child: Container(
        width: 60, height: double.infinity,
        decoration: BoxDecoration(color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent, borderRadius: BorderRadius.circular(15)),
        child: Icon(icon, color: isSelected ? Colors.white : Colors.white54, size: 24),
      ),
    );
  }

  Widget _buildTimelineRow(IconData icon, String title, Color iconColor) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20), const SizedBox(width: 12),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
        const Spacer(), const Icon(Icons.drag_handle_rounded, color: Colors.white24)
      ],
    );
  }
}