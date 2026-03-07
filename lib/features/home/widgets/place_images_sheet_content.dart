import 'package:flutter/material.dart';
import '../../../core/utils/app_haptics.dart';
import '../services/wikipedia_service.dart';

class PlaceImagesSheetContent extends StatefulWidget {
  final String title;
  final String mainImageUrl;

  const PlaceImagesSheetContent({
    super.key,
    required this.title,
    required this.mainImageUrl,
  });

  @override
  State<PlaceImagesSheetContent> createState() => _PlaceImagesSheetContentState();
}

class _PlaceImagesSheetContentState extends State<PlaceImagesSheetContent> {
  static const Color neonCyan = Color(0xFF00E5FF);
  
  final ScrollController _scrollController = ScrollController();
  List<String> _images = [];
  
  bool _isInitialLoading = true;
  bool _isFetchingMore = false;
  bool _hasMoreImages = true;
  String? _continueToken;

  @override
  void initState() {
    super.initState();
    // Sabse pehle apni main badi image add kar do
    _images.add(widget.mainImageUrl);
    _fetchInitialImages();

    // Scroll listener for Unlimited Scrolling
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        if (!_isFetchingMore && _hasMoreImages) {
          _fetchMoreImages();
        }
      }
    });
  }

  Future<void> _fetchInitialImages() async {
    final result = await WikipediaService.fetchRealPlaceImagesPaginated(widget.title, widget.mainImageUrl);
    if (mounted) {
      setState(() {
        _images.addAll(result['images'] as List<String>);
        _continueToken = result['continueToken'] as String?;
        _hasMoreImages = _continueToken != null;
        _isInitialLoading = false;
      });
    }
  }

  Future<void> _fetchMoreImages() async {
    setState(() => _isFetchingMore = true);
    
    final result = await WikipediaService.fetchRealPlaceImagesPaginated(
      widget.title, 
      widget.mainImageUrl, 
      continueToken: _continueToken
    );
    
    if (mounted) {
      setState(() {
        _images.addAll(result['images'] as List<String>);
        _continueToken = result['continueToken'] as String?;
        _hasMoreImages = _continueToken != null;
        _isFetchingMore = false;
      });
    }
  }

  // 🚀 Full Screen Image Kholne ka Function
  void _openFullScreenImage(String imageUrl, String tag) {
    AppHaptics.lightImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.9), // Dark background
        pageBuilder: (context, _, __) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                // Zoomable Image
                Center(
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Hero(
                      tag: tag,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                ),
                // Close Button
                Positioned(
                  top: MediaQuery.of(context).padding.top + 20,
                  right: 20,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 150),
        child: Center(child: CircularProgressIndicator(color: neonCyan)),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 85.0, left: 16, right: 16, bottom: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final imageUrl = _images[index];
                final heroTag = "image_${widget.title}_$index";

                return GestureDetector(
                  onTap: () => _openFullScreenImage(imageUrl, heroTag),
                  child: Hero(
                    tag: heroTag,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: const Color(0xFF1E1E1E),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image, color: Colors.white24, size: 30)
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
              childCount: _images.length,
            ),
          ),
        ),
        
        // Niche loading spinner dikhayega jab aur images load ho rahi hongi
        if (_isFetchingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40.0, top: 10),
              child: Center(child: CircularProgressIndicator(color: neonCyan)),
            ),
          )
        else if (!_hasMoreImages && _images.length > 1)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40.0, top: 10),
              child: Center(child: Text("End of gallery", style: TextStyle(color: Colors.white38, fontSize: 12))),
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}