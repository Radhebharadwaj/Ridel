// lib/features/map/widgets/map_details_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ridel/features/map/map_engine/controllers/map_mode_controller.dart';

class MapDetailsSheet extends StatelessWidget {
  const MapDetailsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final modeController = context.read<MapModeController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Map details",
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              IconButton(
                  icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black54),
                  onPressed: () => Navigator.pop(context))
            ],
          ),
          const SizedBox(height: 20),
          Text("Map type",
              style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ValueListenableBuilder<MapMapType>(
                valueListenable: modeController.mapType,
                builder: (context, mapType, _) {
                  return _buildTypeCard(
                      context: context,
                      isDark: isDark,
                      title: "Default",
                      icon: Icons.map,
                      isSelected: mapType == MapMapType.defaultVector,
                      onTap: () =>
                          modeController.setMapType(MapMapType.defaultVector));
                },
              ),
              ValueListenableBuilder<MapMapType>(
                valueListenable: modeController.mapType,
                builder: (context, mapType, _) {
                  return _buildTypeCard(
                      context: context,
                      isDark: isDark,
                      title: "Satellite",
                      icon: Icons.satellite_alt,
                      isSelected: mapType == MapMapType.satellite,
                      onTap: () =>
                          modeController.setMapType(MapMapType.satellite));
                },
              ),
            ],
          ),
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Divider(color: isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.05), height: 1)),
          Text("Map details",
              style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: modeController.showTransitLayer,
                builder: (context, showTransitLayer, _) {
                  return _buildDetailCard(
                      context: context,
                      isDark: isDark,
                      title: "Transit",
                      icon: Icons.directions_transit,
                      isSelected: showTransitLayer,
                      onTap: () => modeController.toggleTransitLayer());
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: modeController.showTraffic,
                builder: (context, showTraffic, _) {
                  return _buildDetailCard(
                      context: context,
                      isDark: isDark,
                      title: "Traffic",
                      icon: Icons.traffic,
                      isSelected: showTraffic,
                      onTap: () => modeController.toggleTraffic());
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: modeController.showPOIs,
                builder: (context, showPOIs, _) {
                  return _buildDetailCard(
                      context: context,
                      isDark: isDark,
                      title: "POIs",
                      icon: Icons.store,
                      isSelected: showPOIs,
                      onTap: () => modeController.togglePOIs());
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildTypeCard(
      {required BuildContext context,
      required bool isDark,
      required String title,
      required IconData icon,
      required bool isSelected,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 70,
            width: 70,
            decoration: BoxDecoration(
                color: isSelected
                    ? Colors.cyan.withValues(alpha: 0.2)
                    : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isSelected ? Colors.cyan : Colors.transparent,
                    width: 2)),
            child: Icon(icon,
                color: isSelected ? Colors.cyan : (isDark ? Colors.white70 : Colors.black54), size: 32),
          ),
          const SizedBox(height: 8),
          Text(title,
              style: TextStyle(
                  color: isSelected ? Colors.cyan : (isDark ? Colors.white70 : Colors.black54),
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildDetailCard(
      {required BuildContext context,
      required bool isDark,
      required String title,
      required IconData icon,
      required bool isSelected,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 50,
            width: 50,
            decoration: BoxDecoration(
                color: isSelected ? Colors.cyan : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                shape: BoxShape.circle),
            child: Icon(icon,
                color: isSelected ? Colors.black : (isDark ? Colors.white70 : Colors.black54), size: 24),
          ),
          const SizedBox(height: 8),
          Text(title,
              style: TextStyle(
                  color: isSelected ? (isDark ? Colors.white : Colors.black87) : (isDark ? Colors.white70 : Colors.black54),
                  fontSize: 13)),
        ],
      ),
    );
  }
}
