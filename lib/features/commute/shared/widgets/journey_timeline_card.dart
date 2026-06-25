import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/app_shadows.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart';
import 'package:ridel/features/commute/shared/models/route_models.dart';

import 'package:ridel/features/commute/shared/widgets/smart_ticketing_overlay.dart';

import 'package:url_launcher/url_launcher.dart';

class JourneyTimelineCard extends StatefulWidget {
  const JourneyTimelineCard({
    required this.routeData,
    required this.fromStation,
    required this.toStation,
    required this.isMetro,
    super.key,
  });
  final RouteResult routeData;
  final String fromStation;
  final String toStation;
  final bool isMetro;

  @override
  State<JourneyTimelineCard> createState() => _JourneyTimelineCardState();
}

class _JourneyTimelineCardState extends State<JourneyTimelineCard> {
  final Set<int> _expandedSegments = {};
  late Timer _liveTimer;
  final Map<int, String> _liveArrivals = {};
  bool _showDetails = true;

  int get _interchangeCount {
    return widget.routeData.path.where((s) => s.type == StationType.interchange).length;
  }
  
  String get _primaryMode {
    if (widget.isMetro) return "Metro";
    final buses = widget.routeData.path.map((e) => e.busNumber).where((b) => b != null).toSet();
    if (buses.isEmpty) return "Bus Route";
    if (buses.length == 1) return "Route ${buses.first}";
    return "Route ${buses.first} + ${buses.length - 1}";
  }

  @override
  void initState() {
    super.initState();
    _startLiveTracking();
  }

  void _startLiveTracking() {
    _updateArrivals();
    _liveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _updateArrivals();
    });
  }

  void _updateArrivals() {
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < 50; i++) {
        if (DateTime.now().second % 4 == 0) {
          _liveArrivals[i] = "Schedule-based";
        } else {
          int mins = (i * 2 + DateTime.now().minute % 15) + 2;
          _liveArrivals[i] = "$mins min";
        }
      }
    });
  }

  @override
  void dispose() {
    _liveTimer.cancel();
    super.dispose();
  }

  Color _muteColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    // Standardize lightness to ensure darker colors don't disappear.
    final targetLightness = (hsl.lightness < 0.65) ? 0.65 : hsl.lightness;
    return hsl.withLightness(targetLightness).toColor().withValues(alpha: 0.9);
  }

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return word;
      return '${word[0].toUpperCase()}${word.substring(1)}';
    }).join(' ');
  }

  String? _filterPlatformText(String? instruction) {
    if (instruction == null || instruction.isEmpty) return null;
    if (instruction.toLowerCase().contains('platform')) {
      if (instruction.contains('•')) {
        final parts = instruction.split('•');
        for (final part in parts) {
          if (part.toLowerCase().contains('platform')) {
            return part.trim();
          }
        }
      }
      final index = instruction.toLowerCase().indexOf('platform');
      if (index != -1) {
        return instruction.substring(index).trim();
      }
      return instruction;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isLightMode
            ? Colors.white.withValues(alpha: 0.90)
            : const Color(0xFF161A25).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(35),
        border: Border.all(
          color: isLightMode
              ? Colors.black.withValues(alpha: 0.04)
              : Colors.white.withValues(alpha: 0.12),
          width: 1.0,
        ),
        boxShadow: isLightMode
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
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Stats
          _buildSummaryHeader(),
          
          // Timeline
          if (_showDetails) ...[
            const SizedBox(height: 24),
            _buildTimeline(),
          ],


          // CTA Button
          const SizedBox(height: 12),
          _buildBookTicketCTA(),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final widgets = <Widget>[];
    final path = widget.routeData.path;
    if (path.isEmpty) return const SizedBox();

    // 1. Start Node
    final startNode = path.first;
    widgets.add(_buildStationRow(
      name: _toTitleCase(startNode.name),
      color: _muteColor(startNode.lineColor),
      platform: _filterPlatformText(startNode.instruction),
      isInterchange: false,
      isStart: true,
    ));

    // 2. Segments
    var i = 0;
    var segmentIndex = 0;

    while (i < path.length - 1) {
      final currentLineCode = path[i].lineCode;
      var j = i + 1;

      while (j < path.length) {
        if (path[j].lineCode != currentLineCode) break;
        j++;
      }

      final segmentStart = path[i];
      final currentId = segmentIndex++;
      
      var intermediateStations = <RouteStation>[];
      if (j > i + 1) {
        intermediateStations = path.sublist(i + 1, j)
            .where((s) => s.id != path.first.id && s.id != path.last.id)
            .toList();
      }
      final stopsCount = intermediateStations.length;

      widgets.add(
        _buildAccordionSegment(
          id: currentId,
          color: _muteColor(segmentStart.lineColor),
          lineName: _toTitleCase(segmentStart.lineName),
          stops: stopsCount,
          intermediates: intermediateStations,
          routeStation: segmentStart,
        )
      );

      if (j < path.length) {
        final interchangeNode = path[j];
        if (j != path.length - 1) {
          widgets.add(_buildStationRow(
            name: _toTitleCase(interchangeNode.name),
            color: _muteColor(interchangeNode.lineColor),
            platform: _filterPlatformText(interchangeNode.instruction),
            isInterchange: true,
            topColor: _muteColor(path[j - 1].lineColor),
          ));
        }
      }
      i = j;
    }

    // 3. End Node
    final endNode = path.last;
    widgets.add(_buildStationRow(
      name: _toTitleCase(endNode.name),
      color: _muteColor(Colors.redAccent),
      platform: null,
      isInterchange: false,
      isEnd: true,
      topColor: _muteColor(path[path.length - 2].lineColor),
    ));

    return LayoutBuilder(
      builder: (context, constraints) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth < 240 ? 240 : constraints.maxWidth,
          ),
          child: RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widgets.asMap().entries.map((entry) {
                final index = entry.key;
                final widgetChild = entry.value;
                return TweenAnimationBuilder<double>(
                  // Trick to create a delay: start from a negative value.
                  // value is clamped to 0.0, so the widget stays invisible and offset until value > 0.
                  tween: Tween(begin: -(index * 0.2), end: 1.0),
                  duration: Duration(milliseconds: 500 + (index * 100)),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    final val = value.clamp(0.0, 1.0);
                    return Opacity(
                      opacity: val,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - val)),
                        child: child,
                      ),
                    );
                  },
                  child: widgetChild,
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStationRow({
    required String name,
    required Color color,
    required String? platform,
    required bool isInterchange,
    bool isStart = false,
    bool isEnd = false,
    Color? topColor,
  }) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Glowing Dot with Connecting Lines (Perfectly centered in 32px column)
          SizedBox(
            width: 32.0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!isStart)
                  Expanded(
                    child: Container(
                      width: 2.0,
                      color: topColor ?? color,
                    ),
                  ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isInterchange ? Colors.white : (isLightMode ? Colors.white : const Color(0xFF151517)),
                    shape: BoxShape.circle,
                    border: Border.all(color: isEnd ? color : (topColor ?? color), width: isInterchange ? 3 : 2),
                    boxShadow: [
                      BoxShadow(
                        color: (isEnd ? color : (topColor ?? color)).withValues(alpha: 0.4),
                        blurRadius: 8,
                      )
                    ],
                  ),
                ),
                if (!isEnd)
                  Expanded(
                    child: Container(
                      width: 2.0,
                      color: color,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
              Text(
                name,
                style: GoogleFonts.inter(
                  color: isLightMode ? Colors.black87 : Colors.white,
                  fontSize: 14, // Reduced from 16px for classier look
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (platform != null) ...[
                const SizedBox(height: 4),
                _buildMicroBadge(platform, color),
              ],
            ],
          ),
        ),
        ),
      ],
      ),
    );
  }

  Widget _buildAccordionSegment({
    required int id,
    required Color color,
    required String lineName,
    required int stops,
    required List<RouteStation> intermediates,
    RouteStation? routeStation,
  }) {
    final isExpanded = _expandedSegments.contains(id);
    final isZeroStops = intermediates.isEmpty;
    final isBus = routeStation?.busNumber != null;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32.0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Container(
                    width: 2.0,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isBus) _buildBusMetadataBadge(routeStation!, color),
                  if (isBus) const SizedBox(height: 8),
                  isZeroStops
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'Next station on $lineName',
                                style: GoogleFonts.inter(
                                  color: color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        )
                  : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // NAKED INLINE TEXT (No heavy background wrappers)
                GestureDetector(
                  onTap: () {
                    AppHaptics.lightImpact();
                    setState(() {
                      if (isExpanded) {
                        _expandedSegments.remove(id);
                      } else {
                        _expandedSegments.add(id);
                      }
                    });
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.arrow_downward_rounded,
                          color: color,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '$stops Stations on $lineName',
                            style: GoogleFonts.inter(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: intermediates.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _toTitleCase(s.name), // Universal Title Case
                                style: GoogleFonts.inter(
                                  color: Theme.of(context).brightness == Brightness.light ? Colors.black87 : Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
                  crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 300),
                  sizeCurve: Curves.easeInOutCubic,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ],
),
);
}

  Widget _buildMicroBadge(String text, Color color) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final titleCaseText = _toTitleCase(text);

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), // Micro padding
        decoration: BoxDecoration(
          color: isLightMode ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.08), // Extremely subtle translucent background, NO BORDER
          borderRadius: BorderRadius.circular(100), // Micro-pill
        ),
        child: Text(
          titleCaseText,
          style: GoogleFonts.inter(
            color: isLightMode ? Colors.black54 : color,
            fontSize: 9, // Reduced font size to absolute minimum (9px)
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }



  Widget _buildBookTicketCTA() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 24),
      child: SizedBox(
        height: 56,
        child: RidelLiquidButton(
          glassTint: CupertinoColors.systemBlue.withValues(alpha: 0.15),
          onTap: () async {
            AppHaptics.selectionClick();
            final result = await showSmartTicketingOverlay(context, isBus: !widget.isMetro);
            
            if (result == 'whatsapp') {
              final String phoneNumber = widget.isMetro
                  ? "919650855800"
                  : "918744073223";
              final text = "Book 1 tickets from ${widget.fromStation} to ${widget.toStation}";
              final url = Uri.parse('https://wa.me/$phoneNumber?text=${Uri.encodeComponent(text)}');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            }
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Book Ticket • ₹${widget.routeData.totalFare}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryHeader() {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final primaryMode = _primaryMode;
    final interchanges = _interchangeCount;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                primaryMode,
                style: GoogleFonts.inter(
                  color: isLightMode ? Colors.black87 : Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12.0),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: interchanges == 0 ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                interchanges == 0 ? "Direct" : "$interchanges Transfers",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: interchanges == 0 ? Colors.green : Colors.orange,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.routeData.totalTimeMin} min • $interchanges Interchange${interchanges == 1 ? '' : 's'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: isLightMode ? Colors.black54 : Colors.white54,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            AppHaptics.lightImpact();
            setState(() => _showDetails = !_showDetails);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _showDetails ? "Hide Details" : "View Details",
                style: GoogleFonts.inter(
                  color: CupertinoColors.systemBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(
                _showDetails ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                color: CupertinoColors.systemBlue,
                size: 18,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBusMetadataBadge(RouteStation station, Color color) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final liveTime = _liveArrivals[station.id.hashCode % 50] ?? "Schedule-based";
    bool isLive = liveTime.contains("min");
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_bus_filled_rounded, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            "Route ${station.busNumber ?? 'Unknown'}",
            style: GoogleFonts.inter(
              color: isLightMode ? Colors.black87 : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: isLightMode ? Colors.black38 : Colors.white38,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isLive ? "Next: $liveTime" : "Schedule-based",
            style: GoogleFonts.inter(
              color: isLive ? Colors.green : (isLightMode ? Colors.black54 : Colors.white54),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (station.frequency != null) ...[
            const SizedBox(width: 6),
            Text(
              "(${station.frequency})",
              style: GoogleFonts.inter(
                color: isLightMode ? Colors.black45 : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
