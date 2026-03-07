import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui';
// 🔥 FIX 1: Relative path for Haptics to avoid import errors
import '../../../core/utils/app_haptics.dart';
// 🔥 FIX 2: Correct file name connection
import 'all_places.dart';

class ReelFeedScreen extends StatefulWidget {
  const ReelFeedScreen({super.key});

  @override
  State<ReelFeedScreen> createState() => _ReelFeedScreenState();
}

class _ReelFeedScreenState extends State<ReelFeedScreen> {
  final PageController _pageController = PageController();
  final Color neonCyan = const Color(0xFF00E5FF);

  // 🎥 Dummy high-quality vertical travel videos
  final List<Map<String, dynamic>> _reels = [
    {
      "id": 1,
      // Sample vertical travel video URL
      "videoUrl": "https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4", 
      "title": "Kedarnath Temple",
      "location": "Uttarakhand, India",
      "rating": "5.0",
      "likes": "24.5K"
    },
    {
      "id": 2,
      "videoUrl": "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4", 
      "title": "Kerala Backwaters",
      "location": "Alleppey, Kerala",
      "rating": "4.9",
      "likes": "18.2K"
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
          // 📱 VERTICAL REEL FEED
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

          // 🔝 TOP NAVIGATION BAR (Back & Grid View Button)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back Button
                  GestureDetector(
                    onTap: () {
                      AppHaptics.lightImpact();
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                  
                  // 🔥 Grid View Button (Connects to all_places.dart)
                  GestureDetector(
                    onTap: _openGridView,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.grid_view_rounded, color: neonCyan, size: 16),
                              const SizedBox(width: 8),
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
          ),
        ],
      ),
    );
  }
}

// 🎬 INDIVIDUAL REEL PLAYER WIDGET (Handles memory efficiently)
class ReelPlayerItem extends StatefulWidget {
  final Map<String, dynamic> reelData;
  final Color neonCyan;

  const ReelPlayerItem({super.key, required this.reelData, required this.neonCyan});

  @override
  State<ReelPlayerItem> createState() => _ReelPlayerItemState();
}

class _ReelPlayerItemState extends State<ReelPlayerItem> {
  // 🔥 FIX 3: Handling video controller initialization properly
  VideoPlayerController? _videoController;
  bool _isLiked = false;
  bool _isMuted = false;

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
        // 🔥 FIX 4: Safety catch agar video load na ho
        print("Video loading error: $error");
      });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _videoController?.setVolume(_isMuted ? 0.0 : 1.0);
    });
    AppHaptics.lightImpact();
  }

  void _toggleLike() {
    setState(() => _isLiked = !_isLiked);
    AppHaptics.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. VIDEO PLAYER
        if (_videoController != null && _videoController!.value.isInitialized)
          GestureDetector(
            onTap: () {
              // Tap to pause/play
              _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play();
              setState(() {});
            },
            onDoubleTap: _toggleLike,
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

        // 2. BOTTOM SHADOW GRADIENT
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
              stops: const [0.6, 1.0],
            ),
          ),
        ),

        // 3. UI OVERLAYS (Bottom Info & Visit Button)
        Positioned(
          bottom: 40, left: 20, right: 80, // Space on right for side buttons
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: widget.neonCyan.withOpacity(0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: widget.neonCyan.withOpacity(0.5))),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFF00E5FF), size: 14),
                    const SizedBox(width: 4),
                    Text(widget.reelData['rating'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(widget.reelData['title'], style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, height: 1.1)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.location_on, color: Colors.white.withOpacity(0.8), size: 16),
                  const SizedBox(width: 4),
                  Text(widget.reelData['location'], style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15, fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 20),
              // THE "VISIT" BUTTON (To open details screen)
              GestureDetector(
                onTap: () { AppHaptics.heavyImpact(); /* TODO: Navigate to Detail Screen */ },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                  decoration: BoxDecoration(color: widget.neonCyan, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: widget.neonCyan.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))]),
                  child: const Text("Visit Place", style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),

        // 4. RIGHT SIDE ACTION BUTTONS (Like, Share, Mute)
        Positioned(
          bottom: 40, right: 15,
          child: Column(
            children: [
              _buildSideButton(
                icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                color: _isLiked ? Colors.redAccent : Colors.white,
                label: widget.reelData['likes'],
                onTap: _toggleLike,
              ),
              const SizedBox(height: 20),
              _buildSideButton(icon: Icons.share_rounded, color: Colors.white, label: "Share", onTap: () {}),
              const SizedBox(height: 20),
              _buildSideButton(icon: _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white, label: "Mute", onTap: _toggleMute),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSideButton({required IconData icon, required Color color, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}