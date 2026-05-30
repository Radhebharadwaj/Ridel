import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/widgets/ridel_glass.dart';
import 'package:ridel/features/map/models/place_model.dart';
import 'package:ridel/features/map/widgets/place_service.dart';

class QuickActionButtons extends StatefulWidget {
  final bool isDark;
  final Function(String actionType) onRequestSearch;
  final Function(PlaceModel destination) onNavigateReady;

  const QuickActionButtons({
    super.key,
    required this.isDark,
    required this.onRequestSearch,
    required this.onNavigateReady,
  });

  @override
  State<QuickActionButtons> createState() => QuickActionButtonsState();
}

class QuickActionButtonsState extends State<QuickActionButtons> {
  PlaceModel? _homePlace;
  PlaceModel? _workPlace;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    refreshData(); // 🚀 Changed to public method
  }

  // 🚀 Call this method to forcefully reload buttons when a place is saved!
  Future<void> refreshData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      final home = await SavedPlacesService.getHome();
      final work = await SavedPlacesService.getWork();
      if (mounted) {
        setState(() {
          _homePlace = home;
          _workPlace = work;
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('home_place, work_place')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted && response != null) {
        setState(() {
          if (response['home_place'] != null) {
            final h = response['home_place'];
            _homePlace = PlaceModel(
                placeId: h['place_id'] ?? 'home_${user.id}',
                name: h['name'],
                address: h['address'],
                latitude: h['latitude'],
                longitude: h['longitude'],
                categories: ['Home']);
          } else {
            _homePlace = null;
          }

          if (response['work_place'] != null) {
            final w = response['work_place'];
            _workPlace = PlaceModel(
                placeId: w['place_id'] ?? 'work_${user.id}',
                name: w['name'],
                address: w['address'],
                latitude: w['latitude'],
                longitude: w['longitude'],
                categories: ['Work']);
          } else {
            _workPlace = null;
          }
        });
      }
    } catch (e) {
      debugPrint("Failed to load places: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleHomeTap() {
    AppHaptics.mediumImpact();
    if (_homePlace == null) {
      widget.onRequestSearch('HOME');
    } else {
      widget.onNavigateReady(_homePlace!);
    }
  }

  void _handleWorkTap() {
    AppHaptics.mediumImpact();
    if (_workPlace == null) {
      widget.onRequestSearch('WORK');
    } else {
      widget.onNavigateReady(_workPlace!);
    }
  }

  void _handleAddPlaceTap() {
    AppHaptics.lightImpact();
    widget.onRequestSearch('CUSTOM');
  }

  void _handleLongPress(String type) {
    AppHaptics.heavyImpact();
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text("Manage $type",
            style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54)),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              widget.onRequestSearch(type.toUpperCase());
            },
            child: const Text("Edit Address"),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              final user = Supabase.instance.client.auth.currentUser;
              if (user != null) {
                String column = type == 'Home' ? 'home_place' : 'work_place';
                await Supabase.instance.client.from('user_profiles').update({column: null}).eq('id', user.id);
              } else {
                if (type == 'Home') {
                  await SavedPlacesService.deleteHome();
                } else if (type == 'Work') {
                  await SavedPlacesService.deleteWork();
                }
              }
              await refreshData();
            },
            child: const Text("Remove"),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLightMode;
    
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _isLoading
          ? const SizedBox(height: 86, child: Center(child: CupertinoActivityIndicator()))
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onLongPress: _homePlace != null ? () => _handleLongPress('Home') : null,
                  child: _buildGlassActionBtn(
                    icon: CupertinoIcons.house_fill,
                    title: "Home",
                    subtitle: _homePlace != null ? "Drive" : "Add",
                    isSet: _homePlace != null,
                    isDark: isDark,
                    onTap: _handleHomeTap,
                  ),
                ),
                GestureDetector(
                  onLongPress: _workPlace != null ? () => _handleLongPress('Work') : null,
                  child: _buildGlassActionBtn(
                    icon: CupertinoIcons.briefcase_fill,
                    title: "Work",
                    subtitle: _workPlace != null ? "Drive" : "Add",
                    isSet: _workPlace != null,
                    isDark: isDark,
                    onTap: _handleWorkTap,
                  ),
                ),
                _buildGlassActionBtn(
                  icon: CupertinoIcons.add,
                  title: "Add",
                  subtitle: "Place",
                  isSet: false,
                  isDark: isDark,
                  onTap: _handleAddPlaceTap,
                ),
              ],
            ),
    );
  }

  Widget _buildGlassActionBtn(
      {required IconData icon, required String title, required String subtitle, required bool isSet, required bool isDark, required VoidCallback onTap}) {
    final isLightMode = !isDark;
    const Color neonCyan = Color(0xFF00E5FF);
    final Color activeCyan = isLightMode ? Colors.cyan.shade700 : neonCyan;
    final Color activeColor = isSet ? activeCyan : (isLightMode ? Colors.black87 : Colors.white70);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isLightMode ? Colors.white : null,
                borderRadius: BorderRadius.circular(40),
                border: isLightMode ? Border.all(color: Colors.black.withValues(alpha: 0.04)) : null,
                boxShadow: isLightMode
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))]
                    : null,
              ),
              child: isLightMode
                  ? Center(child: Icon(icon, color: activeColor, size: 24))
                  : RidelGlass(
                      borderRadius: BorderRadius.circular(40),
                      baseColor: Colors.white.withValues(alpha: 0.08),
                      blurSigma: 20.0,
                      isVerticalCard: true,
                      child: Center(child: Icon(icon, color: activeColor, size: 24)),
                    ),
            ),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: isLightMode ? Colors.black87 : Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            Text(subtitle, style: TextStyle(color: isSet ? activeCyan : (isLightMode ? Colors.black54 : Colors.white54), fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}