import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import '../../features/profile/services/profile_repository.dart';
import 'ridel_sheet.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/place_service.dart';

// ✅ Class Name Updated
class CitySelectorSheet extends StatefulWidget {
  const CitySelectorSheet({super.key});

  // ✅ Static Show Method (Jo AppHeader dhoond raha tha)
  static void show(BuildContext context) {
    RidelSheet.show(
      context,
      title: "Select City",
      showCloseButton: true,
      child: const CitySelectorSheet(),
    );
  }

  @override
  State<CitySelectorSheet> createState() => _CitySelectorSheetState();
}

class _CitySelectorSheetState extends State<CitySelectorSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  
  final List<String> _popularCities = [
    "Delhi", "Mumbai", "Bangalore", "Pune", "Jaipur", "Hyderabad", 
    "Chennai", "Kolkata", "Ahmedabad", "Lucknow", "Chandigarh", 
    "Surat", "Indore", "Bhopal", "Patna", "Kochi", "Agra", "Varanasi", 
    "Dehradun", "Amritsar", "Nagpur"
  ];
  
  late List<String> _searchResults;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchResults = List.from(_popularCities);
  }

  void _searchCityLive(String query) {
    if(query.isEmpty) { 
      setState(() => _searchResults = List.from(_popularCities)); 
      return; 
    }
    setState(() {
      _searchResults = _popularCities
          .where((c) => c.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> _onCitySelected(String city) async {
    if (city == "USE_GPS") {

      ProfileRepository.userCity.value = "Locating..."; 
      Navigator.pop(context); 

      final locationService = Provider.of<GlobalLocationService>(context, listen: false);

      if (!locationService.hasValidLocation) {
        await locationService.initializeEcoLocation();
      }

      final position = locationService.currentPosition;

      if (position != null) {
        print("📍 User Location Found: ${position.latitude}, ${position.longitude}");
  
        final detectedCity = await PlaceService.getCityFromCoordinates(
          position.latitude, 
          position.longitude
        );

        if (detectedCity != null) {
          ProfileRepository.userCity.value = detectedCity;
          AppHaptics.lightImpact(); 
        } else {
          ProfileRepository.userCity.value = "Location Failed";
          AppHaptics.heavyImpact();
        }
        
      } else {
        ProfileRepository.userCity.value = "GPS Disabled";
        AppHaptics.heavyImpact();
      }
    } else {
  
      ProfileRepository.userCity.value = city;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final searchBg = isDark ? Colors.white.withOpacity(0.08) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final hintColor = isDark ? Colors.grey : Colors.grey.shade500;
    final iconColor = isDark ? Colors.grey : Colors.black54;
    
    final List<BoxShadow> shadow = isDark 
        ? [] 
        : [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))];

    return Padding(
      // ✅ 90px Top Padding taaki Header ke neeche aaye
      padding: const EdgeInsets.only(top: 90, left: 20, right: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔍 FLOATING SEARCH BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: searchBg, 
              borderRadius: BorderRadius.circular(50), 
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.transparent),
              boxShadow: shadow, 
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) => _searchCityLive(val),
              style: TextStyle(color: textColor, fontSize: 16),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 14), 
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.cyan, size: 20),
                prefixIconConstraints: const BoxConstraints(minWidth: 50),
                border: InputBorder.none, 
                hintText: "Search city or state...", 
                hintStyle: TextStyle(color: hintColor, fontSize: 16),
              ),
            ),
          ),
          
          const SizedBox(height: 25),
          
          // 📍 CURRENT LOCATION
          ListTile(
            onTap: () { 
              AppHaptics.heavyImpact(); 
              _onCitySelected("USE_GPS");
            },
            leading: const Icon(Icons.my_location_rounded, color: Colors.cyanAccent),
            title: const Text("Use Current Location", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 15)),
            contentPadding: EdgeInsets.zero, 
            dense: true,
          ),
          
          const SizedBox(height: 25),
          
          Text(_searchCtrl.text.isEmpty ? "POPULAR CITIES" : "SEARCH RESULTS", style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 10),
          
          // 🏙 LIST
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                return ListTile(
                  onTap: () { 
                    AppHaptics.selectionClick(); 
                    _onCitySelected(_searchResults[index]);
                  },
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.location_on_outlined, color: iconColor),
                  title: Text(_searchResults[index], style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w500)),
                  trailing: Icon(Icons.chevron_right_rounded, color: iconColor, size: 16),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}