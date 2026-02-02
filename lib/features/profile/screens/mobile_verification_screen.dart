import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ridel/core/services/identity_service.dart';
import 'package:ridel/features/profile/services/profile_repository.dart';

class MobileVerificationScreen extends StatefulWidget {
  final ProfileRepository repository;

  const MobileVerificationScreen({super.key, required this.repository});

  @override
  State<MobileVerificationScreen> createState() => _MobileVerificationScreenState();
}

class _MobileVerificationScreenState extends State<MobileVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _secondaryPhoneController = TextEditingController();
  final _dobController = TextEditingController();
  
  String? _selectedGender;
  bool _isLoading = false;
  
  // Identity Data
  Map<String, String?> _locationData = {};
  Map<String, String?> _deviceData = {};

  final IdentityService _identityService = IdentityService();

  @override
  void initState() {
    super.initState();
    _fetchIdentityInfo();
  }

  Future<void> _fetchIdentityInfo() async {
    // Fetch silently
    final loc = await _identityService.getLocationInfo();
    final dev = await _identityService.getDeviceInfo();
    if (mounted) {
      setState(() {
        _locationData = loc;
        _deviceData = dev;
      });
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _secondaryPhoneController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)), // Default to 18 years ago
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
      setState(() {
        _dobController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _verifyAndSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select gender')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Mock OTP Verification
    // In a real app, we would send OTP here.
    // For now, we simulate a delay and success.
    await Future.delayed(const Duration(seconds: 2));

    try {
      final updates = {
        'phone_primary': _phoneController.text.trim(),
        'phone_secondary': _secondaryPhoneController.text.trim().isNotEmpty 
            ? _secondaryPhoneController.text.trim() 
            : null,
        'gender': _selectedGender,
        'dob': _dobController.text.trim(),
        'is_verified': true,
        
        // Location Data
        'country_code': _locationData['country_code'] ?? 'IN', // Default to IN if failed
        'state_code': _locationData['state_code'],
        'current_city': _locationData['current_city'],

        // Device Data
        'last_device_id': _deviceData['last_device_id'],
        'last_device_name': _deviceData['last_device_name'],
      };

      await widget.repository.updateProfile(updates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification Successful! Profile Updated.')),
        );
        Navigator.pop(context, true); // Return success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Mobile Verification", style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Verify your identity",
                style: TextStyle(color: Colors.cyan, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "We need to verify your mobile number and identity details to issue your Travel ID.",
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 30),

              // Primary Phone
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration("Primary Mobile Number (Required)"),
                validator: (value) {
                  if (value == null || value.length < 10) return 'Enter valid 10-digit number';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Secondary Phone
              TextFormField(
                controller: _secondaryPhoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration("Secondary Mobile Number (Optional)"),
              ),
              const SizedBox(height: 20),

              // Gender
              DropdownButtonFormField<String>(
                value: _selectedGender,
                dropdownColor: const Color(0xFF1A1A1A),
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration("Gender"),
                items: ['Male', 'Female', 'Other'].map((String val) {
                  return DropdownMenuItem(
                    value: val,
                    child: Text(val),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedGender = val),
              ),
              const SizedBox(height: 20),

              // DOB
              TextFormField(
                controller: _dobController,
                readOnly: true,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration("Date of Birth").copyWith(
                  suffixIcon: const Icon(Icons.calendar_today, color: Colors.cyan),
                ),
                onTap: () => _selectDate(context),
                validator: (value) => value!.isEmpty ? 'Select Date of Birth' : null,
              ),

              const SizedBox(height: 40),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyAndSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text("VERIFY & SAVE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.grey),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.cyan),
        borderRadius: BorderRadius.circular(12),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.red),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.red),
        borderRadius: BorderRadius.circular(12),
      ),
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
    );
  }
}
