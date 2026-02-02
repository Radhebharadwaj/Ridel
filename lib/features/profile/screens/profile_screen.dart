import 'dart:io';
import 'dart:math';
import '../services/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; 
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/auth/screens/login_screen.dart';
import 'package:ridel/features/profile/widgets/smart_pass_card.dart';
import 'package:image_cropper/image_cropper.dart';
import '../widgets/premium_avatar_dialog.dart';
import 'personal_info_screen.dart';
import 'security_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final ProfileRepository _repo;
  
  // Logic Variables
  Map<String, dynamic>? _profileData;
  bool _isNeonActive = false; // ✨ Logic for Glow
  bool _isGuest = false;
  bool _isLoading = true;

  Color _parseColor(String? hexCode) {
    try {
      if (hexCode == null || hexCode.toString().toLowerCase() == 'nan' || hexCode.isEmpty) {
        return Colors.cyan; // Default neon color
      }
      final buffer = StringBuffer();
      if (hexCode.length == 6 || hexCode.length == 7) buffer.write('ff');
      buffer.write(hexCode.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      return Colors.cyan; // Fallback
    }
  }

  // Animation
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _repo = ProfileRepository();
    _initAnimations();
    _checkUserAndLoadData();
  }

  void _initAnimations() {
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.0, end: 25.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  Future<void> _checkUserAndLoadData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isGuest = true;
          _isNeonActive = false;
          _isLoading = false;
        });
      }
      _glowController.stop();
    } else {
      await _loadData();
    }
  }

  Future<void> _loadData() async {
    try {
      final data = await _repo.getProfile();
      
      // Zombie User Check: If user exists in Auth but profile is deleted/null
      if (data == null) {
        debugPrint("Profile missing, logging out...");
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          _profileData = data;
          _isNeonActive = data['is_profile_completed'] ?? false;
          _isLoading = false;
        });
        
        if (!_isNeonActive) {
          _glowController.stop();
          _glowController.value = 0;
        } else {
          _glowController.repeat(reverse: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Silently fail or show snackbar if needed, but for profile load just stop loading
      }
    }
  }

  // --- 📸 IMAGE PICKER & UPLOAD LOGIC ---
  Future<void> _pickAndUploadAvatar() async {
    if (_isGuest) return; // Prevent guest from uploading avatar

    AppHaptics.heavyImpact();
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600, // Resize for faster uploads
      maxHeight: 600,
      imageQuality: 85, // Compress image
    );

    if (pickedFile == null) return;

    XFile? fileToUpload = pickedFile;

    if (!kIsWeb) {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Edit Photo',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            backgroundColor: Colors.black,
          ),
          IOSUiSettings(
            title: 'Edit Photo',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );
      
      if (croppedFile != null) {
        fileToUpload = XFile(croppedFile.path);
      } else {
        // User cancelled cropping
        return;
      }
    }

    try {
      final newAvatarUrl = await _repo.uploadAvatar(fileToUpload);
      await _repo.updateProfile({'avatar_url': newAvatarUrl});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Profile picture updated!"),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Upload failed: ${e.toString()}"),
          backgroundColor: Colors.red,
        ));
      }
    }
  }


  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _openPersonalInfo(Map<String, dynamic> profileData) async {
    AppHaptics.mediumImpact();
    // Wait for the result from PersonalInfoScreen
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, sec) => PersonalInfoScreen(
          repository: _repo
        ),
        transitionsBuilder: (context, anim, sec, child) {
          return SlideTransition(
            position: anim.drive(Tween(begin: const Offset(1, 0), end: Offset.zero).chain(CurveTween(curve: Curves.fastOutSlowIn))),
            child: child
          );
        },
      ),
    );

    // If we got updated data map back
    if (result != null && result is Map<String, dynamic>) {
        setState(() {
           _profileData = result;
           _isNeonActive = result['is_profile_completed'] ?? false;
        });
        
        if (!_isNeonActive) {
          _glowController.stop();
          _glowController.value = 0;
        } else {
          _glowController.repeat(reverse: true);
        }
    } else {
       // Fallback: If returned null but we suspect changes or just to be safe (though ideally we rely on returned data)
       // For now, only update if data is returned to avoid blink.
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isGuest) {
      return _buildGuestUI();
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }
    
    if (_profileData == null || _profileData!.isEmpty) {
        return const Center(child: Text('No profile data found.', style: TextStyle(color: Colors.white)));
    }

    return _buildProfileUI(_profileData!);
  }

  Widget _buildProfileUI(Map<String, dynamic> profileData) {
    final String userName = profileData['full_name'] ?? 'Traveler';
    final String userPhone = profileData['phone_primary'] ?? 'Complete Profile to Unlock';
    final String avatarUrl = profileData['avatar_url'] ?? '';
    final bool hasAvatar = avatarUrl.isNotEmpty;
    final Color profileColor = _parseColor(profileData['color_hex']);

    final Widget avatarWidget = hasAvatar
        ? CircleAvatar(
            radius: 35,
            backgroundColor: const Color(0xFF1A1A1A),
            backgroundImage: NetworkImage(avatarUrl),
          )
        : const Icon(Icons.account_circle, size: 70, color: Colors.grey);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Glow
          Positioned(
            top: -80, right: -80,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                boxShadow: [
                  BoxShadow(
                    color: (_isNeonActive ? profileColor : Colors.blueAccent).withOpacity(0.15),
                    blurRadius: 150,
                    spreadRadius: 50,
                  )
                ]
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  
                  // --- HEADER (With Neon Logic) ---
                  Row(
                    children: [
                      RepaintBoundary(
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (hasAvatar) {
                                  showDialog(
                                    context: context,
                                    builder: (context) => PremiumAvatarDialog(imageUrl: avatarUrl),
                                  );
                                }
                              },
                              child: Hero(
                                tag: 'profileAvatar',
                                child: AnimatedBuilder(
                                  animation: _glowAnimation,
                                  builder: (context, child) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        boxShadow: _isNeonActive ? [
                                          BoxShadow(
                                            color: profileColor.withOpacity(0.4),
                                            blurRadius: _glowAnimation.value,
                                            spreadRadius: 2,
                                          )
                                        ] : [], // No Glow if not complete
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _isNeonActive ? profileColor : Colors.grey.withOpacity(0.3),
                                            width: 2
                                          ),
                                        ),
                                        child: hasAvatar ? avatarWidget : CircleAvatar(
                                            radius: 35,
                                            backgroundColor: const Color(0xFF1A1A1A),
                                            child: avatarWidget, // Show the default icon/placeholder
                                          ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(userName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            const SizedBox(height: 6),
                            Text(userPhone, style: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 35),

                  // --- SMART PASS ---
                  _buildTravelPass(profileData),

                  const SizedBox(height: 35),

                  // --- PREFERENCES ---
                  _buildSectionTitle("Preferences"),
                  _buildMenuTile(
                    icon: Icons.person_outline_rounded, 
                    title: "Personal Info", 
                    subtitle: "Name, Email & Mobile",
                    onTap: () => _openPersonalInfo(profileData), 
                  ),
                  _buildMenuTile(
                    icon: Icons.notifications_none_rounded,
                    title: "Notifications",
                    subtitle: "Ride alerts & offers",
                    onTap: (){ AppHaptics.lightImpact(); }
                  ),
                  _buildMenuTile(
                    icon: Icons.security_rounded,
                    title: "Security & Privacy",
                    subtitle: "App Lock, PIN & Biometrics",
                    onTap: (){
                      AppHaptics.mediumImpact();
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const SecurityScreen()));
                    }
                  ),

                  const SizedBox(height: 30),

                  // --- LOGOUT BUTTON ---
                  _buildSectionTitle("Account"),
                     _buildMenuTile(
                      icon: Icons.logout_rounded, 
                      title: "Log Out", 
                      subtitle: "Sign out of Ridel", 
                       onTap: () async {
                        AppHaptics.heavyImpact();
                        await Supabase.instance.client.auth.signOut();
                        if (mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (context) => const LoginScreen()),
                            (route) => false
                          );
                        }
                      }
                    ),
                  
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildGuestUI() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Row(
                children: [
                  const CircleAvatar(
                    radius: 35,
                    backgroundColor: Color(0xFF1A1A1A),
                    child: Icon(Icons.account_circle, size: 70, color: Colors.grey),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Guest User', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        const SizedBox(height: 6),
                        Text('Sign in to access all features', style: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const LoginScreen()),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: const Text("Login / Sign Up", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 35),
              _buildTravelPass(null),
              const SizedBox(height: 35),
              _buildSectionTitle("Preferences"),
              _buildMenuTile(
                icon: Icons.person_outline_rounded, 
                title: "Personal Info", 
                subtitle: "Name, Email & Mobile",
                onTap: () {}, 
              ),
              _buildMenuTile(
                icon: Icons.notifications_none_rounded, 
                title: "Notifications", 
                subtitle: "Ride alerts & offers", 
                onTap: (){ AppHaptics.lightImpact(); }
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildTravelPass(Map<String, dynamic>? profileData) {
    return SmartPassCard(profileData: profileData);
  }
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(title.toUpperCase(), style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
    );
  }

  Widget _buildMenuTile({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: const Color(0xFF131313),
          child: InkWell(
            onTap: onTap,
            splashColor: Colors.white.withOpacity(0.15),
            highlightColor: Colors.white.withOpacity(0.05),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withOpacity(0.05)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey.shade800, size: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
