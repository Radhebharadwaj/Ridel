import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PlaceCard extends StatelessWidget {
  final String title;
  final String location;
  final String rating;
  final String weather;
  final String imageUrl;
  final double parallaxOffset;
  final VoidCallback onTap;
  final VoidCallback onSwipeUp; // 🔥 Naya Swipe function add kiya

  const PlaceCard({
    super.key,
    required this.title,
    required this.location,
    required this.rating,
    required this.weather,
    required this.imageUrl,
    required this.parallaxOffset,
    required this.onTap,
    required this.onSwipeUp, // 🔥 Ise require kiya
  });

  @override
  Widget build(BuildContext context) {
    // 🔥 YAHAN MAGIC HAI: GestureDetector ko dono powers de di
    return GestureDetector(
      onTap: onTap, // Sirf tap hoga toh detail page khulega
      onVerticalDragEnd: (details) {
        // Agar user ne upar ki taraf zor se swipe kiya hai (Negative Y velocity)
        if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
          onSwipeUp(); // Reel Screen khul jayegi
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          color: const Color(0xFF1E1E1E),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // --- IMAGE WITH PARALLAX ---
            Transform.translate(
              offset: Offset(parallaxOffset * 80.0, 0), // Parallax effect
              child: Transform.scale(
                scale: 1.15, // Extra scale for parallax
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
                  },
                ),
              ),
            ),
            
            // --- BLACK GRADIENT FOR TEXT ---
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.1),
                    Colors.black.withOpacity(0.8),
                  ],
                  stops: const [0.4, 0.7, 1.0],
                ),
              ),
            ),

            // --- WEATHER BADGE (Top Right) ---
            Positioned(
              top: 20,
              right: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  color: Colors.black.withOpacity(0.4), // Simple translucent background
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(weather, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 6),
                      const Icon(Icons.wb_sunny_rounded, color: Colors.orangeAccent, size: 14),
                    ],
                  ),
                ),
              ),
            ),

            // --- BOTTOM INFO ---
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, color: Colors.white70, size: 16),
                          const SizedBox(width: 4),
                          Text(location, style: GoogleFonts.inter(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFF00E5FF), borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.black, size: 14),
                            const SizedBox(width: 4),
                            Text(rating, style: GoogleFonts.inter(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      )
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
}