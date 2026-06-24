import re

with open("lib/features/commute/shared/widgets/schematic_route_map.dart", "r") as f:
    content = f.read()

# Replace everything from "class _SchematicRouteMapState" to the end of the file
new_state = """class _SchematicRouteMapState extends State<SchematicRouteMap>
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
    final double progress = path.isEmpty ? 0 : (currentIdx >= 0 ? currentIdx / (path.length - 1) : 0).clamp(0.0, 1.0);
    
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // If error, show error overlay instead
          if (hasError)
            _buildErrorOverlay()
          else
            _buildLiveTrackerLayout(progress, activeColor, floatingText, originName, destinationName, isLightMode),
        ],
      ),
    );
  }

  Widget _buildLiveTrackerLayout(double progress, Color activeColor, String floatingText, String originName, String destinationName, bool isLightMode) {
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
                    left: 0, right: 0, bottom: 12,
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

  Widget _buildPulseNode() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 0.2 + (_pulseController.value * 0.6),
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Container(
              width: 16,
              height: 16,
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
    f.write(content)
