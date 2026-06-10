import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart'; // 🚀 Added for Compass Icon
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart'; // 🚀 Added for button feedback
import 'package:ridel/features/commute/shared/models/route_models.dart';

class SchematicRouteMap extends StatefulWidget {
  const SchematicRouteMap({
    required this.routeData,
    super.key,
    this.isMetro = true,
    this.activeStationIndex,
    this.trackingError,
    this.onOpenRidelMap, // 🚀
    this.onOpenDeviceMap, // 🚀
  });
  final RouteResult routeData;
  final bool isMetro;
  final int? activeStationIndex;
  final String? trackingError;

  // 🚀 NAYE CALLBACKS: Navigation ke liye
  final VoidCallback? onOpenRidelMap;
  final VoidCallback? onOpenDeviceMap;

  @override
  State<SchematicRouteMap> createState() => _SchematicRouteMapState();
}

class _SchematicRouteMapState extends State<SchematicRouteMap>
    with SingleTickerProviderStateMixin {
  static const double _mapHeight = 180;
  static const double _centerY = 80;
  static const double _iconSize = 48;
  static const double _iconTop = _centerY - (_iconSize / 2);
  static const double _lineHeight = 6;
  static const double _lineTop = _centerY - (_lineHeight / 2);

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    unawaited(_pulseController.repeat(reverse: true));
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

    final mapNodes = _buildSchematicNodes();
    final hasError = widget.trackingError != null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: hasError ? const Color(0xFF2A0808) : (isLightMode ? Colors.white : const Color(0xFF0B0D12)),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: hasError
              ? Colors.redAccent.withValues(alpha: 0.5)
              : (isLightMode ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.05)),
        ),
        boxShadow: isLightMode
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                ),
              ]
            : [
                BoxShadow(
                  color: hasError
                      ? Colors.redAccent.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            if (!isLightMode)
              Positioned(
                top: -60,
                left: -40,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (widget.isMetro
                              ? widget.routeData.path.first.lineColor
                              : const Color(0xFFFF9F0A))
                          .withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),

            Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Opacity(
                  opacity: hasError ? 0.2 : 1.0,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: mapNodes,
                  ),
                ),
              ),
            ),

            // 🚨 DETAILED ERROR WARNING OVERLAY WITH 2 BUTTONS
            if (hasError)
              Container(
                width: double.infinity,
                color: Colors.black.withValues(
                  alpha: 0.4,
                ), // Darken background to make buttons pop
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          widget.trackingError!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 🚀 NEW: Two sleek buttons for map options wrapped in FittedBox
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
                ),
              ),
          ],
        ),
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

  List<Widget> _buildSchematicNodes() {
    final widgets = <Widget>[];
    final path = widget.routeData.path;
    final currentIdx = widget.activeStationIndex ?? -1;

    final startColor =
        widget.isMetro ? path.first.lineColor : const Color(0xFFFF9F0A);
    widgets.add(
      _buildSourceNode(
        path.first.name,
        startColor,
        nodeIndex: 0,
        currentIdx: currentIdx,
      ),
    );

    var i = 0;
    while (i < path.length) {
      final currentLine = path[i].lineCode;
      final segmentColor =
          widget.isMetro ? path[i].lineColor : const Color(0xFFFF9F0A);
      var j = i + 1;
      while (j < path.length && path[j].lineCode == currentLine) {
        j++;
      }
      final isLastSegment = (j == path.length);

      var intermediates = <RouteStation>[];
      final intermediateIndices = <int>[];

      if (isLastSegment) {
        if (j - 1 > i + 1) {
          intermediates = path.sublist(i + 1, j - 1);
          for (var k = i + 1; k < j - 1; k++) {
            intermediateIndices.add(k);
          }
        }
      } else {
        if (j > i + 1) {
          intermediates = path.sublist(i + 1, j);
          for (var k = i + 1; k < j; k++) {
            intermediateIndices.add(k);
          }
        }
      }

      if (intermediates.isNotEmpty) {
        for (var k = 0; k < intermediates.length; k++) {
          widgets.add(
            _buildIntermediateNode(
              intermediates[k].name,
              segmentColor,
              isTop: k % 2 == 0,
              nodeIndex: intermediateIndices[k],
              currentIdx: currentIdx,
            ),
          );
        }
      } else {
        final isPassed = currentIdx > i;
        widgets.add(
          _buildEmptyLine(
            isPassed ? Colors.white.withValues(alpha: 0.15) : segmentColor,
          ),
        );
      }

      if (isLastSegment) {
        widgets.add(
          _buildDestinationNode(
            path.last.name,
            segmentColor,
            nodeIndex: path.length - 1,
            currentIdx: currentIdx,
          ),
        );
      } else {
        final nextColor =
            widget.isMetro ? path[j].lineColor : const Color(0xFFFF9F0A);
        widgets.add(
          _buildInterchangeNode(
            path[j].name,
            segmentColor,
            nextColor,
            nodeIndex: j,
            currentIdx: currentIdx,
          ),
        );
      }
      i = j;
    }
    return widgets;
  }

  // ==================== 📍 UI BUILDERS ====================
  Widget _buildSourceNode(
    String name,
    Color color, {
    required int nodeIndex,
    required int currentIdx,
  }) {
    final isPassed = currentIdx > nodeIndex;
    final isCurrent = currentIdx == nodeIndex;
    final nodeColor = isPassed ? Colors.white.withValues(alpha: 0.2) : color;
    return SizedBox(
      width: 90,
      height: _mapHeight,
      child: Stack(
        children: [
          Positioned(
            top: _lineTop,
            left: 45,
            right: 0,
            child: _glowLine(nodeColor),
          ),
          Positioned(
            top: _iconTop,
            left: 21,
            child:
                isCurrent ? _buildLiveTracker() : _buildNeonTarget(nodeColor),
          ),
          Positioned(
            top: 115,
            left: 0,
            right: 0,
            child: _buildNodeText(name, isMain: true, isPassed: isPassed),
          ),
        ],
      ),
    );
  }

  Widget _buildInterchangeNode(
    String name,
    Color incomingColor,
    Color outgoingColor, {
    required int nodeIndex,
    required int currentIdx,
  }) {
    final isPassed = currentIdx > nodeIndex;
    final isCurrent = currentIdx == nodeIndex;

    final inColor = isPassed || isCurrent
        ? Colors.white.withValues(alpha: 0.15)
        : incomingColor;
    final outColor =
        isPassed ? Colors.white.withValues(alpha: 0.15) : outgoingColor;
    return SizedBox(
      width: 90,
      height: _mapHeight,
      child: Stack(
        children: [
          Positioned(
            top: _lineTop,
            left: 0,
            right: 45,
            child: _glowLine(inColor),
          ),
          Positioned(
            top: _lineTop,
            left: 45,
            right: 0,
            child: _glowLine(outColor),
          ),
          Positioned(
            top: _iconTop,
            left: 21,
            child: isCurrent
                ? _buildLiveTracker()
                : _buildHollowRing(isPassed: isPassed),
          ),
          Positioned(
            top: 115,
            left: 0,
            right: 0,
            child: _buildNodeText(name, isMain: true, isPassed: isPassed),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationNode(
    String name,
    Color incomingColor, {
    required int nodeIndex,
    required int currentIdx,
  }) {
    final isPassed = currentIdx > nodeIndex;
    final isCurrent = currentIdx == nodeIndex;
    final destColor = isPassed
        ? Colors.white.withValues(alpha: 0.2)
        : const Color(0xFFFF3B30);
    final inColor = isPassed || isCurrent
        ? Colors.white.withValues(alpha: 0.15)
        : incomingColor;
    return SizedBox(
      width: 90,
      height: _mapHeight,
      child: Stack(
        children: [
          Positioned(
            top: _lineTop,
            left: 0,
            right: 45,
            child: _glowLine(inColor),
          ),
          Positioned(
            top: _iconTop,
            left: 21,
            child:
                isCurrent ? _buildLiveTracker() : _buildNeonTarget(destColor),
          ),
          Positioned(
            top: 115,
            left: 0,
            right: 0,
            child: _buildNodeText(name, isMain: true, isPassed: isPassed),
          ),
        ],
      ),
    );
  }

  Widget _buildIntermediateNode(
    String name,
    Color color, {
    required bool isTop,
    required int nodeIndex,
    required int currentIdx,
  }) {
    final isPassed = currentIdx > nodeIndex;
    final isCurrent = currentIdx == nodeIndex;
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final lineColor =
        isPassed || isCurrent ? Colors.white.withValues(alpha: 0.15) : color;
    return SizedBox(
      width: 80,
      height: _mapHeight,
      child: Stack(
        children: [
          Positioned(
            top: _lineTop,
            left: 0,
            right: 0,
            child: _glowLine(lineColor),
          ),
          Positioned(
            top: _centerY - (isCurrent ? 8 : 6),
            left: isCurrent ? 32 : 34,
            child: isCurrent
                ? _buildSmallLiveTracker()
                : Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isLightMode ? Colors.white : const Color(0xFF0B0D12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isLightMode 
                            ? (isPassed ? Colors.black26 : Colors.black87)
                            : (isPassed ? Colors.white24 : Colors.white),
                        width: 2.5,
                      ),
                    ),
                  ),
          ),
          if (isTop)
            Positioned(
              bottom: 110,
              left: 0,
              right: 0,
              child: _buildNodeText(name, isMain: false, isPassed: isPassed),
            ),
          if (!isTop)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: _buildNodeText(name, isMain: false, isPassed: isPassed),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyLine(Color color) {
    return SizedBox(
      width: 50,
      height: _mapHeight,
      child: Stack(
        children: [
          Positioned(top: _lineTop, left: 0, right: 0, child: _glowLine(color)),
        ],
      ),
    );
  }

  // ==================== 📡 LIVE TRACKER WIDGETS ====================
  Widget _buildLiveTracker() {
    return SizedBox(
      width: _iconSize,
      height: _iconSize,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: _iconSize * (0.5 + (_pulseController.value * 0.5)),
                height: _iconSize * (0.5 + (_pulseController.value * 0.5)),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blueAccent
                      .withValues(alpha: 1.0 - _pulseController.value),
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.8),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSmallLiveTracker() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.blueAccent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.blue
                    .withValues(alpha: 0.6 + (_pulseController.value * 0.4)),
                blurRadius: 8,
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== 🎨 STYLING HELPERS ====================
  Widget _glowLine(Color color) {
    return Container(
      height: _lineHeight,
      decoration: BoxDecoration(
        color: color,
        boxShadow: color.a > 0.3
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildNeonTarget(Color color) {
    return SizedBox(
      width: _iconSize,
      height: _iconSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
            ),
          ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3.5),
              boxShadow: color.a > 0.3
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildHollowRing({required bool isPassed}) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return SizedBox(
      width: _iconSize,
      height: _iconSize,
      child: Center(
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isLightMode ? Colors.white : const Color(0xFF0B0D12),
            shape: BoxShape.circle,
            border: Border.all(
              color: isLightMode
                  ? (isPassed ? Colors.black26 : Colors.black87)
                  : (isPassed ? Colors.white24 : Colors.white),
              width: 4,
            ),
            boxShadow: isPassed
                ? null
                : [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ],
          ),
        ),
      ),
    );
  }

  Widget _buildNodeText(
    String name, {
    required bool isMain,
    required bool isPassed,
  }) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final textColor = isLightMode
        ? (isPassed ? Colors.black38 : Colors.black87)
        : (isMain ? (isPassed ? Colors.white38 : Colors.white.withValues(alpha: 0.95)) : (isPassed ? Colors.white24 : Colors.white.withValues(alpha: 0.6)));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        name.toUpperCase(),
        textAlign: TextAlign.center,
        maxLines: isMain ? 3 : 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: textColor,
          fontSize: isMain ? 10 : 8.5,
          letterSpacing: 0.5,
          fontWeight: isMain ? FontWeight.bold : FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}
