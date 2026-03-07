import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/utils/app_haptics.dart';

class PlaceCard extends StatefulWidget {
  final String title;
  final String location;
  final String rating;
  final String imageUrl;
  final String weather;
  final VoidCallback onTap;
  final double parallaxOffset; 

  const PlaceCard({
    super.key,
    required this.title,
    required this.location,
    required this.rating,
    required this.imageUrl,
    required this.weather,
    required this.onTap,
    this.parallaxOffset = 0.0, 
  });

  @override
  State<PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<PlaceCard> {
  double _dragOffset = 0.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AppHaptics.mediumImpact();
        widget.onTap();
      },
      onVerticalDragUpdate: (details) {
        if (details.delta.dy < 0) { 
          setState(() { _dragOffset += details.delta.dy * 0.4; });
        }
      },
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity! < -150 || _dragOffset < -40) {
          AppHaptics.heavyImpact();
          widget.onTap();
        }
        setState(() { _dragOffset = 0.0; }); 
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: _dragOffset == 0 ? 400 : 0),
        curve: Curves.easeOutBack,
        transform: Matrix4.translationValues(0, _dragOffset, 0)..scale(_dragOffset < 0 ? 0.98 : 1.0),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32), 
            color: const Color(0xFF0F1216), 
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 25, offset: const Offset(0, 15)),
              BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.05), blurRadius: 30, spreadRadius: 2), 
            ]
          ),
          child: Stack(
            fit: StackFit.expand, 
            children: [
              // 🖼️ INNER PARALLAX IMAGE
              Transform.scale(
                scale: 1.25, 
                child: Transform.translate(
                  offset: Offset(widget.parallaxOffset * -100, 0), 
                  child: Image.network(widget.imageUrl, fit: BoxFit.cover),
                ),
              ),

              // 🌑 BOTTOM SHADOW GRADIENT (Clean Simple Text Layout)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent, 
                      Colors.black.withOpacity(0.3), 
                      Colors.black.withOpacity(0.95)
                    ], 
                    stops: const [0.4, 0.7, 1.0],
                  ),
                ),
              ),
              
              // 💎 "REAL GLASS" EDGE-LIT WEATHER PILL
              Positioned(
                top: 18, right: 18,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), 
                    child: Container(
                      // This 1.5px padding acts as the dynamic glowing border
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        // 🔥 THE INCONSISTENT BORDER SHINE (Light hitting corners)
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.8),  // Strong shine Top-Left
                            Colors.white.withOpacity(0.0),  // Transparent Top-Right / Middle
                            Colors.white.withOpacity(0.0),  // Transparent Bottom-Left / Middle
                            Colors.white.withOpacity(0.4),  // Subtle reflection Bottom-Right
                          ],
                          stops: const [0.0, 0.25, 0.75, 1.0], // Sharp edges, invisible sides
                        ),
                      ),
                      // Inner pure glass body
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(19),
                          color: Colors.black.withOpacity(0.35), // Clean frosted black center
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.weather, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 6),
                            const Icon(Icons.wb_sunny_rounded, color: Colors.orangeAccent, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 🏷️ PURE & SIMPLE DETAILS WITH 3D TEXT SHADOW
              Positioned(
                bottom: 24, left: 24, right: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title, 
                      style: TextStyle(
                        color: Colors.white, 
                        fontSize: 28, 
                        fontWeight: FontWeight.bold, 
                        letterSpacing: -0.5, 
                        height: 1.1,
                        // 🔥 3D FLOATING EFFECT: 2 shadows for depth
                        shadows: [
                          Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 4, offset: const Offset(0, 2)), // Sharp inner drop
                          Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 12, offset: const Offset(0, 4)), // Soft outer glow
                        ]
                      )
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, color: Colors.white.withOpacity(0.8), size: 14, 
                          shadows: [Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 3, offset: const Offset(0, 1))]
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.location, 
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9), 
                              fontSize: 14, 
                              fontWeight: FontWeight.w600,
                              // 🔥 LOCATION SHADOW
                              shadows: [
                                Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 3, offset: const Offset(0, 1)),
                              ]
                            ), 
                            overflow: TextOverflow.ellipsis
                          )
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: const Color(0xFF00E5FF), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: const Color(0xFF00E5FF).withOpacity(0.4), blurRadius: 10)]),
                          child: Row(
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.black, size: 12),
                              const SizedBox(width: 4),
                              Text(widget.rating, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}