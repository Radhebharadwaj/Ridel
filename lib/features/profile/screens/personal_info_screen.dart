import 'package:flutter/material.dart';
import 'dart:ui'; // For BackdropFilter
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:image_picker/image_picker.dart';
import 'dart:io'; // Needed for File checks on mobile
import 'package:ridel/features/profile/services/profile_repository.dart';
import 'package:ridel/features/profile/widgets/editable_profile_field.dart';
import 'package:image_cropper/image_cropper.dart';

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
  bool _isCropping = false;
  
  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;

  // Initial Data (For Reset)
  Map<String, dynamic>? _initialData;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _emailController = TextEditingController();
    _loadInitialData();
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final data = await widget.repository.getProfile();
      if (mounted) {
        setState(() {
          _initialData = data;
          _nameController.text = data?['full_name'] ?? '';
          _phoneController.text = data?['phone_primary'] ?? '';
          _emailController.text = data?['email'] ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleEditMode() {
    if (_isGlobalEditing) {
      // Cancel Edit - Reset Data to initial state
      if (_initialData != null) {
        _nameController.text = _initialData!['full_name'] ?? '';
        _phoneController.text = _initialData!['phone_primary'] ?? '';
      }
      setState(() => _isGlobalEditing = false);
    } else {
      // Start Edit
      setState(() => _isGlobalEditing = true);
    }
  }

  Future<void> _saveAllDetails() async {
    // Validation
    final phone = _phoneController.text.trim();
    final isDigitsOnly = int.tryParse(phone) != null;
    if (phone.isNotEmpty && (phone.length != 10 || !isDigitsOnly)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Please enter a valid 10-digit mobile number"),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Calling update on repository with Map
      final updatedData = await widget.repository.updateProfile({
        'full_name': _nameController.text.trim(),
        'phone_primary': _phoneController.text.trim(),
      });

      if (mounted) {
        if (updatedData != null) {
           // Success: Return updated data to Profile Screen
           Navigator.pop(context, updatedData);
        } else {
           throw "Update failed";
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Database Update Failed"),
          backgroundColor: Colors.red,
        ));
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

    // Set cropping state for blur effect
    setState(() => _isCropping = true);

    XFile? fileToUpload;

    try {
      if (!kIsWeb) {
        // ✅ MOBILE: Premium Neon + Gesture UI
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: imageFile.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Adjust Photo',
              toolbarColor: Colors.black,
              toolbarWidgetColor: Colors.cyanAccent,
              backgroundColor: Colors.black,
              
              // Neon Colors
              activeControlsWidgetColor: Colors.cyanAccent,
              cropFrameColor: Colors.cyanAccent,
              cropGridColor: Colors.cyanAccent.withOpacity(0.4),
              dimmedLayerColor: Colors.black.withOpacity(0.8),

              // ✨ SMART GESTURES (Hidden Slider)
              hideBottomControls: true,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
            ),
            IOSUiSettings(
              title: 'Adjust Photo',
              hidesNavigationBar: true,
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
              aspectRatioPickerButtonHidden: true,
              doneButtonTitle: "DONE",
              cancelButtonTitle: "CANCEL",
            ),
          ],
        );

        if (croppedFile != null) {
          fileToUpload = XFile(croppedFile.path);
        }
      } else {
        // ✅ WEB: Safe Minimal UI (Prevents Crash)
        // Web doesn't support the custom neon theme parameters, so we use defaults.
        try {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: imageFile.path,
            uiSettings: [
              WebUiSettings(
                context: context,
                // Minimal settings to ensure stability on Chrome
              ),
            ],
          );
          if (croppedFile != null) {
            fileToUpload = XFile(croppedFile.path);
          }
        } catch (e) {
          debugPrint("Web cropper error: $e");
          // Fallback: Use original image if cropper fails on web
          fileToUpload = imageFile;
        }
      }
    } finally {
      // Remove blur effect
      setState(() => _isCropping = false);
    }

    // If user cancelled, stop here
    if (fileToUpload == null) return;

    // Upload Logic
    try {
      final newAvatarUrl = await widget.repository.uploadAvatar(fileToUpload);
      
      if (newAvatarUrl != null) {
        final updatedData = await widget.repository.updateProfile({'avatar_url': newAvatarUrl});
        
        if (mounted) {
          setState(() {
            _initialData = updatedData;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Profile picture updated!"),
            backgroundColor: Colors.green,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Upload Failed"),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialData == null && _isLoading) {
       return const Scaffold(
         backgroundColor: Colors.black,
         body: Center(child: CircularProgressIndicator(color: Colors.cyan))
       );
    }
    
    // Fail case
    if (_initialData == null) {
       return Scaffold(
         backgroundColor: Colors.black,
         appBar: AppBar(backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.white)),
         body: Center(child: Text("Failed to load profile", style: TextStyle(color: Colors.white)))
       );
    }

    final String avatarUrl = _initialData!['avatar_url'] ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () {
            if (_isGlobalEditing) {
               _toggleEditMode(); // Cancel Logic
            } else {
               Navigator.pop(context, _initialData); // Back Logic
            }
          },
          child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white.withOpacity(0.1)),
              child: Icon(_isGlobalEditing ? Icons.close : Icons.arrow_back, color: Colors.white)),
        ),
        title: const Text("Personal Info",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Stack(
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
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Icon(Icons.edit,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text("Edit your details to unlock Neon Profile",
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 40),
                
                // Fields
                EditableProfileField(
                    label: "Full Name",
                    initialValue: "", // Controlled via controller
                    icon: Icons.person,
                    dbKey: 'full_name',
                    isEnabled: _isGlobalEditing,
                    controller: _nameController),
                const SizedBox(height: 20),

                Opacity(
                  opacity: 0.6,
                  child: EditableProfileField(
                      label: "Email Address",
                      initialValue: "", 
                      icon: Icons.email,
                      dbKey: 'email',
                      isEnabled: false,
                      isReadOnly: true,
                      controller: _emailController), 
                ),

                const SizedBox(height: 20),
                EditableProfileField(
                    label: "Mobile Number",
                    initialValue: "",
                    icon: Icons.phone_iphone,
                    dbKey: 'phone_primary',
                    isEnabled: _isGlobalEditing,
                    controller: _phoneController),
                
                const SizedBox(height: 100), 
              ],
            ),
          ),
          
          if (_isGlobalEditing)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveAllDetails,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 5,
                ),
                child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text("SAVE DETAILS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            
            // Blur Layer for Cropping/Loading State
            if (_isCropping)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: Colors.cyanAccent,
                        ),
                        SizedBox(height: 20),
                        Text(
                          "Updating Profile...",
                          style: TextStyle(
                            color: Colors.cyanAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16
                          ),
                        )
                      ],
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