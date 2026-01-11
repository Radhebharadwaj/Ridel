import 'package:flutter/material.dart';
import 'dart:math';

class SmartPassCard extends StatefulWidget {
  final Map<String, dynamic>? profileData;

  const SmartPassCard({super.key, this.profileData});

  @override
  State<SmartPassCard> createState() => _SmartPassCardState();
}

class _SmartPassCardState extends State<SmartPassCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _showFrontSide = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutBack),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flipCard() {
    if (_showFrontSide) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    _showFrontSide = !_showFrontSide;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _flipCard,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final angle = _animation.value * pi;
          // Only show front for the first 90 degrees (pi/2)
          final isFront = angle < pi / 2;
          
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle);

          return Transform(
            transform: transform,
            alignment: Alignment.center,
            // If it's the back side, we need to rotate the content 180 degrees so it's not mirrored
            child: isFront 
                ? _buildFront() 
                : Transform(
                    transform: Matrix4.identity()..rotateY(pi),
                    alignment: Alignment.center,
                    child: _buildBack(),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildFront() {
    return Container(
      width: double.infinity, height: 170,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [const Color(0xFF1A1A1A), Colors.grey.shade900],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 25, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              right: -50, bottom: -50,
              child: Icon(Icons.qr_code_2_rounded, size: 200, color: Colors.white.withOpacity(0.03)),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        const Icon(Icons.nfc_rounded, color: Colors.white54, size: 20), 
                        const SizedBox(width: 8), 
                        Text("SMART PASS", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold))
                      ]),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF25D366).withOpacity(0.3)),
                        ),
                        child: Row(children: [
                          const CircleAvatar(radius: 3, backgroundColor: Color(0xFF25D366)), 
                          const SizedBox(width: 6), 
                          const Text("ACTIVE", style: TextStyle(color: Color(0xFF25D366), fontSize: 10, fontWeight: FontWeight.bold))
                        ]),
                      )
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("Travel ID", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                        const SizedBox(height: 4),
                        const Text("IN-8829-X4", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1))
                      ]),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.qr_code_2, color: Colors.black, size: 36),
                      )
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBack() {
    final String fullName = widget.profileData?['full_name'] ?? 'Guest User';
    final String email = widget.profileData?['email'] ?? 'Not Linked';

    return Container(
      width: double.infinity, height: 170,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [const Color(0xFF1A1A1A), Colors.grey.shade900],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 25, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("PASS DETAILS", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold)),
                  Icon(Icons.info_outline, color: Colors.white.withOpacity(0.5), size: 20),
                ],
              ),
              const Spacer(),
              Text("HOLDER NAME", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
              const SizedBox(height: 2),
              Text(fullName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              Text("LINKED EMAIL", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
              const SizedBox(height: 2),
              Text(email, style: const TextStyle(color: Colors.white70, fontSize: 14), overflow: TextOverflow.ellipsis),
              const Spacer(),
              Center(child: FittedBox(child: Text("Tap to flip back", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10)))),
            ],
          ),
        ),
      ),
    );
  }
}
