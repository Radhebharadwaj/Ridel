import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/auth/screens/login_screen.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/services/identity_service.dart';
import 'package:ridel/core/services/theme_service.dart';
import '../services/profile_repository.dart';

import 'package:provider/provider.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/place_service.dart';

import '../../../core/widgets/ridel_sheet.dart';
import '../../../core/widgets/ridel_glass_modal.dart';
import '../../../core/widgets/ridel_glass_dropdown.dart';
import '../../../core/widgets/city_selector_sheet.dart';

import 'security_screen.dart';
import 'mobile_verification_screen.dart';
import 'edit_profile_dialog.dart';
import 'appearance_dialog.dart';

import '../widgets/permissions_center_sheet.dart'; 

class ProfileSheetContent extends StatefulWidget {
  const ProfileSheetContent({super.key});
  @override
  State<ProfileSheetContent> createState() => _ProfileSheetContentState();
}

class _ProfileSheetContentState extends State<ProfileSheetContent> {
  late final ProfileRepository _repo;
  final IdentityService _identityService = IdentityService();
  
  Map<String, dynamic>? _profileData;
  bool _isDataLoaded = false;
  
  final TextEditingController _userIdCtrl = TextEditingController();
  String? _email, _selectedGender;
  DateTime? _selectedDOB;
  bool _isGuest = false;

  @override
  void initState() {
    super.initState();
    _repo = ProfileRepository();
    _checkUserStatus();
  }

  Future<void> _checkUserStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() { _isGuest = true; _isDataLoaded = true; });
    } else {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final data = await _repo.getProfile();
    if (mounted) {
      setState(() {
        _profileData = data;
        _email = data?['email'];
        _userIdCtrl.text = data?['user_id_custom'] ?? '';
        _selectedGender = data?['gender'];
        if (data?['dob'] != null) try { _selectedDOB = DateTime.parse(data!['dob']); } catch (_) {}
        _isDataLoaded = true;
      });
    }
  }

  // 🚀 NAYA CLEAN LOCATION LOGIC (Replaced the old locData block)
  Future<void> _fetchAutoLocation() async {
    ProfileRepository.userCity.value = "Locating...";
    
    try {
      final locationService = Provider.of<GlobalLocationService>(context, listen: false);
      
      if (!locationService.hasValidLocation) {
        await locationService.initializeEcoLocation();
      }

      final pos = locationService.currentPosition;
      
      if (pos != null && !pos.isMocked) {
        final detectedCity = await PlaceService.getCityFromCoordinates(pos.latitude, pos.longitude);
        
        if (detectedCity != null) {
          if (!_isGuest) {
            await _repo.updateProfile({
              'current_city': detectedCity,
              // NOTE: state_code aur country_code hata diye hain kyunki 
              // naya PlaceService sirf accurate city name deta hai (Cost saving).
            });
          } else {
            ProfileRepository.userCity.value = detectedCity;
          }
          
          if (mounted) {
            ToastService.showSuccess(context, "Location updated: $detectedCity");
            _loadData();
          }
        } else {
           ProfileRepository.userCity.value = "Select City";
           if (mounted) ToastService.showError(context, "Could not detect location. Select manually.");
        }
      } else {
        ProfileRepository.userCity.value = "Select City";
        if (mounted) ToastService.showError(context, "Could not get GPS fix.");
      }
    } catch (e) {
      debugPrint("⚠️ Profile Location Update Error: $e");
      ProfileRepository.userCity.value = "Select City";
      if (mounted) ToastService.showError(context, "Location service error.");
    }
  }

  void _redirectToLogin() {
    AppHaptics.heavyImpact();
    Navigator.pop(context); 
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<void> _updateField(String key, dynamic value) async {
    if (_isGuest) return;
    await _repo.updateProfile({key: value});
    if (mounted) ToastService.showSuccess(context, "Saved!");
    _loadData();
  }

  void _showGenderMenu() {
    if (_isGuest) return;
    RidelGlassDropdown.show(context, options: ["Male", "Female", "Prefer not to say"], selectedValue: _selectedGender, onSelected: (val) {
      setState(() => _selectedGender = val);
      _updateField('gender', val);
    });
  }

  void _showDatePicker() {
    if (_isGuest) return;
    AppHaptics.selectionClick();
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    DateTime tempDate = _selectedDOB ?? DateTime(2000);
    
    RidelGlassModal.show(context, height: 350, child: Column(children: [
      Text("Select Birthdate", style: GoogleFonts.inter(
        color: isDark ? Colors.white : Colors.black, 
        fontSize: 18, 
        fontWeight: FontWeight.bold
      )),
      const SizedBox(height: 20),
      Expanded(
        child: CupertinoTheme(
          data: CupertinoThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
            textTheme: CupertinoTextThemeData(
              dateTimePickerTextStyle: GoogleFonts.inter(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 18
              ),
            ),
          ), 
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.date, 
            initialDateTime: tempDate, 
            minimumDate: DateTime(1950), 
            maximumDate: DateTime.now(), 
            onDateTimeChanged: (val) => tempDate = val
          )
        )
      ),
      SizedBox(
        width: double.infinity, 
        child: ElevatedButton(
          onPressed: () { 
            Navigator.pop(context); 
            setState(() => _selectedDOB = tempDate); 
            _updateField('dob', DateFormat('yyyy-MM-dd').format(tempDate)); 
          }, 
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? Colors.white : Colors.black, 
            foregroundColor: isDark ? Colors.black : Colors.white
          ), 
          child: const Text("Save Date")
        )
      ),
    ]));
  }

  void _openEditProfile() {
    if (_isGuest) {
      _redirectToLogin();
    } else {
      AppHaptics.lightImpact();
      RidelGlassModal.show(context, child: EditProfileContent(initialData: _profileData, repository: _repo, onSaved: _loadData));
    }
  }

  // ✅ Helper Function for Initials
  String _getInitials(String name) {
    if (name.isEmpty) return "U";
    List<String> parts = name.trim().split(' ');
    if (parts.length > 1) {
      return "${parts[0][0]}${parts.last[0]}".toUpperCase();
    }
    return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : "U";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color cardColor = isDark ? Colors.white.withOpacity(0.08) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black;
    final Color subTextColor = isDark ? Colors.grey : Colors.grey.shade600;
    final Color iconColor = isDark ? Colors.white : Colors.black;
    final Color dividerColor = isDark ? Colors.white.withOpacity(0.08) : Colors.black12;

    final String fName = _isGuest ? "Guest User" : (_profileData?['full_name'] ?? 'User');
    final String avatar = _profileData?['avatar_url'] ?? '';

    return Material(
      color: Colors.transparent,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, overscroll: false),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 95, 20, 50),
          child: Column(children: [
            
            // 1. Header with FIXED IMAGE LOGIC (Placed correctly inside build)
            CircleAvatar(
              radius: 45, 
              backgroundColor: cardColor, 
              child: ClipOval(
                child: SizedBox(
                  width: 90, height: 90,
                  child: (!_isGuest && avatar.isNotEmpty)
                    ? Image.network(
                        avatar,
                        fit: BoxFit.cover,
                        // 🛑 Error Builder: Shows Initials if image fails
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Text(
                              _getInitials(fName),
                              style: GoogleFonts.inter(color: textColor, fontSize: 28, fontWeight: FontWeight.bold)
                            ),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(child: CircularProgressIndicator(strokeWidth: 2, color: iconColor));
                        },
                      )
                    : Center(
                        child: Text(
                          _isGuest ? "G" : _getInitials(fName), 
                          style: GoogleFonts.inter(color: textColor, fontSize: 28, fontWeight: FontWeight.bold)
                        ),
                      ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(fName, style: GoogleFonts.inter(color: textColor, fontSize: 24, fontWeight: FontWeight.bold)),
            
            TextButton(
              onPressed: _openEditProfile, 
              child: Text(_isGuest ? "Log in to Ridel" : "Edit Profile", style: const TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold))
            ),
            
            const SizedBox(height: 30),

            // 2. Personal Info
            if (!_isGuest) ...[
              _section("Account"),
              _card(cardColor, isDark, Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent, unselectedWidgetColor: iconColor), 
                  child: ExpansionTile(
                    initiallyExpanded: true, collapsedShape: const Border(), shape: const Border(),
                    leading: Icon(Icons.person, color: iconColor), 
                    title: Text("Personal Info", style: TextStyle(color: textColor)),
                    iconColor: iconColor, collapsedIconColor: iconColor,
                    children: [
                      _row("Email", _email ?? "Loading...", textColor, subTextColor, readOnly: true),
                      _row("User ID", _userIdCtrl.text.isEmpty ? "Set ID" : _userIdCtrl.text, textColor, subTextColor, isLink: true, onTap: _openEditProfile),
                      _row("Birthdate", _selectedDOB != null ? DateFormat('dd MMM yyyy').format(_selectedDOB!) : "Not set", textColor, subTextColor, isLink: true, onTap: _showDatePicker),
                      _row("Gender", _selectedGender ?? "Not set", textColor, subTextColor, isLink: true, onTap: _showGenderMenu),
                    ]
                  )
              )),
              const SizedBox(height: 20),
            ],

            // 3. Travel Setup
            _section("Travel"),
            _card(cardColor, isDark, Column(children: [
                _tile(
                  Icons.phone, 
                  "Mobile", 
                  _isGuest ? "Login to verify" : (_profileData?['phone_primary'] ?? 'Unverified'), 
                  iconColor, 
                  textColor, 
                  subTextColor, 
                  () {
                    if (_isGuest) {
                      _redirectToLogin();
                    } else {
                      AppHaptics.lightImpact();
                      RidelGlassModal.show(
                        context, 
                        child: MobileVerificationModal(repository: _repo)
                      ).then((_) => _loadData());
                    }
                  }
                ),
                Divider(height: 1, color: dividerColor),
                
                // ✅ FIXED: Correct City Selector Call
                _tile(Icons.gps_fixed, "City", _isGuest ? (ProfileRepository.userCity.value == "Locating..." ? "Select City" : ProfileRepository.userCity.value) : (_profileData?['current_city'] ?? 'Set'), iconColor, textColor, subTextColor, () => RidelSheet.show(
                    context, 
                    title: "Select City", 
                    showBackButton: true, 
                    child: const CitySelectorSheet()
                  )
                ),
            ])),

            const SizedBox(height: 20),

            // 4. Preferences (Permissions added here)
            _section("Preferences"),
            _card(cardColor, isDark, Column(children: [
                
                // Appearance
                _tile(Icons.palette, "Appearance", ThemeService.themeNotifier.value == ThemeMode.dark ? "Dark" : (ThemeService.themeNotifier.value == ThemeMode.light ? "Light" : "System"), iconColor, textColor, subTextColor, () {
                     RidelGlassModal.show(context, child: const AppearanceDialog());
                }),
                
                Divider(height: 1, color: dividerColor),
                
                // 🛡️ NAYA: Permissions & Alerts (Available for both Guest and Logged in)
                _tile(Icons.shield_outlined, "Permissions", "Manage", iconColor, textColor, subTextColor, () {
                  AppHaptics.lightImpact();
                  RidelGlassModal.show(
                    context, 
                    child: const PermissionsCenterSheet()
                  );
                }),

                // Security (Only for logged in users)
                if (!_isGuest) ...[
                  Divider(height: 1, color: dividerColor),
                  _tile(Icons.security, "Security", "", iconColor, textColor, subTextColor, () => RidelSheet.show(context, title: "Security", showBackButton: true, child: const SecuritySheetContent())),
                ]
            ])),

            // 🔥 Increased distance from 30 to 60 as requested
            const SizedBox(height: 60),
            
            // 5. Log Out / Log In Button
            _card(cardColor, isDark, ListTile(
                title: Text(_isGuest ? "Log In" : "Log Out", style: TextStyle(color: _isGuest ? Colors.cyan : Colors.red)), 
                leading: Icon(_isGuest ? Icons.login : Icons.logout, color: _isGuest ? Colors.cyan : Colors.red), 
                onTap: () async { 
                  if (!_isGuest) await Supabase.instance.client.auth.signOut(); 
                  if(mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_)=> const LoginScreen())); 
                }
            )),
            
            const SizedBox(height: 50),
          ]),
        ),
      ),
    );
  }

  Widget _section(String t) => Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(left: 10, bottom: 8), child: Text(t, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))));
  
  Widget _card(Color bgColor, bool isDark, Widget child) => Material(
  color: bgColor,
  borderRadius: BorderRadius.circular(30),
  clipBehavior: Clip.antiAlias, 
  elevation: 0, 
  child: Container(
    decoration: BoxDecoration(
      border: Border.all(
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05), 
        width: 1
      ),
    ),
    child: child,
    ),
  );
  
  Widget _row(String label, String val, Color textColor, Color subColor, {bool readOnly = false, bool isLink = false, VoidCallback? onTap}) => ListTile(title: Text(label, style: TextStyle(color: textColor, fontSize: 14)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(val, style: TextStyle(color: isLink ? Colors.cyan : subColor, fontSize: 14)), if(isLink) Icon(Icons.chevron_right, color: subColor, size: 16)]), onTap: onTap);
  Widget _tile(IconData icon, String title, String sub, Color iconColor, Color textColor, Color subColor, VoidCallback onTap) => ListTile(leading: Icon(icon, color: iconColor), title: Text(title, style: TextStyle(color: textColor)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(sub, style: TextStyle(color: subColor)), Icon(Icons.chevron_right, color: subColor, size: 16)]), onTap: onTap);
}