import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:ridel/core/services/theme_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/widgets/city_selector_sheet.dart';
import 'package:ridel/core/widgets/ridel_glass_dropdown.dart';
import 'package:ridel/core/widgets/ridel_glass_modal.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/features/auth/screens/login_screen.dart';

import 'package:ridel/features/profile/screens/edit_profile_dialog.dart';
import 'package:ridel/features/profile/screens/mobile_verification_screen.dart';
import 'package:ridel/features/profile/screens/security_screen.dart';
import 'package:ridel/features/profile/services/profile_repository.dart';
import 'package:ridel/features/profile/widgets/permissions_center_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ridel/core/widgets/branded_loader.dart';

class ProfileSheetContent extends StatefulWidget {
  const ProfileSheetContent({super.key});

  @override
  State<ProfileSheetContent> createState() => _ProfileSheetContentState();
}

class _ProfileSheetContentState extends State<ProfileSheetContent> {
  late final ProfileRepository _repo;
  Map<String, dynamic>? _profileData;

  final Map<String, dynamic> _unsavedChanges = {};
  XFile? _draftedImage;

  final TextEditingController _userIdCtrl = TextEditingController();
  String? _email;
  String? _selectedGender;
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
      if (mounted) setState(() => _isGuest = true);
    } else {
      _loadData();
    }
  }

  @override
  void dispose() {
    _userIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final data = await _repo.getProfile();
    if (mounted) {
      setState(() {
        _profileData = data;
        _email = (data?['email'] as String?) ??
            Supabase.instance.client.auth.currentUser?.email;
        _userIdCtrl.text = (data?['custom_user_id'] as String?) ?? '';
        _selectedGender = data?['gender'] as String?;
        if (data?['birthdate'] != null) {
          try {
            _selectedDOB = DateTime.parse(data!['birthdate'] as String);
          } catch (_) {}
        }
        _unsavedChanges.clear();
        _draftedImage = null;
      });
    }
  }

  void _redirectToLogin() {
    AppHaptics.heavyImpact();
    Navigator.pop(context);
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _showGenderMenu(BuildContext targetContext) {
    if (_isGuest) return;
    AppHaptics.sheetInteraction();
    RidelGlassDropdown.show(
      targetContext,
      options: const ['Male', 'Female', 'Prefer not to say'],
      selectedValue: _selectedGender,
      onSelected: (val) {
        setState(() {
          _selectedGender = val;
          _unsavedChanges['gender'] = val;
        });
        AppHaptics.selectionClick();
      },
    );
  }

  void _showDatePicker() {
    if (_isGuest) return;
    AppHaptics.sheetInteraction();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    var tempDate = _selectedDOB ?? DateTime(2000);

    RidelGlassModal.show(
      context,
      height: 350,
      child: Column(
        children: [
          Text('Select Birthdate',
              style: GoogleFonts.inter(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Expanded(
            child: CupertinoTheme(
              data: CupertinoThemeData(
                  brightness: isDark ? Brightness.dark : Brightness.light,
                  textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: GoogleFonts.inter(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 18))),
              child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: tempDate,
                  minimumDate: DateTime(1950),
                  maximumDate: DateTime.now(),
                  onDateTimeChanged: (val) => tempDate = val),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _selectedDOB = tempDate;
                  _unsavedChanges['birthdate'] =
                      DateFormat('yyyy-MM-dd').format(tempDate);
                });
                AppHaptics.selectionClick();
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white : Colors.black,
                  foregroundColor: isDark ? Colors.black : Colors.white),
              child: const Text('Confirm Date'),
            ),
          ),
        ],
      ),
    );
  }

  void _openEditProfile() {
    if (_isGuest) {
      _redirectToLogin();
    } else {
      AppHaptics.sheetInteraction();

      final currentName =
          _unsavedChanges['full_name'] ?? _profileData?['full_name'];
      final currentId =
          _unsavedChanges['custom_user_id'] ?? _profileData?['custom_user_id'];

      RidelGlassModal.show(context,
          child: EditProfileContent(
              initialData: {
                'full_name': currentName,
                'custom_user_id': currentId,
                'avatar_url': _profileData?['avatar_url'],
                'handle_updated_at': _profileData?['handle_updated_at']
              },
              onDraftSaved: (name, userId, image) {
                setState(() {
                  if (image != null) _draftedImage = image;
                  _unsavedChanges['full_name'] = name;
                  _unsavedChanges['custom_user_id'] = userId;
                  _userIdCtrl.text = userId;
                });
                AppHaptics.selectionClick();
              }));
    }
  }

  void _showDeleteAccountSheet() {
    if (_isGuest) return;
    AppHaptics.warning();

    String? selectedReason;
    final TextEditingController feedbackCtrl = TextEditingController();
    bool confirmDelete = false;

    RidelGlassModal.show(
      context,
      height: 460,
      child: StatefulBuilder(builder: (context, setModalState) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Text("Delete Account",
                  style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent)),
              const SizedBox(height: 10),
              const Text(
                "This action will schedule your account for deletion. All your data, saved routes, and preferences will be permanently erased after 7 days.",
                style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              Builder(
                builder: (btnContext) => InkWell(
                  onTap: () {
                    AppHaptics.selectionClick();
                    RidelGlassDropdown.show(
                      btnContext,
                      options: const [
                        'Privacy concerns',
                        'Found a better app',
                        'Not using it enough',
                        'Other'
                      ],
                      selectedValue: selectedReason,
                      onSelected: (val) =>
                          setModalState(() => selectedReason = val),
                    );
                  },
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          selectedReason ?? "Select a reason for leaving",
                          style: TextStyle(
                            color: selectedReason == null
                                ? Colors.grey
                                : Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: feedbackCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Optional feedback...",
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.1),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(100),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(100),
                    borderSide: const BorderSide(color: Colors.cyan),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              CheckboxListTile(
                value: confirmDelete,
                onChanged: (val) => setModalState(() => confirmDelete = val!),
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.redAccent,
                title: const Text(
                  "I understand that this action is irreversible after 7 days.",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: confirmDelete && selectedReason != null
                      ? () {
                          Future.microtask(() async {
                            AppHaptics.heavyImpact();
                            try {
                              await Supabase.instance.client.rpc(
                                'request_account_deletion',
                                params: {
                                  'reason': selectedReason,
                                  'feedback': feedbackCtrl.text.trim(),
                                },
                              );

                              await Supabase.instance.client.auth.signOut();

                              if (!context.mounted) return;
                              Navigator.pop(context);
                              ToastService.showSuccess(context,
                                  "Account deletion scheduled. We're sorry to see you go! 💔");

                              Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const LoginScreen()));
                            } catch (e) {
                              if (!context.mounted) return;
                              debugPrint("Deletion Error: $e");
                              ToastService.showError(context,
                                  "Error requesting deletion. Check your connection.");
                            }
                          });
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    disabledBackgroundColor:
                        Colors.redAccent.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100)),
                    elevation: 0,
                  ),
                  child: const Text("Confirm Deletion",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'U';
    final parts = name.trim().split(' ');
    if (parts.length > 1) return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
    return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : 'U';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white;
    final textColor = theme.textTheme.titleLarge?.color ?? (isDark ? Colors.white : Colors.black);
    final subTextColor = theme.textTheme.bodyMedium?.color ?? (isDark ? Colors.grey : Colors.grey.shade600);
    final iconColor = theme.iconTheme.color ?? (isDark ? Colors.white : Colors.black);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    final displayFName = _isGuest
        ? 'Guest User'
        : (_unsavedChanges['full_name'] ??
            _profileData?['full_name'] ??
            'User');

    final dbAvatar = (_unsavedChanges['avatar_url'] as String?) ??
        (_profileData?['avatar_url'] as String?) ??
        Supabase
            .instance.client.auth.currentUser?.userMetadata?['avatar_url'] ??
        Supabase.instance.client.auth.currentUser?.userMetadata?['picture'] ??
        '';

    return Material(
      color: Colors.transparent,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context)
            .copyWith(scrollbars: false, overscroll: false),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          // Padding top 105 is kept so content flows smoothly under the master RidelSheet header
          padding: const EdgeInsets.fromLTRB(20, 105, 20, 50),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 850),
            switchInCurve: Curves.easeInOutQuart,
            switchOutCurve: Curves.easeInOutQuart,
            child: Column(
              key: ValueKey(theme.brightness),
              children: [
              Container(
                width: 95,
                height: 95,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.cyan.withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyan.withValues(alpha: 0.15),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 45,
                  backgroundColor: cardColor,
                  child: ClipOval(
                    child: SizedBox(
                      width: 90,
                      height: 90,
                      child: _draftedImage != null
                          ? (kIsWeb
                              ? Image.network(_draftedImage!.path,
                                  fit: BoxFit.cover)
                              : Image.file(File(_draftedImage!.path),
                                  fit: BoxFit.cover))
                          : ((!_isGuest && dbAvatar.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: dbAvatar,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => const Center(
                                    child: BrandedLoader(isFullScreen: false),
                                  ),
                                  errorWidget: (context, url, error) => Center(
                                    child: Text(
                                      _getInitials(displayFName),
                                      style: GoogleFonts.inter(
                                          color: textColor,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    _isGuest ? 'G' : _getInitials(displayFName),
                                    style: GoogleFonts.inter(
                                        color: textColor,
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold),
                                  ),
                                )),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(displayFName,
                  style: GoogleFonts.inter(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              TextButton(
                  onPressed: () => Future.microtask(_openEditProfile),
                  child: Text(_isGuest ? 'Log in to Ridel' : 'Edit Profile',
                      style: const TextStyle(
                          color: Colors.cyan, fontWeight: FontWeight.bold))),
              const SizedBox(height: 30),
              if (!_isGuest) ...[
                _section('Account'),
                _card(
                  cardColor,
                  isDark,
                  Theme(
                    data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent,
                        unselectedWidgetColor: iconColor),
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      collapsedShape: const Border(),
                      shape: const Border(),
                      leading: Icon(Icons.person, color: iconColor),
                      title: Text('Personal Info',
                          style: TextStyle(color: textColor)),
                      iconColor: iconColor,
                      collapsedIconColor: iconColor,
                      children: [
                        _row('Email', _email ?? 'Loading...', textColor,
                            subTextColor,
                            readOnly: true),
                        _row(
                            'User ID',
                            _userIdCtrl.text.isEmpty
                                ? 'Set ID'
                                : _userIdCtrl.text,
                            textColor,
                            subTextColor,
                            isLink: true,
                            onTap: (_) => _openEditProfile()),
                        _row(
                            'Birthdate',
                            _selectedDOB != null
                                ? DateFormat('dd MMM yyyy')
                                    .format(_selectedDOB!)
                                : 'Not set',
                            textColor,
                            subTextColor,
                            isLink: true,
                            onTap: (_) => _showDatePicker()),
                        Builder(
                            builder: (tileContext) => _row(
                                'Gender',
                                _selectedGender ?? 'Not set',
                                textColor,
                                subTextColor,
                                isLink: true,
                                onTap: (_) => _showGenderMenu(tileContext))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              _section('Travel'),
              _card(
                cardColor,
                isDark,
                Column(
                  children: [
                    _tile(
                        Icons.phone,
                        'Mobile',
                        _isGuest
                            ? 'Login to verify'
                            : (_profileData?['phone_number'] as String? ??
                                'Unverified'),
                        iconColor,
                        textColor,
                        subTextColor, () {
                      if (_isGuest) {
                        _redirectToLogin();
                      } else {
                        AppHaptics.sheetInteraction();
                        RidelGlassModal.show(context,
                                child:
                                    MobileVerificationModal(repository: _repo))
                            .then((_) => _loadData());
                      }
                    }),
                    Divider(height: 1, color: dividerColor),
                    _tile(
                        Icons.gps_fixed,
                        'City',
                        _isGuest
                            ? (ProfileRepository.userCity.value == 'Locating...'
                                ? 'Select City'
                                : ProfileRepository.userCity.value)
                            : (_profileData?['city'] as String? ?? 'Set'),
                        iconColor,
                        textColor,
                        subTextColor, () {
                      AppHaptics.sheetInteraction();
                      RidelSheet.show(context,
                          title: 'Select City',
                          showBackButton: true,
                          child: const CitySelectorSheet());
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _section('Preferences'),
              _card(
                cardColor,
                isDark,
                Column(
                  children: [
                    ValueListenableBuilder<AppThemeMode>(
                      valueListenable: ThemeService.appThemeNotifier,
                      builder: (context, mode, child) {
                        String currentModeStr = 'System';
                        if (mode == AppThemeMode.dark) currentModeStr = 'Dark';
                        if (mode == AppThemeMode.light) currentModeStr = 'Light';
                        if (mode == AppThemeMode.autoTime) currentModeStr = 'Auto (Time)';

                        return Builder(
                          builder: (tileContext) => _tile(
                            Icons.palette,
                            'Appearance',
                            currentModeStr,
                            iconColor,
                            textColor,
                            subTextColor,
                            () {
                              AppHaptics.sheetInteraction();
                              RidelGlassDropdown.show(
                                tileContext,
                                options: const ['System', 'Light', 'Dark', 'Auto (Time)'],
                                selectedValue: currentModeStr,
                                onSelected: (val) {
                                  if (val == 'System') {
                                    ThemeService.switchTheme(AppThemeMode.system);
                                  } else if (val == 'Light') {
                                    ThemeService.switchTheme(AppThemeMode.light);
                                  } else if (val == 'Dark') {
                                    ThemeService.switchTheme(AppThemeMode.dark);
                                  } else if (val == 'Auto (Time)') {
                                    ThemeService.switchTheme(AppThemeMode.autoTime);
                                  }
                                },
                              );
                            },
                          ),
                        );
                      },
                    ),
                    Divider(height: 1, color: dividerColor),
                    ValueListenableBuilder<HapticLevel>(
                      valueListenable: AppHaptics.hapticLevel,
                      builder: (context, level, child) {
                        String levelText = 'Full';
                        if (level == HapticLevel.light) levelText = 'Light';
                        if (level == HapticLevel.off) levelText = 'Off';

                        return _tile(Icons.vibration_rounded, 'Haptics',
                            levelText, iconColor, textColor, subTextColor, () {
                          AppHaptics.sheetInteraction();
                          RidelGlassDropdown.show(
                            context,
                            options: const ['Full', 'Light', 'Off'],
                            selectedValue: levelText,
                            onSelected: (val) {
                              if (val == 'Full') {
                                AppHaptics.setLevel(HapticLevel.full);
                              }
                              if (val == 'Light') {
                                AppHaptics.setLevel(HapticLevel.light);
                              }
                              if (val == 'Off') {
                                AppHaptics.setLevel(HapticLevel.off);
                              }
                            },
                          );
                        });
                      },
                    ),
                    Divider(height: 1, color: dividerColor),
                    _tile(Icons.shield_outlined, 'Permissions', 'Manage',
                        iconColor, textColor, subTextColor, () {
                      AppHaptics.sheetInteraction();
                      RidelGlassModal.show(context,
                          child: const PermissionsCenterSheet());
                    }),
                    if (!_isGuest) ...[
                      Divider(height: 1, color: dividerColor),
                      _tile(Icons.security, 'Security', '', iconColor,
                          textColor, subTextColor, () {
                        AppHaptics.sheetInteraction();
                        RidelSheet.show(context,
                            title: 'Security',
                            showBackButton: true,
                            child: const SecuritySheetContent());
                      }),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (!_isGuest) ...[
                _section('Danger Zone'),
                _card(
                  cardColor,
                  isDark,
                  ListTile(
                    title: const Text('Delete Account',
                        style: TextStyle(color: Colors.redAccent)),
                    leading: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    onTap: () => Future.microtask(_showDeleteAccountSheet),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              _card(
                cardColor,
                isDark,
                ListTile(
                  title: Text(_isGuest ? 'Log In' : 'Log Out',
                      style: TextStyle(
                          color: _isGuest ? Colors.cyan : Colors.red)),
                  leading: Icon(_isGuest ? Icons.login : Icons.logout,
                      color: _isGuest ? Colors.cyan : Colors.red),
                  onTap: () {
                    Future.microtask(() async {
                      AppHaptics.warning();
                      if (!_isGuest) {
                        await Supabase.instance.client.auth.signOut();
                      }
                      if (!context.mounted) return;
                      Navigator.pushReplacement(context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()));
                    });
                  },
                ),
              ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _section(String t) => Align(
      alignment: Alignment.centerLeft,
      child: Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 8),
          child: Text(t,
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold))));
  Widget _card(Color bgColor, bool isDark, Widget child) => AnimatedContainer(
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeInOutQuart,
      decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05))),
      clipBehavior: Clip.antiAlias,
      child: Material(
          color: Colors.transparent,
          child: child));
  Widget _row(String label, String val, Color textColor, Color subColor,
          {bool readOnly = false,
          bool isLink = false,
          void Function(BuildContext)? onTap}) =>
      Builder(
          builder: (ctx) => ListTile(
              title:
                  Text(label, style: TextStyle(color: textColor, fontSize: 14)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(val,
                    style: TextStyle(
                        color: isLink ? Colors.cyan : subColor, fontSize: 14)),
                if (isLink) Icon(Icons.chevron_right, color: subColor, size: 16)
              ]),
              onTap: onTap != null ? () => Future.microtask(() { if (ctx.mounted) onTap(ctx); }) : null));
  Widget _tile(IconData icon, String title, String sub, Color iconColor,
          Color textColor, Color subColor, VoidCallback onTap) =>
      ListTile(
          leading: Icon(icon, color: iconColor),
          title: Text(title, style: TextStyle(color: textColor)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(sub, style: TextStyle(color: subColor)),
            Icon(Icons.chevron_right, color: subColor, size: 16)
          ]),
          onTap: () => Future.microtask(onTap));
}
