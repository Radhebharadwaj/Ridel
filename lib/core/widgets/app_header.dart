import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridel/core/utils/toast_service.dart';
import '../utils/app_haptics.dart';
import '../../features/profile/services/profile_repository.dart'; 
import '../../features/profile/screens/profile_screen.dart'; 
import 'ridel_sheet.dart'; 
import 'city_selector_sheet.dart'; 
import 'ridel_glass_dropdown.dart'; 

import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/place_service.dart';
import 'package:ridel/core/widgets/notification_sheet.dart'; 
import 'package:ridel/core/services/notification_service.dart';

class AppHeader extends StatefulWidget {
  final Widget? actionWidget; 
  final bool showProfile;

  const AppHeader({
    super.key, 
    this.actionWidget,
    this.showProfile = true
  });

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  final ProfileRepository _repo = ProfileRepository();
  
  String _notificationMode = 'Active'; 
  final List<String> _notifOptions = ['Active', 'Mute Notifications', 'Turn Off'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
    });
  }

  Future<void> _initLocation() async {
    try {
      await _repo.getProfile();
      String current = ProfileRepository.userCity.value;
      if (current == "Locating..." || current == "Select City" || current.isEmpty || current == "Detecting...") {
        _detectAndSaveRealLocation(); 
      }
    } catch (e) {
      // Silent fail
    }
  }

  Future<void> _detectAndSaveRealLocation() async {
    try {
      final locationService = Provider.of<GlobalLocationService>(context, listen: false);

      if (!locationService.hasValidLocation) {
        ProfileRepository.userCity.value = "Locating...";
        await locationService.initializeEcoLocation();
      }

      final position = locationService.currentPosition;

      if (position != null) {
        if (position.isMocked) {
          ProfileRepository.userCity.value = "Fake GPS Detected";
          AppHaptics.heavyImpact();
          return; 
        }

        final detectedCity = await PlaceService.getCityFromCoordinates(
          position.latitude, 
          position.longitude
        );

        if (detectedCity != null) {
          ProfileRepository.userCity.value = detectedCity;
          
          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            await _repo.updateProfile({'current_city': detectedCity});
          }
        } else {
           ProfileRepository.userCity.value = "Select City";
        }
      } else {
        ProfileRepository.userCity.value = "Select City";
      }
    } catch (e) {
      ProfileRepository.userCity.value = "Select City";
    }
  }

  void _openCitySelector() {
    HapticFeedback.lightImpact();
    CitySelectorSheet.show(context);
  }

  void _showNotificationSettings() {
    AppHaptics.heavyImpact();
    RidelGlassDropdown.show(
      context, 
      options: _notifOptions, 
      selectedValue: _notificationMode,
      onSelected: (val) {
        setState(() => _notificationMode = val);
        AppHaptics.lightImpact();
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    // 🔥 SMART CALCULATION: Ye line Commute aur Home dono ko perfectly align karegi!
    final double topInset = MediaQuery.of(context).padding.top;
    final double dynamicPadding = topInset > 0 ? (topInset + 20) : 10;

    IconData bellIcon = Icons.notifications_rounded; 
    Color bellColor = isDark ? Colors.white.withOpacity(0.45) : Colors.black.withOpacity(0.45); 

    if (_notificationMode == 'Mute Notifications') {
      bellIcon = Icons.notifications_paused_rounded;
      bellColor = Colors.orangeAccent.withOpacity(0.85);
    } else if (_notificationMode == 'Turn Off') {
      bellIcon = Icons.notifications_off_rounded;
      bellColor = isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.15);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: dynamicPadding, // Ye auto-adjust hoke alignment lock kar dega
        bottom: 12, 
        left: 20,
        right: 20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            bgColor,                      
            bgColor.withOpacity(0.9),     
            bgColor.withOpacity(0.0),     
          ],
          stops: const [0.1, 0.4, 1.0],   
        ),
      ),
      // 🔥 EXACT 44PX LOCK: Text ke jhatke band karne ke liye
      child: SizedBox(
        height: 44, 
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center, 
          children: [
            Expanded( 
              child: GestureDetector(
                onTap: _openCitySelector,
                behavior: HitTestBehavior.opaque, 
                child: ValueListenableBuilder<String>(
                  valueListenable: ProfileRepository.userCity,
                  builder: (context, cityName, child) {
                    String displayTitle = (cityName.isEmpty || cityName == "Locating...") 
                        ? "Select City" 
                        : cityName;
                    
                    displayTitle = displayTitle.replaceAll(RegExp(r'^New\s+', caseSensitive: false), '')
                                               .replaceAll(RegExp(r'^West\s+', caseSensitive: false), '');
                    
                    final isFake = displayTitle == "Fake GPS Detected";

                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                        return Stack(
                          alignment: Alignment.centerLeft, 
                          children: <Widget>[
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      child: Text(
                        displayTitle,
                        key: ValueKey<String>(displayTitle),
                        style: GoogleFonts.inter(
                          fontSize: isFake ? 22 : 34, 
                          fontWeight: FontWeight.bold,
                          color: isFake ? Colors.redAccent : textColor, 
                          letterSpacing: -1.0, 
                          height: 1.0, 
                        ),
                        maxLines: 1, 
                        overflow: TextOverflow.ellipsis, 
                      ),
                    );
                  },
                ),
              ),
            ),
            
            const SizedBox(width: 15), 

            if (widget.actionWidget != null) 
              Container(
                height: 44,
                alignment: Alignment.centerRight,
                child: widget.actionWidget!
              )
            else if (widget.showProfile) 
              GestureDetector(
                onTap: () {
                  AppHaptics.lightImpact();
                  RidelSheet.show(
                    context, 
                    title: "Notifications", 
                    showCloseButton: true,
                    child: NotificationSheetContent(), 
                  );
                },
                onLongPress: _showNotificationSettings, 
                child: Container(
                  width: 44, 
                  height: 44,
                  color: Colors.transparent, 
                  alignment: Alignment.centerRight, 
                  child: ValueListenableBuilder<List<RidelNotification>>(
                    valueListenable: NotificationService().notificationsNotifier,
                    builder: (context, notifs, child) {
                      return Stack(
                        clipBehavior: Clip.none, 
                        children: [
                          Icon(bellIcon, color: bellColor, size: 26), 
                          
                          if (NotificationService().hasUnreadNotifications() && _notificationMode == 'Active') 
                            Positioned(
                              top: 2, right: 0, 
                              child: Container(
                                width: 10, height: 10, 
                                decoration: BoxDecoration(
                                  color: Colors.redAccent, 
                                  shape: BoxShape.circle, 
                                  border: Border.all(color: bgColor, width: 2.0) 
                                )
                              ),
                            )
                        ],
                      );
                    }
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}