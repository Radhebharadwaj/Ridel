import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/core/services/universal_mic_button.dart';

// ✅ IMPORTS
import 'package:ridel/features/commute/shared/services/database_helper.dart';
import 'package:ridel/features/commute/shared/widgets/station_selector_sheet.dart';
import 'package:ridel/features/commute/shared/screens/route_result_screen.dart';
import 'package:ridel/features/commute/metro/services/metro_service.dart';
import 'package:ridel/features/commute/shared/models/route_models.dart'; 
import 'package:ridel/features/commute/bus/services/bus_service.dart';

class CommuteSearchCard extends StatefulWidget {
  final bool isDark;
  final int selectedMode;

  const CommuteSearchCard({super.key, required this.isDark, required this.selectedMode});

  @override
  State<CommuteSearchCard> createState() => _CommuteSearchCardState();
}

class _CommuteSearchCardState extends State<CommuteSearchCard> {
  final TextEditingController _fromCtrl = TextEditingController();
  final TextEditingController _toCtrl = TextEditingController();

  List<Map<String, dynamic>> _allStationsCache = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _isSearchingFrom = true; // Tracks which field is active

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  Color get _accentColor => widget.selectedMode == 0 ? const Color(0xFF00E5FF) : const Color(0xFFFF9F0A);
  String get _locationTerm => widget.selectedMode == 0 ? "Station" : "Stop";

  @override
  void initState() {
    super.initState();
    _loadAllStationsForFuzzySearch();
    // Listeners to track focus can be added here if needed
  }

  @override
  void didUpdateWidget(CommuteSearchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedMode != widget.selectedMode) {
      _loadAllStationsForFuzzySearch();
    }
  }

  Future<void> _loadAllStationsForFuzzySearch() async {
    final results = await DatabaseHelper().getStationsByMode(widget.selectedMode);
    if(mounted) {
      setState(() {
        _allStationsCache = results;
        _suggestions = []; 
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }
  
  // 🔥 FIX 1: DEDUPLICATION LOGIC ADDED HERE
  void _onSearchChanged(String query, bool isFrom) {
    _isSearchingFrom = isFrom; // Update tracking flag
    
    // Update Overlay Position immediately if switching fields
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }

    if (query.length < 1) {
      setState(() => _suggestions = []);
      _removeOverlay();
      return;
    }

    final lowerQuery = query.toLowerCase();
    
    // Set to track unique names (Prevents "IIT", "IIT" duplicates)
    final Set<String> seenNames = {};
    final List<Map<String, dynamic>> uniqueResults = [];

    // 1. Exact/Contains Matches
    final exactMatches = _allStationsCache.where((s) {
      return s['stop_name'].toString().toLowerCase().contains(lowerQuery);
    });

    for (var s in exactMatches) {
      if (seenNames.add(s['stop_name'])) {
        uniqueResults.add(s);
      }
    }

    // 2. Fuzzy Matches (Only if few exact matches)
    if (uniqueResults.length < 3 && query.length > 2) {
      final fuzzyMatches = _allStationsCache.where((s) {
        // Skip if already added
        if (seenNames.contains(s['stop_name'])) return false;
        return _levenshtein(s['stop_name'].toString().toLowerCase(), lowerQuery) <= 2; 
      });
      
      for (var s in fuzzyMatches) {
        if (seenNames.add(s['stop_name'])) {
          uniqueResults.add(s);
        }
      }
    }

    setState(() => _suggestions = uniqueResults.take(5).toList());
    
    if (_suggestions.isNotEmpty) {
      _showOverlay(); 
    } else {
      _removeOverlay();
    }
  }

  void _showOverlay() {
    if (_overlayEntry == null) {
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
    } else {
      // Re-build to update position if field changed
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // 🔥 FIX 2: DYNAMIC POSITIONING LOGIC
  OverlayEntry _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;

    return OverlayEntry(
      builder: (context) {
        // Logic: 
        // Agar "From" search kar rahe hain -> Offset 65 (First box ke niche)
        // Agar "To" search kar rahe hain -> Offset 125 (Second box ke niche)
        double yOffset = _isSearchingFrom ? 65.0 : 125.0;

        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            // Dynamic Offset yahan use ho raha hai
            offset: Offset(0, yOffset), 
            child: Material(
              color: Colors.transparent, 
              child: _buildGlassSuggestions()
            ),
          ),
        );
      },
    );
  }

  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;
    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);
    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j < t.length + 1; j++) v0[j] = v1[j];
    }
    return v1[t.length];
  }

  void _onSuggestionTap(Map<String, dynamic> station) {
    AppHaptics.selectionClick();
    setState(() {
      if (_isSearchingFrom) {
        _fromCtrl.text = station['stop_name'];
      } else {
        _toCtrl.text = station['stop_name'];
      }
      _suggestions = [];
      FocusScope.of(context).unfocus();
    });
    _removeOverlay();
  }

  void _swapLocations() {
    AppHaptics.lightImpact();
    final temp = _fromCtrl.text;
    setState(() {
      _fromCtrl.text = _toCtrl.text;
      _toCtrl.text = temp;
    });
  }

  void _detectNearestStation() {
    AppHaptics.heavyImpact();
    setState(() => _fromCtrl.text = "Locating...");
    Future.delayed(const Duration(milliseconds: 800), () {
      if(mounted) {
        setState(() => _fromCtrl.text = widget.selectedMode == 0 ? "Rajiv Chowk" : "Kashmere Gate ISBT"); 
        ToastService.showSuccess(context, "Nearest $_locationTerm located");
      }
    });
  }

  Future<void> _openStationSheet({required bool isFrom}) async { 
    AppHaptics.lightImpact();
    FocusScope.of(context).unfocus();
    _removeOverlay();

    await RidelSheet.show(
      context,
      title: "",
      customHeader: true,
      child: StationSelectorSheet(
        isSelectingSource: isFrom,
        isBusMode: widget.selectedMode == 1,
        
        currentFromStation: _fromCtrl.text.isEmpty ? null : {'stop_name': _fromCtrl.text, 'stop_id': 'mock_id_1'}, 
        currentToStation: _toCtrl.text.isEmpty ? null : {'stop_name': _toCtrl.text, 'stop_id': 'mock_id_2'},
        
        onStationSelected: (station, isSourceSelected) {
          setState(() {
            if (isSourceSelected) {
              _fromCtrl.text = station['stop_name'];
            } else {
              _toCtrl.text = station['stop_name'];
            }
          });
        },
      ),
    );
  }

  void _handleMainButton() async {
    AppHaptics.heavyImpact();
    
    if (_fromCtrl.text.isEmpty && _toCtrl.text.isEmpty) {
      _openStationSheet(isFrom: true);
    } 
    else if (_fromCtrl.text.isNotEmpty && _toCtrl.text.isEmpty) {
      _openStationSheet(isFrom: false);
    }
    else if (_fromCtrl.text.isNotEmpty && _toCtrl.text.isNotEmpty) {
      
      ToastService.showSuccess(context, "Finding best route..."); 

      try {
        if (widget.selectedMode == 0) {
          final result = await MetroService().findBestRoute(_fromCtrl.text, _toCtrl.text);
          if (mounted && result != null && result.path.isNotEmpty) {
             Navigator.push(context, MaterialPageRoute(builder: (context) => RouteResultScreen(fromStation: _fromCtrl.text, toStation: _toCtrl.text, routeData: result)));
          } else {
             ToastService.showError(context, "No route found.");
          }
        } else {
          // 🔥 BUS LOGIC (UPDATED HERE)
          final result = await BusService().findBusRoute(_fromCtrl.text, _toCtrl.text);
          
          if (mounted) {
            if (result != null && result.path.isNotEmpty) {
               Navigator.push(
                 context, 
                 MaterialPageRoute(
                   builder: (context) => RouteResultScreen(
                     fromStation: _fromCtrl.text, 
                     toStation: _toCtrl.text, 
                     routeData: result,
                     isMetro: false, // 👈 Bus Mode ke liye false
                   )
                 )
               );
            } else {
               ToastService.showError(context, "No bus route found.");
            }
          }
        }
      } catch (e) {
        debugPrint("Route Error: $e");
        ToastService.showError(context, "Error finding route.");
      }
      
    } else {
      _openStationSheet(isFrom: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = widget.isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final inputBg = widget.isDark ? const Color(0xFF0B0E17) : const Color(0xFFF2F2F7);
    final textColor = widget.isDark ? Colors.white : Colors.black;
    final hintColor = widget.isDark ? Colors.grey.shade700 : Colors.grey.shade400;

    final bool isReady = _fromCtrl.text.isNotEmpty && _toCtrl.text.isNotEmpty;
    final String btnLabel = isReady ? "Find Route" : "Select $_locationTerm""s";
    final IconData btnIcon = isReady ? Icons.directions_transit_filled_rounded : Icons.list_alt_rounded;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(35),
          border: Border.all(color: widget.isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(widget.isDark ? 0.4 : 0.08), blurRadius: 30, offset: const Offset(0, 15))],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SizedBox(
              height: 108,
              child: Stack(
                children: [
                  Column(
                    children: [
                      _buildSlimCapsule(
                        leftIcon: Icons.my_location_rounded, leftIconColor: _accentColor,
                        hint: "From $_locationTerm", 
                        controller: _fromCtrl,
                        bgColor: inputBg, textColor: textColor, hintColor: hintColor,
                        onLeftIconTap: _detectNearestStation, isDark: widget.isDark,
                        // 🔥 Pass true for FROM
                        onChanged: (val) => _onSearchChanged(val, true),
                      ),
                      const SizedBox(height: 8), 
                      _buildSlimCapsule(
                        leftIcon: Icons.location_on_rounded, leftIconColor: Colors.redAccent,
                        hint: "To $_locationTerm", 
                        controller: _toCtrl,
                        bgColor: inputBg, textColor: textColor, hintColor: hintColor,
                        onLeftIconTap: () {}, isDark: widget.isDark,
                        // 🔥 Pass false for TO
                        onChanged: (val) => _onSearchChanged(val, false),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 48, top: 0, bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _swapLocations,
                        child: Container(
                          height: 28, width: 28,
                          decoration: BoxDecoration(
                            color: cardBg, shape: BoxShape.circle,
                            border: Border.all(color: widget.isDark ? Colors.white24 : Colors.grey.shade300),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]
                          ),
                          child: Icon(Icons.swap_vert_rounded, size: 16, color: widget.isDark ? Colors.white70 : Colors.black54),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: _handleMainButton,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.isDark ? Colors.white : Colors.black, 
                  foregroundColor: widget.isDark ? Colors.black : Colors.white,
                  elevation: 0, shadowColor: _accentColor.withOpacity(0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(btnLabel, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(width: 8), Icon(btnIcon, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildGlassSuggestions() {
       final isDark = widget.isDark;
      final bgColor = isDark ? const Color(0xFF121212).withOpacity(0.95) : Colors.white.withOpacity(0.95);
      final borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);
      final textColor = isDark ? Colors.white : Colors.black;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 250),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, spreadRadius: 2)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                color: bgColor, 
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                  itemBuilder: (context, index) {
                    final station = _suggestions[index];
                    final colorHex = station['route_color'] ?? "808080"; 
                    final mainColor = Color(int.parse("0xFF$colorHex"));
                    final bool isInterchange = (station['is_interchange'] == 1); 

                    BorderRadius? itemBorderRadius;
                    int totalItems = _suggestions.length;
                    if (totalItems == 1) { itemBorderRadius = BorderRadius.circular(24); } 
                    else if (index == 0) { itemBorderRadius = const BorderRadius.vertical(top: Radius.circular(24)); } 
                    else if (index == totalItems - 1) { itemBorderRadius = const BorderRadius.vertical(bottom: Radius.circular(24)); } 
                    else { itemBorderRadius = BorderRadius.zero; }

                    return Material(
                      color: Colors.transparent, 
                      child: InkWell(
                        borderRadius: itemBorderRadius,
                        onTap: () => _onSuggestionTap(station),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                          child: Row(
                            children: [
                              Container(
                                width: 12, height: 12,
                                decoration: BoxDecoration(
                                  color: isInterchange ? Colors.white : mainColor, 
                                  shape: BoxShape.circle, 
                                  border: Border.all(color: isInterchange ? Colors.transparent : Colors.white.withOpacity(0.2), width: 1.5)
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Text(station['stop_name'], style: GoogleFonts.inter(color: textColor, fontWeight: FontWeight.w600, fontSize: 15))),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
  }
  
  Widget _buildSlimCapsule({
    required IconData leftIcon, 
    required Color leftIconColor, 
    required String hint, 
    required TextEditingController controller, 
    required Color bgColor, 
    required Color textColor,
    required Color hintColor, 
    required VoidCallback onLeftIconTap, 
    required bool isDark,
    required Function(String) onChanged,
  }) {
    final bool isTyping = controller.text.isNotEmpty;
    
    // Add Listener to handle focus if needed, but onChanged works for search
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 12, right: 8),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(100)),
      child: Row(
        children: [
          GestureDetector(
            onTap: onLeftIconTap, 
            child: Container(
              padding: const EdgeInsets.all(6), 
              color: Colors.transparent, 
              child: Icon(leftIcon, color: leftIconColor, size: 20)
            )
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller, 
              onChanged: onChanged, 
              // Added onTap to ensure overlay appears for correct field if already has text
              onTap: () {
                 if(controller.text.isNotEmpty) onChanged(controller.text);
              },
              style: GoogleFonts.inter(color: textColor, fontWeight: FontWeight.w600, fontSize: 15),
              cursorColor: _accentColor, 
              decoration: InputDecoration(
                hintText: hint, 
                hintStyle: TextStyle(color: hintColor, fontWeight: FontWeight.normal), 
                border: InputBorder.none, 
                isDense: true, 
                contentPadding: EdgeInsets.zero
              ),
            )
          ),
          const SizedBox(width: 5),
          
          if (isTyping)
            GestureDetector(
              onTap: () {
                AppHaptics.lightImpact();
                controller.clear(); 
                onChanged(""); 
              },
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(Icons.close_rounded, color: isDark ? Colors.white38 : Colors.black38, size: 22),
              ),
            )
          else
            UniversalMicButton(
              isDark: isDark,
              activeColor: _accentColor,
              onTextRecognized: (text) {
                controller.text = text;
                onChanged(text); 
                setState(() {});
              },
            ),
        ],
      ),
    );
  }
}