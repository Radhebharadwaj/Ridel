import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ridel/core/services/identity_service.dart';
import 'package:ridel/core/services/phone_verification_service.dart';
import 'package:ridel/features/profile/services/profile_repository.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:intl/intl.dart';
import 'package:ridel/core/utils/toast_service.dart';

class PersonalInfoScreen extends StatefulWidget {
  final ProfileRepository repository;

  const PersonalInfoScreen({super.key, required this.repository});

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  // Global Editing State
  bool _isGlobalEditing = false;
  bool _isLoading = false;
  bool _isLocationLoading = false;
  bool _isCropping = false;

  // Controllers for Editable Fields
  late TextEditingController _nameController;
  late TextEditingController _secondaryPhoneController;
  DateTime? _selectedDob;
  String? _selectedGender;

  // Initial Data
  Map<String, dynamic>? _initialData;

  // Services
  final IdentityService _identityService = IdentityService();
  final PhoneVerificationService _verificationService = PhoneVerificationService();

  // CONSTANTS
  final double kTileHeight = 72.0; // ✅ Increased height for better touch targets

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _secondaryPhoneController = TextEditingController();
    _loadInitialData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _secondaryPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final data = await widget.repository.getProfile();
      if (mounted) {
        setState(() {
          _initialData = data;
          _populateFields(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateFields(Map<String, dynamic>? data) {
    if (data == null) return;
    _nameController.text = data['full_name'] ?? '';
    _secondaryPhoneController.text = data['phone_secondary'] ?? '';
    
    if (data['dob'] != null && data['dob'].isNotEmpty) {
      try {
        _selectedDob = DateTime.parse(data['dob']);
      } catch (_) {}
    }
    // "Prefer not to say" ko handle karne ke liye
    _selectedGender = data['gender'];
  }

  void _toggleEditMode() {
    if (_isGlobalEditing) {
      // Cancel Edit - Reset to initial data
      if (_initialData != null) {
        _populateFields(_initialData);
      }
      setState(() => _isGlobalEditing = false);
    } else {
      // Start Edit
      setState(() => _isGlobalEditing = true);
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    if (!_isGlobalEditing) return;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.cyan,
              onPrimary: Colors.black,
              surface: Color(0xFF1A1A1A),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Colors.black,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDob = picked);
    }
  }

  // ✅ Clear Date (Prefer not to say)
  void _clearDate() {
    setState(() => _selectedDob = null);
  }

  // --- SMART LOCATION LOGIC ---
  Future<void> _handleSmartLocation() async {
    setState(() => _isLocationLoading = true);

    try {
      final locationInfo = await _identityService.getLocationInfo();
      
      if (locationInfo['current_city'] != null) {
          final updatedData = await widget.repository.updateProfile({
            'current_city': locationInfo['current_city'],
            'state_code': locationInfo['state_code'],
            'country_code': locationInfo['country_code'],
          });

          if (mounted) {
            setState(() {
              _initialData = updatedData;
              _isLocationLoading = false;
            });
            ToastService.showSuccess(context, "Location Detected & Saved!");
          }
      } else {
          throw "Could not fetch address details.";
      }

    } catch (e) {
      if (mounted) {
        setState(() => _isLocationLoading = false);
        ToastService.showError(context, "$e");
      }
    }
  }

  Future<void> _saveAllDetails() async {
    setState(() => _isLoading = true);

    try {
      final updates = {
        'full_name': _nameController.text.trim(),
        'phone_secondary': _secondaryPhoneController.text.trim().isNotEmpty
            ? _secondaryPhoneController.text.trim()
            : null,
        // Save null if DOB is not selected (Prefer not to say)
        'dob': _selectedDob != null ? DateFormat('yyyy-MM-dd').format(_selectedDob!) : null,
        'gender': _selectedGender,
      };

      final updatedData = await widget.repository.updateProfile(updates);

      if (mounted) {
        if (updatedData != null) {
           setState(() {
             _initialData = updatedData;
             _isGlobalEditing = false;
             _isLoading = false;
           });
           ToastService.showInfo(context, "Profile Updated Successfully!");
        } else {
           throw "Update failed";
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastService.showError(context, "Database Update Failed");
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final imageFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 90,
    );

    if (imageFile == null) return;

    setState(() => _isCropping = true);
    XFile? fileToUpload;

    try {
      if (!kIsWeb) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: imageFile.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Adjust Photo',
              toolbarColor: Colors.black,
              toolbarWidgetColor: Colors.cyanAccent,
              backgroundColor: Colors.black,
              activeControlsWidgetColor: Colors.cyanAccent,
              cropFrameColor: Colors.cyanAccent,
              cropGridColor: Colors.cyanAccent.withOpacity(0.4),
              dimmedLayerColor: Colors.black.withOpacity(0.8),
              hideBottomControls: true,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
            ),
            IOSUiSettings(
              title: 'Adjust Photo',
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
              doneButtonTitle: "DONE",
              cancelButtonTitle: "CANCEL",
            ),
          ],
        );
        if (croppedFile != null) fileToUpload = XFile(croppedFile.path);
      } else {
        fileToUpload = imageFile;
      }
    } finally {
      setState(() => _isCropping = false);
    }

    if (fileToUpload == null) return;

    try {
      final newAvatarUrl = await widget.repository.uploadAvatar(fileToUpload);
      if (newAvatarUrl != null) {
        final updatedData = await widget.repository.updateProfile({'avatar_url': newAvatarUrl});
        if (mounted) {
          setState(() => _initialData = updatedData);
          ToastService.showSuccess(context, "Profile picture updated!");
        }
      }
    } catch (e) {
      if (mounted) {
        ToastService.showError(context, "Upload Failed");
      }
    }
  }

  Future<void> _handlePhoneVerification() async {
    final bool isVerified = _initialData!['phone_primary'] != null &&
                             _initialData!['phone_primary'].toString().isNotEmpty;
    
    if (isVerified) return;

    setState(() => _isLoading = true);
    
    try {
      final verifiedNumber = await _verificationService.startVerification(context);
      
      if (verifiedNumber != null && verifiedNumber.isNotEmpty) {
        // Update phone_primary in Supabase
        final updatedData = await widget.repository.updateProfile({
          'phone_primary': verifiedNumber,
          'is_verified': true,
        });

        if (mounted) {
          setState(() {
            _initialData = updatedData;
            _isLoading = false;
          });
          ToastService.showSuccess(context, "Phone Verified Successfully!");
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastService.showError(context, "Verification Error: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialData == null && _isLoading) {
       return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.cyan)));
    }
    
    if (_initialData == null) {
       return const Scaffold(backgroundColor: Colors.black, body: Center(child: Text("Failed to load profile", style: TextStyle(color: Colors.white))));
    }

    final String avatarUrl = _initialData!['avatar_url'] ?? '';
    final String email = _initialData!['email'] ?? 'No Email';
    
    final String city = _initialData!['current_city'] ?? '';
    final String state = _initialData!['state_code'] ?? '';
    final String country = _initialData!['country_code'] ?? '';
    final String fullAddress = [city, state, country].where((s) => s.isNotEmpty).join(", ");
    final String displayAddress = fullAddress.isNotEmpty ? fullAddress : "Tap to detect location";

    return Scaffold(
      backgroundColor: Colors.black, // ✅ Solid Black Background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context, _initialData),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.1)),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
        title: const Text("Personal Info", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          if (!_isGlobalEditing)
            IconButton(
              onPressed: _toggleEditMode,
              icon: const Icon(Icons.edit, color: Colors.cyan),
            )
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            // ✅ Extra Bottom Padding to prevent overflow behind floating button
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                          radius: 50,
                          backgroundColor: const Color(0xFF1A1A1A),
                          backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                      ),
                      GestureDetector(
                        onTap: _pickAndUploadAvatar,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.cyan,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: const Icon(Icons.edit, color: Colors.black, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 35),

                // --- SECTION A: VERIFIED IDENTITY ---
                _buildSectionTitle("VERIFIED IDENTITY"),
                _buildVerifiedTile(
                  label: "Primary Mobile",
                  value: (_initialData!['phone_primary'] != null && _initialData!['phone_primary'].toString().isNotEmpty)
                      ? _initialData!['phone_primary']
                      : 'Unverified',
                  icon: Icons.phone_iphone_rounded,
                  isVerified: _initialData!['phone_primary'] != null && _initialData!['phone_primary'].toString().isNotEmpty,
                  valueColor: (_initialData!['phone_primary'] != null && _initialData!['phone_primary'].toString().isNotEmpty)
                      ? Colors.white
                      : Colors.redAccent,
                  onTap: _handlePhoneVerification,
                ),
                _buildVerifiedTile(
                  label: "Travel ID",
                  value: _initialData!['travel_id'] ?? 'N/A',
                  icon: Icons.badge_rounded,
                  isVerified: false
                ),

                const SizedBox(height: 30),

                // --- SECTION B: SMART LOCATION ---
                _buildSectionTitle("SMART LOCATION"),
                GestureDetector(
                  onTap: _isLocationLoading ? null : _handleSmartLocation,
                  child: Container(
                    height: kTileHeight, // ✅ Fixed Height
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131313),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                      boxShadow: [
                         BoxShadow(color: Colors.cyan.withOpacity(0.05), blurRadius: 10, spreadRadius: 0)
                      ]
                    ),
                    child: Row(
                      children: [
                        if (_isLocationLoading)
                          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyan))
                        else
                          const Icon(Icons.gps_fixed_rounded, color: Colors.cyan, size: 22),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Current Address", style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text(
                                displayAddress,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.refresh_rounded, color: Colors.grey, size: 20),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // --- SECTION C: PERSONAL DETAILS ---
                _buildSectionTitle("PERSONAL DETAILS"),

                // Full Name
                _buildEditableContainer(
                  icon: Icons.person_rounded,
                  label: "Full Name",
                  child: TextField(
                    controller: _nameController,
                    enabled: _isGlobalEditing,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: "Enter your name",
                      hintStyle: TextStyle(color: Colors.grey),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Email
                _buildEditableContainer(
                  icon: Icons.email_rounded,
                  label: "Email",
                  child: Text(
                    email,
                    style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),

                const SizedBox(height: 12),
                
                // Secondary Mobile
                _buildEditableContainer(
                  icon: Icons.phone_android_rounded,
                  label: "Secondary Mobile",
                  child: TextField(
                    controller: _secondaryPhoneController,
                    enabled: _isGlobalEditing,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: "Emergency Contact",
                      hintStyle: TextStyle(color: Colors.grey),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),

                // Date of Birth
                GestureDetector(
                  onTap: () => _pickDate(context),
                  child: _buildEditableContainer(
                    icon: Icons.cake_rounded,
                    label: "Date of Birth",
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedDob != null 
                              ? DateFormat('dd MMM yyyy').format(_selectedDob!) 
                              : "Prefer not to say", // ✅ Updated default text
                            style: TextStyle(
                              color: _selectedDob != null ? Colors.white : Colors.grey,
                              fontWeight: FontWeight.w600,
                              fontSize: 14
                            ),
                          ),
                        ),
                        if (_isGlobalEditing) 
                          // ✅ Added 'Clear' option to enable "Prefer not to say" selection
                          _selectedDob != null 
                            ? GestureDetector(
                                onTap: _clearDate,
                                child: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                              )
                            : const Icon(Icons.calendar_today, color: Colors.cyan, size: 16),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Gender
                _buildEditableContainer(
                  icon: Icons.wc_rounded,
                  label: "Gender",
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedGender,
                      hint: const Text("Select Gender", style: TextStyle(color: Colors.grey, fontSize: 14)),
                      dropdownColor: const Color(0xFF1A1A1A),
                      icon: _isGlobalEditing ? const Icon(Icons.arrow_drop_down, color: Colors.cyan) : const SizedBox.shrink(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      isExpanded: true, 
                      isDense: true, // ✅ Fixes vertical overflow
                      onChanged: _isGlobalEditing ? (val) => setState(() => _selectedGender = val) : null,
                      // ✅ Added "Prefer not to say" option
                      items: ['Male', 'Female', 'Other', 'Prefer not to say'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Save Button (Floating)
          if (_isGlobalEditing)
            Positioned(
              bottom: 30, left: 20, right: 20,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveAllDetails,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 10,
                  shadowColor: Colors.cyan.withOpacity(0.4),
                ),
                child: _isLoading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5))
                  : const Text("SAVE CHANGES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
              ),
            ),
            
            // Cropping Overlay
            if (_isCropping)
             Positioned.fill(
               child: BackdropFilter(
                 filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                 child: Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator(color: Colors.cyan))),
               ),
             ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
    );
  }

  // ✅ IMPROVED TILE UI: Equal Height & Better Alignment
  Widget _buildVerifiedTile({
    required String label,
    required String value,
    required IconData icon,
    required bool isVerified,
    Color? valueColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: kTileHeight, // ✅ Fixed Height
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF131313),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey.shade600, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(color: valueColor ?? Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (isVerified)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.5))
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 12),
                  SizedBox(width: 4),
                  Text("Verified", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ IMPROVED EDITABLE CONTAINER: Equal Height & Alignment
  Widget _buildEditableContainer({required IconData icon, required String label, required Widget child}) {
    return Container(
      height: kTileHeight, // ✅ Fixed Height
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF131313),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isGlobalEditing ? Colors.cyan.withOpacity(0.5) : Colors.white.withOpacity(0.05),
        ),
        boxShadow: _isGlobalEditing ? [
          BoxShadow(
            color: Colors.cyan.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 0,
          )
        ] : [],
      ),
      child: Row(
        children: [
          Icon(icon, color: _isGlobalEditing ? Colors.cyan : Colors.grey.shade600, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isGlobalEditing) 
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                  ),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}