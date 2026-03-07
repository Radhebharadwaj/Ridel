import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import '../services/profile_repository.dart';

class EditProfileContent extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final ProfileRepository repository;
  final VoidCallback onSaved;

  const EditProfileContent({super.key, required this.initialData, required this.repository, required this.onSaved});

  @override
  State<EditProfileContent> createState() => _EditProfileContentState();
}

class _EditProfileContentState extends State<EditProfileContent> {
  late TextEditingController _nameCtrl;
  late TextEditingController _userIdCtrl; // ✅ Renamed for clarity
  bool _isLoading = false;
  XFile? _pickedImage;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialData?['full_name'] ?? '');
    // ✅ Load existing user_id_custom (Handle)
    _userIdCtrl = TextEditingController(text: widget.initialData?['user_id_custom'] ?? '');
  }

  // ✅ Helper for Initials
  String _getInitials(String name) {
    if (name.isEmpty) return "";
    List<String> parts = name.trim().split(' ');
    if (parts.length > 1) {
      return "${parts[0][0]}${parts.last[0]}".toUpperCase();
    }
    return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : "";
  }

  // 📸 PICK & CROP IMAGE
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      if (kIsWeb) {
        setState(() => _pickedImage = image);
      } else {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Photo',
              toolbarColor: Colors.black,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
              hideBottomControls: true,
            ),
            IOSUiSettings(title: 'Crop Photo', aspectRatioLockEnabled: true, resetAspectRatioEnabled: false),
          ],
        );

        if (croppedFile != null) {
          setState(() => _pickedImage = XFile(croppedFile.path));
        }
      }
    }
  }

  Future<void> _saveChanges() async {
    final name = _nameCtrl.text.trim();
    final userId = _userIdCtrl.text.trim(); // ✅ User ID

    // 🛡️ STRICT VALIDATIONS
    if (name.length < 4 || name.length > 20) {
      ToastService.showError(context, "Name must be 4-20 chars");
      return;
    }
    if (userId.isNotEmpty && (userId.length < 4 || userId.length > 15)) {
      ToastService.showError(context, "User ID must be 4-15 chars");
      return;
    }
    // Regex for User ID (Handle)
    if (userId.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_@]+$').hasMatch(userId)) {
      ToastService.showError(context, "User ID: Only letters, numbers, _, @ allowed");
      return;
    }

    AppHaptics.mediumImpact();
    setState(() => _isLoading = true);

    try {
      // 1. Upload Avatar if selected
      if (_pickedImage != null) {
        await widget.repository.uploadAvatar(_pickedImage!);
      }

      // 2. Update Text Fields
      await widget.repository.updateProfile({
        'full_name': name,
        'user_id_custom': userId, // ✅ Saves to correct DB column
      });

      ToastService.showSuccess(context, "Profile updated!");
      widget.onSaved();
      if (mounted) Navigator.pop(context); 
    } catch (e) {
      ToastService.showError(context, "Update failed. Try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? currentAvatar = widget.initialData?['avatar_url'];
    String fullName = _nameCtrl.text;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 📷 AVATAR SECTION
        GestureDetector(
          onTap: _pickImage,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 45, 
                backgroundColor: Colors.white10,
                backgroundImage: _pickedImage != null 
                    ? (kIsWeb ? NetworkImage(_pickedImage!.path) : FileImage(File(_pickedImage!.path)) as ImageProvider) 
                    : (currentAvatar != null && currentAvatar.isNotEmpty ? NetworkImage(currentAvatar) : null),
                // ✅ Initials Logic here too
                child: (_pickedImage == null && (currentAvatar == null || currentAvatar.isEmpty)) 
                    ? Text(
                        _getInitials(fullName),
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                      ) 
                    : null,
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.cyan, shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)),
                child: const Icon(Icons.edit, color: Colors.black, size: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        
        _buildInputField("Name (4-20 chars)", _nameCtrl, maxLength: 20),
        const SizedBox(height: 16),
        // ✅ User ID Field added here
        _buildInputField("User ID (e.g. @radhe)", _userIdCtrl, maxLength: 15),
        const SizedBox(height: 30),

        // SAVE BUTTON
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, 
              foregroundColor: Colors.black, 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
            ),
            child: _isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) 
                : Text("Save Changes", style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 12),
        
        // CANCEL
        GestureDetector(
          onTap: () { AppHaptics.lightImpact(); Navigator.pop(context); },
          child: Padding(padding: const EdgeInsets.all(10), child: Text("Cancel", style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 14, fontWeight: FontWeight.w600))),
        ),
      ],
    );
  }

  Widget _buildInputField(String label, TextEditingController ctrl, {int? maxLength}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 6), child: Text(label, style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.w600))),
        TextField(
          controller: ctrl, 
          style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
          maxLength: maxLength, 
          decoration: InputDecoration(
            filled: true, fillColor: Colors.white.withOpacity(0.08), isDense: true, counterText: "",
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.cyan, width: 1)),
          ),
        ),
      ],
    );
  }
}