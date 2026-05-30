import 'package:flutter/material.dart';
import 'package:ridel/core/map/map_style_helper.dart';

class ThemeSelectionSheet {
  static void show(BuildContext context, MapThemeType currentTheme, Function(MapThemeType) onThemeSelected) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final activeCyan = isLightMode ? Colors.cyan.shade700 : const Color(0xFF00E5FF);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: isLightMode ? Colors.white : const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Select Map Theme", style: TextStyle(color: isLightMode ? Colors.black87 : Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Divider(color: isLightMode ? Colors.grey.shade200 : Colors.white12, height: 1),
                ListTile(
                  title: Text("Dark Mode", style: TextStyle(color: isLightMode ? Colors.black87 : Colors.white)),
                  trailing: currentTheme == MapThemeType.dark ? Icon(Icons.check_circle, color: activeCyan) : null,
                  onTap: () { onThemeSelected(MapThemeType.dark); Navigator.pop(context); },
                ),
                Divider(color: isLightMode ? Colors.grey.shade200 : Colors.white12, height: 1),
                ListTile(
                  title: Text("Light Mode", style: TextStyle(color: isLightMode ? Colors.black87 : Colors.white)),
                  trailing: currentTheme == MapThemeType.light ? Icon(Icons.check_circle, color: activeCyan) : null,
                  onTap: () { onThemeSelected(MapThemeType.light); Navigator.pop(context); },
                ),
              ],
            ),
          ),
        );
      }
    );
  }
}