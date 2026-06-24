import re

with open("lib/features/commute/shared/widgets/schematic_route_map.dart", "r") as f:
    content = f.read()

# I will write a script to rewrite `class _SchematicRouteMapState extends State<SchematicRouteMap>`
new_state = """import 'dart:ui'; // Needed for ImageFilter

class _SchematicRouteMapState extends State<SchematicRouteMap>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseController.repeat(reverse: true);
  }

  // 🚀 Premium Title Case Formatter
  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _showTimelineSheet(BuildContext context, int currentIdx, Color activeColor, bool isLightMode) {
    AppHaptics.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: isLightMode
                ? Colors.white.withValues(alpha: 0.85)
                : const Color(0xFF1C1C1E).withValues(alpha: 0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.15),
                width: 0.5,
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Drag Pill
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isLightMode ? Colors.black26 : Colors.white38,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Journey Details",
                    style: GoogleFonts.inter(
                      color: isLightMode ? Colors.black87 : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                      itemCount: widget.routeData.path.length,
                      itemBuilder: (context, index) {
                        final station = widget.routeData.path[index];
                        final isPassed = currentIdx > index;
                        final isCurrent = currentIdx == index;
                        final isFuture = currentIdx < index;
                        final isLast = index == widget.routeData.path.length - 1;

                        final textColor = isPassed 
                            ? (isLightMode ? Colors.black38 : Colors.white38)
                            : (isLightMode ? Colors.black87 : Colors.white);

                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Column(
                                children: [
                                  // Node
                                  if (isCurrent)
                                    _buildPulseNode(size: 20)
                                  else
                                    Container(
                                      width: 16,
                                      height: 16,
                                      margin: const EdgeInsets.symmetric(vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isPassed ? (isLightMode ? Colors.black26 : Colors.white24) : activeColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isLightMode ? Colors.white : const Color(0xFF1C1C1E),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  // Line
                                  if (!isLast)
                                    Expanded(
                                      child: Container(
                                        width: 3,
                                        color: isPassed ? (isLightMode ? Colors.black12 : Colors.white12) : activeColor.withValues(alpha: 0.5),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 32.0, top: 0),
                                  child: Text(
                                    _toTitleCase(station.name),
                                    style: GoogleFonts.inter(
                                      color: textColor,
                                      fontSize: 16,
                                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    if (widget.routeData.path.isEmpty) return const SizedBox();

    final hasError = widget.trackingError != null;
    final path = widget.routeData.path;
    final originName = _toTitleCase(path.first.name);
    final destinationName = _toTitleCase(path.last.name);
    
    // Calculate progress
    final int currentIdx = widget.activeStationIndex ?? -1;
    final double progress = path.isEmpty ? 0.0 : (currentIdx >= 0 ? currentIdx / (path.length - 1) : 0.0).clamp(0.0, 1.0);
    
    final activeColor = widget.isMetro ? path.first.lineColor : const Color(0xFFFF9F0A);
    
    // Dynamic Context Text
    String floatingText = "";
    if (currentIdx == -1) {
      floatingText = "Starting Journey...";
    } else if (currentIdx >= path.length - 1) {
      floatingText = "Arrived at Destination";
    } else {
      floatingText = "Next: ${_toTitleCase(path[currentIdx + 1].name)}";
    }

    return Container(
      width: double.infinity,
      height: 140, // Fixed height for the new dynamic island layout
      decoration: BoxDecoration(
        color: hasError 
            ? const Color(0xFF2A0808) 
            : (isLightMode
                ? Colors.white.withValues(alpha: 0.90)
                : const Color(0xFF161A25).withValues(alpha: 0.75)),
        borderRadius: BorderRadius.circular(35),
        border: Border.all(
          color: hasError
              ? Colors.redAccent.withValues(alpha: 0.5)
              : (isLightMode
                  ? Colors.black.withValues(alpha: 0.04)
                  : Colors.white.withValues(alpha: 0.12)),
          width: 1.0,
        ),
        boxShadow: hasError 
            ? [
                BoxShadow(
                  color: Colors.redAccent.withValues(alpha: 0.2),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                )
              ]
            : (isLightMode
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8))
                  ]
                : [
                    ...AppShadows.cardFloating,
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 40,
                      spreadRadius: 8,
                      offset: const Offset(0, 15),
                    ),
                  ]),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(35),
          onTap: () {
            if (!hasError) {
              _showTimelineSheet(context, currentIdx, activeColor, isLightMode);
            }
          },
          splashColor: isLightMode ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.05),
          highlightColor: Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Tap-to-Expand Pill
              if (!hasError)
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isLightMode ? Colors.black26 : Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              // Main Content
              Padding(
                padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 16),
                child: hasError
                    ? _buildErrorOverlay()
                    : _buildLiveTrackerLayout(progress, activeColor, floatingText, originName, destinationName, isLightMode, path.length),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveTrackerLayout(double progress, Color activeColor, String floatingText, String originName, String destinationName, bool isLightMode, int totalStations) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Floating Context Text
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0, right: 0, bottom: 8,
                    child: Align(
                      // Align handles keeping the text within bounds gracefully
                      alignment: Alignment(progress * 2 - 1, 1.0),
                      child: Text(
                        floatingText,
                        style: GoogleFonts.inter(
                          color: isLightMode ? Colors.black87 : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        
        // Dynamic Track
        LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            final activeWidth = trackWidth * progress;
            
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                // Background Track
                Container(
                  height: 6,
                  width: trackWidth,
                  decoration: BoxDecoration(
                    color: isLightMode ? Colors.black12 : Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                
                // Intermediate Station Dots
                if (totalStations > 2)
                  ...List.generate(totalStations - 2, (index) {
                    final dotProgress = (index + 1) / (totalStations - 1);
                    final dotPosition = trackWidth * dotProgress;
                    final isDotPassed = progress >= dotProgress;
                    
                    return Positioned(
                      left: dotPosition - 2, // center the 4px dot
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDotPassed ? Colors.transparent : (isLightMode ? Colors.black26 : Colors.white38),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),

                // Active Progress Track
                Container(
                  height: 6,
                  width: activeWidth,
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.5),
                        blurRadius: 8,
                      )
                    ],
                  ),
                ),
                
                // Live Pulsing Indicator at the tip
                Positioned(
                  left: activeWidth - 16, // Center the 32x32 pulse circle
                  child: _buildPulseNode(),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        // Origin and Destination texts
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                originName,
                style: GoogleFonts.inter(
                  color: isLightMode ? Colors.black54 : Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                destinationName,
                style: GoogleFonts.inter(
                  color: isLightMode ? Colors.black54 : Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPulseNode({double size = 32}) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 0.2 + (_pulseController.value * 0.6),
              child: Container(
                width: size,
                height: size,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Container(
              width: size / 2,
              height: size / 2,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.white.withValues(alpha: 0.8), blurRadius: 10),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildErrorOverlay() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_off_rounded,
              color: Colors.redAccent,
              size: 28,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.trackingError!,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildMapButton(
                  title: 'Ridel Maps',
                  icon: Icons.map_rounded,
                  onTap: widget.onOpenRidelMap,
                ),
                const SizedBox(width: 12),
                _buildMapButton(
                  title: 'Device Map',
                  icon: CupertinoIcons.compass,
                  onTap: widget.onOpenDeviceMap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🚀 BUTTON BUILDER: Exact match from your image
  Widget _buildMapButton({
    required String title,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: () {
        AppHaptics.mediumImpact();
        if (onTap != null) onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
"""

content = re.sub(r'class _SchematicRouteMapState extends State<SchematicRouteMap>.*', new_state, content, flags=re.DOTALL)

with open("lib/features/commute/shared/widgets/schematic_route_map.dart", "w") as f:
    f.write("import 'dart:ui';\n" + content.replace("import 'dart:ui'; // Needed for ImageFilter\n\n", ""))

