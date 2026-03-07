import 'package:flutter/material.dart';
import 'dart:async';

class AuthHeader extends StatefulWidget {
  final List<String> texts; 
  final Color neonColor;
  
  const AuthHeader({
    super.key, 
    required this.texts, 
    required this.neonColor
  });

  @override
  State<AuthHeader> createState() => _AuthHeaderState();
}

class _AuthHeaderState extends State<AuthHeader> {
  String _displayedText = "";
  int _currentTextIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTypingLoop();
  }

  void _startTypingLoop() async {
    while (mounted) {
      String currentTarget = widget.texts[_currentTextIndex];

      // 1. Typing Phase (100ms per character)
      for (int i = 0; i <= currentTarget.length; i++) {
        if (!mounted) return;
        setState(() => _displayedText = currentTarget.substring(0, i));
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      // Pause after typing complete
      await Future.delayed(const Duration(seconds: 3));
      
      // 2. Backspacing Phase (40ms per character)
      for (int i = currentTarget.length; i >= 0; i--) {
        if (!mounted) return;
        setState(() => _displayedText = currentTarget.substring(0, i));
        await Future.delayed(const Duration(milliseconds: 40));
      }

      // 3. Move to next text
      setState(() {
        _currentTextIndex = (_currentTextIndex + 1) % widget.texts.length;
      });

      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100, // Fixed height space taaki screen jump na kare
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible( 
            child: Text(
              _displayedText,
              textAlign: TextAlign.center,
              // GoogleFonts hata diya hai, ab app ka standard font use hoga
              style: TextStyle(
                color: widget.neonColor,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Bada White Dot (34x34) pixel-perfect from old design
          Container(
            width: 34, 
            height: 34,
            decoration: const BoxDecoration(
              color: Colors.white, 
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}