import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; 
import 'package:video_player/video_player.dart';

import '../../../core/utils/app_haptics.dart';
import 'package:ridel/features/tour/screens/all_place.dart';
import '../../home/screens/place_detail_screen.dart';

class ReelFeedScreen extends StatefulWidget {
  const ReelFeedScreen({super.key});

  @override
  State<ReelFeedScreen> createState() => _ReelFeedScreenState();
}

class _ReelFeedScreenState extends State<ReelFeedScreen> {
  final PageController _pageController = PageController();
  final Color neonCyan = const Color(0xFF00E5FF);

  final List<Map<String, dynamic>> _reels = [
    {
      "id": 1,
      "videoUrl": "https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4", 
      "title": "Kedarnath Temple",
      "location": "Uttarakhand",
      "rating": "5.0",
      "likes": "24.5K",
      "comments": "1.2K"
    },
    {
      "id": 2,
      "videoUrl": "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4", 
      "title": "Kerala Backwaters",
      "location": "Alleppey",
      "rating": "4.9",
      "likes": "18.2K",
      "comments": "890"
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openGridView() {
    AppHaptics.heavyImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => AllPlacesScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 📱 1. FULL SCREEN VIDEO FEED
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            physics: const BouncingScrollPhysics(),
            itemCount: _reels.length,
            onPageChanged: (index) {
              AppHaptics.selectionClick();
            },
            itemBuilder: (context, index) {
              return ReelPlayerItem(
                reelData: _reels[index],
                neonCyan: neonCyan,
              );
            },
          ),

          // 🔝 2. TOP NAVIGATION (Fixed Position for Exact Alignment)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12, // Align with PlaceDetailScreen top padding
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 🔙 Sleek Back Button
                GestureDetector(
                  onTap: () {
                    AppHaptics.lightImpact();
                    Navigator.pop(context);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(50),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        height: 44, // 👈 Fixed height for perfect alignment
                        width: 44,  // 👈 Fixed width
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.5),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.only(right: 2.0), // Center iOS back icon visually
                          child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ),
                ),
                
              
                GestureDetector(
                  onTap: _openGridView,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        height: 44, 
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.grid_view_rounded, color: neonCyan, size: 16),
                            const SizedBox(width: 6),
                            const Text("Grid View", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 🎬 INDIVIDUAL REEL PLAYER WIDGET
class ReelPlayerItem extends StatefulWidget {
  final Map<String, dynamic> reelData;
  final Color neonCyan;

  const ReelPlayerItem({super.key, required this.reelData, required this.neonCyan});

  @override
  State<ReelPlayerItem> createState() => _ReelPlayerItemState();
}

class _ReelPlayerItemState extends State<ReelPlayerItem> {
  VideoPlayerController? _videoController;
  bool _isLiked = false;
  bool _isMuted = false;
  
  bool _showVolumeIcon = false;
  Timer? _volumeTimer;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  void _initializeVideo() {
    _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.reelData['videoUrl']))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _videoController!.setLooping(true);
          _videoController!.play();
        }
      }).catchError((error) {
        print("Video loading error: $error");
      });
  }

  @override
  void dispose() {
    _volumeTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  // 🔥 SINGLE TAP TO MUTE/UNMUTE
  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _videoController?.setVolume(_isMuted ? 0.0 : 1.0);
      _showVolumeIcon = true;
    });
    
    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _showVolumeIcon = false);
    });
    
    AppHaptics.lightImpact();
  }

  void _toggleLike() {
    setState(() => _isLiked = !_isLiked);
    AppHaptics.heavyImpact();
  }

  void _openDetailScreen() {
    AppHaptics.heavyImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false, 
        transitionDuration: const Duration(milliseconds: 500), 
        pageBuilder: (context, animation, secondaryAnimation) => PlaceDetailScreen(
          place: {
            "title": widget.reelData['title'],
            "loc": widget.reelData['location'],
            "rating": widget.reelData['rating'],
            "temp": "24°C", 
            "img": widget.reelData['videoUrl'], 
            "lat": 30.7352, 
            "lng": 79.0669, 
          },
          userLat: 28.6139,
          userLng: 77.2090,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
          return FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
            child: SlideTransition(position: slideAnimation, child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. VIDEO PLAYER
        if (_videoController != null && _videoController!.value.isInitialized)
          GestureDetector(
            onTap: _toggleMute, // Single tap to mute
            onDoubleTap: _toggleLike, // Double tap to like
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ),
          )
        else
          const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),

        // 2. BOTTOM SHADOW GRADIENT (Softer for cleaner look)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
              stops: const [0.65, 1.0],
            ),
          ),
        ),

        // 3. CENTER VOLUME INDICATOR
        Center(
          child: AnimatedOpacity(
            opacity: _showVolumeIcon ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
              child: Icon(_isMuted ? CupertinoIcons.volume_off : CupertinoIcons.volume_up, color: Colors.white, size: 40),
            ),
          ),
        ),

        // 🔥 4. BOTTOM LEFT INFO (Clean & Structured)
        Positioned(
          bottom: 30, left: 16, right: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                widget.reelData['title'], 
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5, shadows: [Shadow(color: Colors.black87, blurRadius: 8)])
              ),
              const SizedBox(height: 8),
              
              // Location + Rating Pill Row
              Row(
                children: [
                  const Icon(CupertinoIcons.location_solid, color: Colors.white70, size: 14),
                  const SizedBox(width: 4),
                  Text(widget.reelData['location'], style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 10),

                  ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white.withOpacity(0.1), width: 0.5),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.star_rounded, color: widget.neonCyan, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              widget.reelData['rating'], 
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
          
              GestureDetector(
                onTap: _openDetailScreen,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withOpacity(0.1), width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Explore", 
                            style: TextStyle(color: widget.neonCyan, fontSize: 14, fontWeight: FontWeight.w700)
                          ),
                          const SizedBox(width: 6),
                          Icon(CupertinoIcons.arrow_right, color: widget.neonCyan, size: 14),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 🔥 5. RIGHT SIDE ICONS (Smooth iOS Style, No Sharp Edges)
        Positioned(
          bottom: 30, right: 12,
          child: Column(
            children: [
              _buildMinimalSideButton(
                icon: _isLiked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                color: _isLiked ? Colors.redAccent : Colors.white,
                label: widget.reelData['likes'],
                onTap: _toggleLike,
              ),
              const SizedBox(height: 24),
              _buildMinimalSideButton(
                icon: CupertinoIcons.chat_bubble, 
                color: Colors.white, 
                label: widget.reelData['comments'], 
                onTap: () {}
              ),
              const SizedBox(height: 24),
              // 🔥 Updated Share Button with the requested icon
              _buildMinimalSideButton(
                icon: Icons.share_outlined, // 👈 Exactly matches the 3-node share image
                color: Colors.white, 
                label: "Share", 
                onTap: () {}
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Softened shadows and increased smooth icon sizes
  Widget _buildMinimalSideButton({required IconData icon, required Color color, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            icon, 
            color: color, 
            size: 34, 
            shadows: const [Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1))], 
          ),
          const SizedBox(height: 6),
          Text(
            label, 
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, shadows: [Shadow(color: Colors.black54, blurRadius: 3)]),
          ),
        ],
      ),
    );
  }
}