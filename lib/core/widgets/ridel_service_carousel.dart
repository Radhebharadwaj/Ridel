import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';

class RidelServiceCarousel extends StatefulWidget {
  final String title;
  final List<Widget> cards;
  final Color accentColor;

  const RidelServiceCarousel({
    super.key,
    required this.title,
    required this.cards,
    required this.accentColor,
  });

  @override
  State<RidelServiceCarousel> createState() => _RidelServiceCarouselState();
}

class _RidelServiceCarouselState extends State<RidelServiceCarousel> {
  bool _isExpanded = false;
  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0.0;

  // 🚀 FADE LOGIC VARIABLES
  bool _isIndicatorVisible = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _showIndicatorTemporarily();

    _scrollController.addListener(() {
      if (_scrollController.position.maxScrollExtent > 0) {
        setState(() {
          _scrollProgress = _scrollController.position.pixels /
              _scrollController.position.maxScrollExtent;
        });
        _showIndicatorTemporarily();
      }
    });
  }

  void _showIndicatorTemporarily() {
    // Agar grid open hai toh scroller show mat karo
    if (_isExpanded) return;

    setState(() => _isIndicatorVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _isIndicatorVisible = false);
    });
  }

  void _toggleExpand() {
    AppHaptics.lightImpact();
    setState(() {
      _isExpanded = !_isExpanded;
      // Grid khulte hi scroller ko force hide kar do
      if (_isExpanded) {
        _isIndicatorVisible = false;
      } else {
        _showIndicatorTemporarily();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _toggleExpand,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: isDark ? Colors.white54 : Colors.black54,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 350),
          sizeCurve: Curves.easeOutCubic,
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: Column(
            children: [
              SizedBox(
                height: 120,
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.transparent
                      ],
                      stops: [0.0, 0.05, 0.95, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ListView.separated(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    clipBehavior: Clip.none,
                    itemCount: widget.cards.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 14),
                    itemBuilder: (context, index) => widget.cards[index],
                  ),
                ),
              ),

              // 🚀 TERA PREMIUM GLASSY SCROLLER WAPAS AA GAYA
              if (widget.cards.length > 3) ...[
                const SizedBox(height: 16),
                AnimatedOpacity(
                  opacity: _isIndicatorVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          width: 45,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Stack(
                            children: [
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 50),
                                left: _scrollProgress * (45 - 18),
                                child: Container(
                                  width: 18,
                                  height: 5,
                                  decoration: BoxDecoration(
                                      color: widget.accentColor
                                          .withValues(alpha: 0.8),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                            color: widget.accentColor
                                                .withValues(alpha: 0.5),
                                            blurRadius: 4)
                                      ]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]
            ],
          ),
          secondChild: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                children: widget.cards,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
