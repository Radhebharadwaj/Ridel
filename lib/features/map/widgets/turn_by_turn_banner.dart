import 'dart:ui';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/map/map_provider.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';
import 'package:ridel/core/utils/route_utils.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

class TurnByTurnBanner extends StatefulWidget {
  final bool isDark;

  const TurnByTurnBanner({super.key, required this.isDark});

  @override
  State<TurnByTurnBanner> createState() => _TurnByTurnBannerState();
}

class _TurnByTurnBannerState extends State<TurnByTurnBanner> {
  bool _isStepsExpanded = false;
  bool _isDashVisible = false;
  Timer? _hideHandleTimer;

  @override
  void initState() {
    super.initState();
    _pokeDragHandle();
  }

  @override
  void dispose() {
    _hideHandleTimer?.cancel();
    super.dispose();
  }

  void _pokeDragHandle() {
    setState(() => _isDashVisible = true);
    _hideHandleTimer?.cancel();
    _hideHandleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isDashVisible = false);
    });
  }

  // ── Premium design tokens ──
  static const Color _accentCyan = Color(0xFF32D7E0);
  static const Color _accentGreen = Color(0xFF30D158);
  static const Color _accentBlue = Color(0xFF0A84FF);

  void _toggleExpanded() {
    setState(() {
      _isStepsExpanded = !_isStepsExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLight = !widget.isDark;

    // Frosted glass — exact WeatherFloatingWidget match
    final glassColor = isLight
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF0B0E17).withValues(alpha: 0.75);

    final borderColor = isLight
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.white.withValues(alpha: 0.1);

    double bannerWidth = MediaQuery.sizeOf(context).width - 32;

    return Selector<MapProvider, bool>(
        selector: (context, provider) => provider.isActiveNavigation,
        builder: (context, show, child) {
          return IgnorePointer(
            ignoring: !show,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: show ? 1.0 : 0.0,
              child: child,
            ),
          );
        },
        child: Align(
          alignment: Alignment.topCenter,
          child: TapRegion(
            onTapOutside: (_) {
              if (_isStepsExpanded) _toggleExpanded();
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => _pokeDragHandle(),
              onHover: (_) => _pokeDragHandle(),
              // Black-hole gesture swallowing — prevents map touch bleed
              child: Listener(
                onPointerDown: (_) {
                  _pokeDragHandle();
                },
                onPointerMove: (_) {
                  _pokeDragHandle();
                },
                behavior: HitTestBehavior.opaque,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {},
                  onPanEnd: (details) {
                    if (details.velocity.pixelsPerSecond.dy > 0 &&
                        !_isStepsExpanded) {
                      _toggleExpanded();
                    } else if (details.velocity.pixelsPerSecond.dy < 0 &&
                        _isStepsExpanded) {
                      _toggleExpanded();
                    }
                  },
                  child: RidelBounceButton(
                    onTap: _toggleExpanded,
                    scaleFactor: 0.97,
                    child: Container(
                      width: bannerWidth,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(42),
                        boxShadow: [
                          if (isLight)
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 40,
                              spreadRadius: 0,
                              offset: const Offset(0, 16),
                            )
                          else ...[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 32,
                              offset: const Offset(0, 14),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ],
                      ),
                      child: RepaintBoundary(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(42),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                            child: PointerInterceptor(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: glassColor,
                                  border: Border.all(
                                    color: borderColor,
                                    width: 0.5,
                                  ),
                                ),
                                child: AnimatedSize(
                                  duration: const Duration(milliseconds: 380),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildHeader(isLight),
                                      if (_isStepsExpanded)
                                        _buildExpandedSteps(isLight),
                                      _buildDragHandle(isLight),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
  }

  // ────────────────────────────────────────────
  // HEADER — Main Direction + Distance
  // ────────────────────────────────────────────
  Widget _buildHeader(bool isLight) {
    final primaryText = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final mapProvider = Provider.of<MapProvider>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      child: Row(
        children: [
          // Soft squircle icon
          _SoftIcon(
            icon: CupertinoIcons.arrow_turn_up_left,
            color: isLight ? _accentBlue : _accentCyan,
            size: 50,
            iconSize: 24,
            isLight: isLight,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: mapProvider.engine.navigation.distanceToNextTurn,
                  builder: (context, distance, child) {
                    return Text(
                      RouteUtils.formatDistance(distance),
                      style: GoogleFonts.inter(
                        color: isLight ? _accentBlue : _accentCyan,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                        height: 1.0,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Main Mangal Bazar Road',
                  style: GoogleFonts.inter(
                    color: primaryText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Minimal ETA capsule
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: isLight
                  ? Colors.black.withValues(alpha: 0.04)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
            ),
            child: ValueListenableBuilder<double>(
              valueListenable: mapProvider.engine.navigation.remainingDuration,
              builder: (context, duration, child) {
                final mins = (duration / 60).floor();
                return Text(
                  '$mins min',
                  style: GoogleFonts.inter(
                    color: isLight
                        ? Colors.black.withValues(alpha: 0.45)
                        : Colors.white.withValues(alpha: 0.50),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────
  // EXPANDED STEPS — Timeline
  // ────────────────────────────────────────────
  Widget _buildExpandedSteps(bool isLight) {
    final divider = isLight
        ? Colors.black.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.06);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Separator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Container(height: 0.5, color: divider),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.38,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                _StepTile(
                  icon: CupertinoIcons.arrow_turn_up_right,
                  distance: '100 m',
                  road: 'Turn right onto Subhash Marg',
                  isLight: isLight,
                  showConnector: true,
                ),
                _StepTile(
                  icon: CupertinoIcons.arrow_up,
                  distance: '2.5 km',
                  road: 'Continue straight',
                  isLight: isLight,
                  showConnector: true,
                ),
                _StepTile(
                  icon: CupertinoIcons.star_fill,
                  distance: 'Stop',
                  road: 'Qutub Minar',
                  isLight: isLight,
                  showConnector: true,
                  accent: _accentBlue,
                ),
                _StepTile(
                  icon: CupertinoIcons.flag_fill,
                  distance: '3.2 km',
                  road: 'Arrive at destination',
                  isLight: isLight,
                  showConnector: false,
                  accent: _accentGreen,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────
  // DRAG HANDLE — Minimal pill
  // ────────────────────────────────────────────
  Widget _buildDragHandle(bool isLight) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _isDashVisible ? 1.0 : 0.0,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 2),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: isLight
                ? Colors.black.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// _SoftIcon — iOS-style squircle icon container
// ══════════════════════════════════════════════
class _SoftIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final bool isLight;

  const _SoftIcon({
    required this.icon,
    required this.color,
    this.size = 44,
    this.iconSize = 20,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isLight ? 0.09 : 0.12),
        borderRadius: BorderRadius.circular(size * 0.45),
      ),
      child: Center(
        child: Icon(icon, color: color, size: iconSize),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// _StepTile — Single timeline step with
//             soft icon + vertical connector
// ══════════════════════════════════════════════
class _StepTile extends StatelessWidget {
  final IconData icon;
  final String distance;
  final String road;
  final bool isLight;
  final bool showConnector;
  final Color? accent;

  const _StepTile({
    required this.icon,
    required this.distance,
    required this.road,
    required this.isLight,
    required this.showConnector,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor = accent ??
        (isLight
            ? Colors.black.withValues(alpha: 0.40)
            : Colors.white.withValues(alpha: 0.45));

    final Color primaryText = isLight ? const Color(0xFF1A1A1A) : Colors.white;
    final Color secondaryText = isLight
        ? Colors.black.withValues(alpha: 0.42)
        : Colors.white.withValues(alpha: 0.50);
    final Color connectorColor = isLight
        ? Colors.black.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.07);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Timeline rail ──
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  const SizedBox(height: 2),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: isLight ? 0.07 : 0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Icon(icon, color: iconColor, size: 16),
                    ),
                  ),
                  if (showConnector)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Container(
                          width: 1.5,
                          decoration: BoxDecoration(
                            color: connectorColor,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ── Text ──
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  top: 4,
                  bottom: showConnector ? 20 : 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      distance,
                      style: GoogleFonts.inter(
                        color: primaryText,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      road,
                      style: GoogleFonts.inter(
                        color: secondaryText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
