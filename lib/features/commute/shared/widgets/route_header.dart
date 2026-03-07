import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';

class RouteHeader extends StatefulWidget {
  final String fromStation;
  final String toStation;
  final double topPadding;
  final bool isScrolled;
  final VoidCallback onBack;
  final Function(String, String) onSwap;

  const RouteHeader({
    super.key,
    required this.fromStation,
    required this.toStation,
    required this.topPadding,
    required this.isScrolled,
    required this.onBack,
    required this.onSwap,
  });

  @override
  State<RouteHeader> createState() => _RouteHeaderState();
}

class _RouteHeaderState extends State<RouteHeader> {
  // Theme Color
  final Color themeBg = const Color(0xFF0B0E17);

  // States
  bool _isSearching = false;
  bool _isPillExpanded = false;
  
  late String _from;
  late String _to;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _from = widget.fromStation;
    _to = widget.toStation;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleSwap() {
    AppHaptics.mediumImpact();
    setState(() {
      final temp = _from;
      _from = _to;
      _to = temp;
    });
    widget.onSwap(_from, _to);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Height covers status bar + content + fade area
      height: widget.topPadding + 80, 
      padding: EdgeInsets.only(top: widget.topPadding + 10, left: 16, right: 16, bottom: 10),
      decoration: BoxDecoration(
        // Gradient Shadow only (No solid glass)
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            themeBg,                // Solid at top (Status Bar)
            themeBg.withOpacity(0.95), // Slightly fade
            themeBg.withOpacity(0.0),  // Transparent at bottom
          ],
          stops: const [0.0, 0.6, 1.0], 
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Back Button (Animates width to 0 when Pill is Expanded)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            child: SizedBox(
              width: _isPillExpanded ? 0 : null, // Shrink to 0 width
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: widget.onBack,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, 
                        color: Colors.white.withOpacity(0.1)
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                  // Spacing also shrinks with the container
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
          
          // 2. Animated Switcher (Pill vs Search)
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _isSearching 
                  ? _buildSearchField() // Show Search Bar
                  : _buildExpandablePillArea(), // Show Pill + Icon
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildExpandablePillArea() {
    return Row(
      children: [
        // The Pill
        Expanded(
          child: GestureDetector(
            onTap: () {
              AppHaptics.lightImpact();
              // Toggle Pill Expansion (Now expands Left because BackBtn shrinks, and Right because Icon shrinks)
              setState(() => _isPillExpanded = !_isPillExpanded);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.fastOutSlowIn,
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // FROM Station
                  Flexible(
                    fit: FlexFit.loose,
                    child: Text(
                      _from,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),

                  // Swap Icon (Arrows Only)
                  GestureDetector(
                    onTap: _handleSwap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Icon(Icons.swap_horiz_rounded, color: Colors.white.withOpacity(0.6), size: 20),
                    ),
                  ),

                  // TO Station
                  Flexible(
                    fit: FlexFit.loose,
                    child: Text(
                      _to,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Search Icon (Hides when Pill Expanded -> Allows expansion to Right)
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: SizedBox(
            width: _isPillExpanded ? 0 : 56, // 12 padding + 44 size
            child: _isPillExpanded 
              ? const SizedBox() 
              : Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () {
                        AppHaptics.lightImpact();
                        setState(() => _isSearching = true);
                      },
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.1))
                        ),
                        child: const Icon(Icons.search_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ),
          ),
        )
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: "Search station...",
                hintStyle: GoogleFonts.inter(color: Colors.white54),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          // Close Button
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
            onPressed: () {
              AppHaptics.lightImpact();
              setState(() {
                _isSearching = false;
                _searchCtrl.clear();
              });
            },
          ),
        ],
      ),
    );
  }
}