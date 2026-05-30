import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';
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
        color: isLightMode ? Colors.white : const Color(0xFF151517), // True dark premium matte background
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: isLightMode ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          isLightMode 
            ? BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 24,
                offset: const Offset(0, 8),
              )
            : BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Journey Route',
                style: GoogleFonts.inter(
                  color: isLightMode ? Colors.black87 : Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, color: isLightMode ? Colors.black54 : Colors.white54, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.routeData.totalTimeMin} min',
                    style: GoogleFonts.inter(color: isLightMode ? Colors.black87 : Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 32),
          
          // Timeline
          _buildTimeline(),
          
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
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildStationRow({
    required String name,
    required Color color,
    required String? platform,
    required bool isInterchange,
    bool isEnd = false,
  }) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Glowing Dot
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: isInterchange ? Colors.white : (isLightMode ? Colors.white : const Color(0xFF151517)),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: isInterchange ? 4 : 2), // Thin border for regular stops
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4), // Muted shadow to avoid screaming neon
                blurRadius: 8,
              )
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
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
              ),
              if (platform != null) ...[
                const SizedBox(width: 8),
                _buildMicroBadge(platform, color),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccordionSegment({
    required int id,
    required Color color,
    required String lineName,
    required int stops,
    required List<RouteStation> intermediates,
  }) {
    final isExpanded = _expandedSegments.contains(id);
    final isZeroStops = intermediates.isEmpty;

    return Container(
      // 16px dot width / 2 = 8px center.
      // 7px margin + 2px border width / 2 = 8px center. Perfectly aligned continuous line!
      margin: const EdgeInsets.only(left: 7),
      padding: const EdgeInsets.only(left: 23, top: 12, bottom: 12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: color, width: 2), // Thin 2px continuous line
        ),
      ),
      child: isZeroStops
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 24), // 16px icon + 8px spacing
                  Text(
                    'Next station on $lineName',
                    style: GoogleFonts.inter(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
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
                        Text(
                          '$stops Stations on $lineName',
                          style: GoogleFonts.inter(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildMicroBadge(String text, Color color) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final titleCaseText = _toTitleCase(text);

    return Container(
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
    );
  }

  Widget _buildBookTicketCTA() {
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 24),
      child: RidelBounceButton(
        scaleFactor: 0.95,
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
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: isLightMode ? Colors.cyan.withValues(alpha: 0.1) : const Color(0xFF00E5FF).withValues(alpha: 0.1), // Translucent cyan background
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: isLightMode ? Colors.cyan.withValues(alpha: 0.4) : const Color(0xFF00E5FF).withValues(alpha: 0.4), width: 1.5), 
            boxShadow: [
              BoxShadow(
                color: isLightMode ? Colors.cyan.withValues(alpha: 0.05) : const Color(0xFF00E5FF).withValues(alpha: 0.05),
                blurRadius: 20,
              )
            ]
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_scanner_rounded, color: isLightMode ? Colors.cyan.shade600 : const Color(0xFF00E5FF), size: 20),
              const SizedBox(width: 8),
              Text(
                'Book Ticket • ₹${widget.routeData.totalFare}',
                style: GoogleFonts.inter(
                  color: isLightMode ? Colors.cyan.shade700 : const Color(0xFF00E5FF),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
