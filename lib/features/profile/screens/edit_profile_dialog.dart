import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/features/profile/services/profile_repository.dart';
import 'package:ridel/core/widgets/branded_loader.dart';

class EditProfileContent extends StatefulWidget {
  const EditProfileContent({
    required this.initialData,
    required this.onDraftSaved,
    super.key,
  });

  final Map<String, dynamic>? initialData;
  final Function(String name, String userId, XFile? image) onDraftSaved;

  @override
  State<EditProfileContent> createState() => _EditProfileContentState();
}

class _EditProfileContentState extends State<EditProfileContent> {
  late TextEditingController _nameCtrl;
  late TextEditingController _userIdCtrl;
  XFile? _pickedImage;

  Timer? _debounce;
  bool _isCheckingHandle = false;
  bool? _isHandleAvailable;
  bool _isHandleLocked = false;
  int _lockDaysLeft = 0;
  String? _handleErrorText; // 🚀 NAYA: Specific error dikhane ke liye

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: (widget.initialData?['full_name'] as String?) ?? '');
    final currentHandle =
        (widget.initialData?['custom_user_id'] as String?) ?? '';
    _userIdCtrl = TextEditingController(text: currentHandle);

    final lastUpdate = widget.initialData?['handle_updated_at'];
    if (lastUpdate != null) {
      final updateDate = DateTime.parse(lastUpdate as String);
      final diff = DateTime.now().difference(updateDate).inDays;
      if (diff < 15) {
        _isHandleLocked = true;
        _lockDaysLeft = 15 - diff;
      }
    }

    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _userIdCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // 🚀 UPDATED: Strict Handle Rules
  void _onHandleChanged(String value) {
    if (_isHandleLocked) return;

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    setState(() {
      _isCheckingHandle = true;
      _isHandleAvailable = null;
      _handleErrorText = null;
    });

    _debounce = Timer(const Duration(milliseconds: 800), () async {
      final handle = value.trim();

      // RULE 1: Minimum 5 Characters
      if (handle.length < 5) {
        setState(() {
          _isCheckingHandle = false;
          _isHandleAvailable = false;
          _handleErrorText = 'Min 5 characters';
        });
        return;
      }

      // RULE 2: Only a-z, 0-9, and _
      final RegExp handleRegex = RegExp(r'^[a-z0-9_]+$');
      if (!handleRegex.hasMatch(handle)) {
        setState(() {
          _isCheckingHandle = false;
          _isHandleAvailable = false;
          _handleErrorText = 'Only a-z, 0-9, _';
        });
        return;
      }

      // RULE 3: Database Availability Check
      final isAvailable = await ProfileRepository()
          .isHandleAvailable(handle, ProfileRepository().userId ?? '');

      if (mounted) {
        setState(() {
          _isCheckingHandle = false;
          _isHandleAvailable = isAvailable;
          if (!isAvailable) _handleErrorText = 'Taken';
        });

        if (isAvailable) {
          AppHaptics.success();
        } else {
          AppHaptics.error();
        }
      }
    });
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'U';
    final parts = name.trim().split(' ');
    if (parts.length > 1) return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
    return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : 'U';
  }

  Future<void> _pickImage() async {
    AppHaptics.lightImpact();
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      if (kIsWeb) {
        if (!mounted) return;
        setState(() => _pickedImage = image);
        AppHaptics.success();
      } else {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
                toolbarTitle: 'Crop Photo',
                toolbarColor: Colors.black,
                toolbarWidgetColor: Colors.white,
                backgroundColor: Colors.black,
                activeControlsWidgetColor: Colors.cyan,
                lockAspectRatio: true),
            IOSUiSettings(title: 'Crop Photo', aspectRatioLockEnabled: true),
          ],
        );
        if (croppedFile != null) {
          if (!mounted) return;
          setState(() => _pickedImage = XFile(croppedFile.path));
          AppHaptics.success();
        }
      }
    }
  }

  void _saveChanges() {
    final name = _nameCtrl.text.trim();
    final userId = _userIdCtrl.text.trim();

    if (name.length < 3) {
      AppHaptics.error();
      ToastService.showError(context, 'Name must be at least 3 characters.');
      return;
    }

    if (_isHandleAvailable == false) {
      AppHaptics.error();
      ToastService.showError(context, 'Please enter a valid User ID.');
      return;
    }

    AppHaptics.buttonClick();
    widget.onDraftSaved(name, userId, _pickedImage);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final currentAvatar = widget.initialData?['avatar_url'] as String?;

    // 🚀 FIXED: Removed double 'viewInsets' padding. Just pure ScrollView.
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.cyan.withValues(alpha: 0.5), width: 2)),
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    backgroundImage: _pickedImage != null
                        ? (kIsWeb
                            ? NetworkImage(_pickedImage!.path)
                            : FileImage(File(_pickedImage!.path))
                                as ImageProvider)
                        : (currentAvatar != null && currentAvatar.isNotEmpty
                            ? NetworkImage(currentAvatar)
                            : null),
                    child: (_pickedImage == null &&
                            (currentAvatar == null || currentAvatar.isEmpty))
                        ? Text(_getInitials(_nameCtrl.text),
                            style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold))
                        : null,
                  ),
                ),
                Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: Colors.cyan,
                        shape: BoxShape.circle,
                        border: Border.all(width: 2)),
                    child: const Icon(Icons.camera_alt,
                        color: Colors.black, size: 14)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildNameField(),
          const SizedBox(height: 16),
          _buildHandleField(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: (_isCheckingHandle || _isHandleAvailable == false)
                  ? null
                  : _saveChanges,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      Colors.cyan.withValues(alpha: 0.2), // Faded when disabled
                  disabledForegroundColor: Colors.white54,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100))),
              child: Text('Confirm Details',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              AppHaptics.lightImpact();
              Navigator.pop(context);
            },
            child: Text('Maybe later',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text('Full Name',
                style: GoogleFonts.inter(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w600))),
        TextField(
          controller: _nameCtrl,
          maxLength: 20,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              counterText: '',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(100),
                  borderSide: BorderSide.none)),
        ),
      ],
    );
  }

  Widget _buildHandleField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('User ID Handle',
                  style: GoogleFonts.inter(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              if (_isHandleLocked)
                Text('Changeable in $_lockDaysLeft days',
                    style: GoogleFonts.inter(
                        color: Colors.orangeAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        TextField(
          controller: _userIdCtrl,
          onChanged: _onHandleChanged,
          enabled: !_isHandleLocked,
          style:
              TextStyle(color: _isHandleLocked ? Colors.white38 : Colors.white),
          decoration: InputDecoration(
            hintText: '@username',
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(100),
                borderSide: BorderSide.none),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isCheckingHandle)
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: BrandedLoader(isFullScreen: false))
                  else if (_isHandleAvailable == true)
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.greenAccent, size: 20)
                  else if (_isHandleAvailable == false &&
                      _userIdCtrl.text.isNotEmpty &&
                      !_isHandleLocked)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.5))),
                      child: Text(_handleErrorText ?? 'Taken',
                          style: GoogleFonts.inter(
                              color: Colors.redAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
