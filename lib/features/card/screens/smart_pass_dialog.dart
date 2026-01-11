import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math';

class SmartPassDialog extends StatefulWidget {
  final Map<String, dynamic>? profileData;

  const SmartPassDialog({super.key, this.profileData});

  @override
  State<SmartPassDialog> createState() => _SmartPassDialogState();
}

class _SmartPassDialogState extends State<SmartPassDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  
  // Data Variables (To ensure consistency front & back)
  late String _userName;
  late String _travelId;
  late String _userBalance;
  late bool _isGuest;

  @override
  void initState() {
    super.initState();
    
    // --- 1. Load Data Consistency ---
    // Yaha hum data load kar rahe hain taki front aur back same rahe
    _userName = widget.profileData?['full_name'] ?? 'Traveler';
    // Travel ID logic: Agar DB me nahi hai to mock dikhao, agar guest hai to hidden
    _isGuest = widget.profileData == null; // Simple guest check logic based on data presence
    _travelId = widget.profileData?['travel_id'] ?? 'IN-8829-X4'; 
    _userBalance = "₹ 1,250.00"; // Mock Balance (Baad me DB se connect karenge)

    // --- 2. Animation Setup ---
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), // Slower for premium feel
    );

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutBack), // Bouncy effect
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flipCard() {
    if (_controller.isDismissed) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dialog ka background transparent blur
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: GestureDetector(
          onTap: () => Navigator.pop(context), // Bahar tap karne par close
          child: Container(
            color: Colors.transparent, // Hit test behavior ke liye
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {}, // Card par tap karne se close na ho
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  // --- 3D FLIP CALCULATIONS ---
                  final double angle = _animation.value * pi;
                  final bool isFront = angle < pi / 2;
                  
                  // Matrix transform for 3D perspective
                  final Matrix4 transform = Matrix4.identity()
                    ..setEntry(3, 2, 0.001) // Perspective depth
                    ..rotateY(angle);

                  return Transform(
                    transform: transform,
                    alignment: Alignment.center,
                    child: isFront 
                        ? _buildFrontCard() 
                        : Transform(
                            // Piche wala card mirror na dikhe, isliye 180 rotate wapas karte hain
                            transform: Matrix4.identity()..rotateY(pi),
                            alignment: Alignment.center,
                            child: _buildBackGlassCard(),
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

  // ---------------------------------------------------------------------------
  // --- FRONT SIDE: PREMIUM DARK CARD ---
  // ---------------------------------------------------------------------------
  Widget _buildFrontCard() {
    return GestureDetector(
      onTap: _flipCard, // Tap to flip
      child: Container(
        width: 320,
        height: 500,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF1E1E1E), Color(0xFF000000)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6), 
              blurRadius: 30, 
              spreadRadius: 5,
              offset: const Offset(0, 15)
            ),
            // Subtle Cyan glow for Smart Pass feel
            BoxShadow(
              color: Colors.cyan.withOpacity(0.1), 
              blurRadius: 20, 
              spreadRadius: 0,
            )
          ],
        ),
        child: Stack(
          children: [
             // Background Pattern
            Positioned(right: -40, top: -40, child: Icon(Icons.qr_code_2, size: 250, color: Colors.white.withOpacity(0.03))),
            
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                       const Row(
                         children: [
                           Icon(Icons.nfc_rounded, color: Colors.cyanAccent, size: 20),
                           SizedBox(width: 8),
                           Text("SMART PASS", style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                         ],
                       ),
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                         decoration: BoxDecoration(
                           color: const Color(0xFF25D366).withOpacity(0.15),
                           borderRadius: BorderRadius.circular(20),
                           border: Border.all(color: const Color(0xFF25D366).withOpacity(0.3)),
                         ),
                         child: const Text("ACTIVE", style: TextStyle(color: Color(0xFF25D366), fontSize: 10, fontWeight: FontWeight.bold)),
                       )
                    ],
                  ),

                  // Center QR
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)]
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.qr_code_2, size: 160, color: Colors.black),
                        const SizedBox(height: 8),
                        Text("Tap to flip details", style: TextStyle(color: Colors.black.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),

                  // Bottom Info
                  Column(
                    children: [
                      Text(_userName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text("Travel ID: $_travelId", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14, letterSpacing: 1, fontFamily: 'Monospace')),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // --- BACK SIDE: GLASSMORPHISM DETAIL CARD ---
  // ---------------------------------------------------------------------------
  Widget _buildBackGlassCard() {
    return GestureDetector(
      onTap: _flipCard, // Tap to flip back
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0), // Strong Blur
          child: Container(
            width: 320,
            height: 500,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1), // Translucent White
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.15),
                  Colors.white.withOpacity(0.05),
                ]
              )
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("PASS DETAILS", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      Icon(Icons.info_outline, color: Colors.white.withOpacity(0.6), size: 20),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 30),
                  
                  // Detailed Info Rows
                  _buildGlassRow(Icons.person, "Holder Name", _userName),
                  _buildGlassRow(Icons.badge, "Travel ID", _travelId),
                  _buildGlassRow(Icons.account_balance_wallet, "Current Balance", _userBalance, isHighlight: true),
                  _buildGlassRow(Icons.calendar_today, "Issued Date", "Jan 2026"), // Static for now
                  _buildGlassRow(Icons.event, "Valid Thru", "Dec 2028"), // Static for now
                  
                  const Spacer(),
                  
                  // Footer Instruction
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.touch_app, color: Colors.white.withOpacity(0.5)),
                        const SizedBox(height: 8),
                        Text("Tap anywhere to flip back", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassRow(IconData icon, String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
              const SizedBox(height: 2),
              Text(
                value, 
                style: TextStyle(
                  color: isHighlight ? Colors.cyanAccent : Colors.white, 
                  fontSize: 16, 
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5
                )
              ),
            ],
          )
        ],
      ),
    );
  }
}