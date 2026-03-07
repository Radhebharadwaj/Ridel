import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/commute/shared/models/route_models.dart';

class JourneyTimelineCard extends StatefulWidget {
  final RouteResult routeData;
  const JourneyTimelineCard({super.key, required this.routeData});

  @override
  State<JourneyTimelineCard> createState() => _JourneyTimelineCardState();
}

class _JourneyTimelineCardState extends State<JourneyTimelineCard> {
  // Stores indices of expanded segments
  final Set<int> _expandedSegments = {}; 
  bool _isCardExpanded = true; 

  // --- NEW HELPER FUNCTION TO CLEAN TEXT ---
  // Ye function text ko check karega aur sirf Platform info return karega.
  // Agar "Platform" word nahi hai, to null return karega taaki badge hide ho jaye.
  String? _filterPlatformText(String? instruction) {
    if (instruction == null || instruction.isEmpty) return null;

    // Check if the instruction actually contains platform info
    if (instruction.toLowerCase().contains("platform")) {
      // Logic 1: Agar text me bullet (•) hai (Jaisa image me "Change for.. • Platform 1" hai)
      if (instruction.contains("•")) {
        List<String> parts = instruction.split("•");
        // Loop through parts to find the one with "Platform"
        for (String part in parts) {
          if (part.toLowerCase().contains("platform")) {
            return part.trim(); // Returns "Platform 1"
          }
        }
      }
      
      // Logic 2: Agar bullet nahi hai, par text lamba hai (e.g. "Change for Red Line Platform 2")
      // To hum "Platform" word dhoond kar wahan se string kaat lenge.
      int index = instruction.toLowerCase().indexOf("platform");
      if (index != -1) {
        return instruction.substring(index).trim();
      }
      
      // Fallback: Agar format simple "Platform 1" hi hai
      return instruction;
    }

    // Agar instruction me Platform mention nahi hai (e.g. sirf "Change for Pink Line"), 
    // to hum null return karenge taaki wo badge dikhe hi nahi.
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: _isCardExpanded 
          ? const EdgeInsets.all(20) 
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(_isCardExpanded ? 32 : 100),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2), 
            blurRadius: 30, 
            offset: const Offset(0, 10)
          )
        ],
      ),
      child: AnimatedCrossFade(
        // --- 1. COLLAPSED STATE (Pill Style) ---
        firstChild: GestureDetector(
          onTap: () {
            AppHaptics.lightImpact();
            setState(() => _isCardExpanded = true);
          },
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Journey Details", style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text("${widget.routeData.totalTimeMin} min • ₹${widget.routeData.totalFare}", style: GoogleFonts.inter(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
              Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.6), size: 24),
            ],
          ),
        ),

        // --- 2. EXPANDED STATE (Full Details) ---
        secondChild: Column(
          children: [
            // Top Stats Row
            Row(
              children: [
                _buildStat(Icons.schedule_rounded, "${widget.routeData.totalTimeMin} min", const Color(0xFF00E5FF)),
                const SizedBox(width: 15),
                Container(width: 1, height: 16, color: Colors.white.withOpacity(0.1)),
                const SizedBox(width: 15),
                _buildStat(Icons.swap_calls_rounded, "${widget.routeData.totalStops} Stops", Colors.orange),
                const Spacer(),
                
                // Pay Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF25D366).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Text("Pay ", style: TextStyle(color: Color(0xFF25D366), fontSize: 11, fontWeight: FontWeight.w600)),
                      Text("₹${widget.routeData.totalFare}", style: const TextStyle(color: Color(0xFF25D366), fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                
                // Collapse Button
                GestureDetector(
                  onTap: () {
                    AppHaptics.lightImpact();
                    setState(() => _isCardExpanded = false);
                  },
                  child: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white54, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 25),
            
            // Timeline Content
            _buildTimeline(),
          ],
        ),
        crossFadeState: _isCardExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        duration: const Duration(milliseconds: 300),
        sizeCurve: Curves.fastOutSlowIn,
      ),
    );
  }

  Widget _buildStat(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(text, style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }

  // 🔥 LOGIC REWRITTEN FOR ROBUSTNESS
  Widget _buildTimeline() {
    List<Widget> widgets = [];
    List<RouteStation> path = widget.routeData.path;
    if (path.isEmpty) return const SizedBox();

    // 1. Start Node
    RouteStation startNode = path.first;
    
    // Clean the text
    String? startPlatformInfo = _filterPlatformText(startNode.instruction);

    widgets.add(_buildNode(
      title: startNode.name, 
      sub: "Start Journey", 
      color: startNode.lineColor, 
      iconData: Icons.my_location_rounded,
      iconColor: const Color(0xFF00E5FF),
      // UPDATED: Use filtered text
      trailingWidget: startPlatformInfo != null 
          ? _buildBadge(startPlatformInfo, startNode.lineColor) 
          : null
    ));

    // Connector
    widgets.add(_buildConnector());

    // 2. Iterate Segments
    int i = 0;
    int segmentIndex = 0;
    
    while (i < path.length - 1) {
      String currentLineCode = path[i].lineCode; 
      int j = i + 1;
      
      while (j < path.length) {
        if (path[j].lineCode != currentLineCode) break;
        j++;
      }

      RouteStation segmentStart = path[i];
      int stopsCount = (j - 1) - i;
      String timeDisplay = "$stopsCount Stops"; 

      int currentId = segmentIndex++;
      bool isExpanded = _expandedSegments.contains(currentId);
      
      List<RouteStation> intermediateStations = [];
      if (j > i + 1) {
         intermediateStations = path.sublist(i + 1, j);
      }

      // Add Line Capsule
      widgets.add(_buildLineCapsule(
        color: segmentStart.lineColor,
        name: segmentStart.lineName,
        stops: "$stopsCount Stops",
        time: "", 
        isExpanded: isExpanded,
        intermediateStations: intermediateStations,
        onTap: () {
          AppHaptics.lightImpact();
          setState(() {
            if (isExpanded) _expandedSegments.remove(currentId); else _expandedSegments.add(currentId);
          });
        }
      ));

      // Connector
      widgets.add(_buildConnector());

      if (j < path.length) {
         RouteStation interchangeNode = path[j]; 
         
         if (j != path.length - 1) {
            // Clean the text for Interchange
            String? interchangePlatformInfo = _filterPlatformText(interchangeNode.instruction);

            // Interchange Node
            widgets.add(_buildInterchangeNode(
              title: interchangeNode.name,
              // UPDATED: Use filtered text
              platformWidget: interchangePlatformInfo != null 
                  ? _buildBadge(interchangePlatformInfo, interchangeNode.lineColor) 
                  : null
            ));
            
            widgets.add(_buildConnector());
         } 
      }
      
      // Move pointer
      i = j;
    }

    // 3. Destination Node
    RouteStation endNode = path.last;
    widgets.add(_buildNode(
      title: endNode.name, 
      sub: "Destination", 
      color: Colors.redAccent, 
      iconData: Icons.location_on_rounded,
      iconColor: Colors.redAccent,
      trailingWidget: null
    ));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  Widget _buildConnector() {
    return Padding(
      padding: const EdgeInsets.only(left: 11), 
      child: Align(
        alignment: Alignment.centerLeft, 
        child: Container(
          width: 2, 
          height: 12, 
          color: Colors.white.withOpacity(0.1)
        )
      ),
    );
  }

  Widget _buildLineCapsule({
    required Color color, required String name, required String stops, required String time,
    required bool isExpanded, required List<RouteStation> intermediateStations, required VoidCallback onTap
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(left: 4), 
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), 
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16), 
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    // Line Dot
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        if (time.isNotEmpty)
                           Text(time, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(stops, style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Icon(isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: color, size: 18)
                  ],
                )
              ],
            ),
            
            // Expandable List
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity), 
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Colors.white10),
                  const SizedBox(height: 8),
                  // Render Intermediates
                  ...intermediateStations.map((s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        // Small hollow dot
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white54, width: 1.5),
                            shape: BoxShape.circle
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          s.name, 
                          style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)
                        )
                      ],
                    ),
                  )).toList(),
                ],
              ),
              crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildNode({
    required String title, required String sub, required Color color, 
    required IconData iconData, required Color iconColor, Widget? trailingWidget
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon Box
        Container(
          width: 24, height: 24, 
          decoration: BoxDecoration(
            color: Colors.black,
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.5), width: 2)
          ),
          child: Center(child: Icon(iconData, color: iconColor, size: 12)),
        ),
        const SizedBox(width: 16),
        // Text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub, style: GoogleFonts.inter(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ),
        if (trailingWidget != null) trailingWidget,
      ],
    );
  }

  Widget _buildInterchangeNode({required String title, Widget? platformWidget}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Interchange Icon
        Container(
          width: 24, height: 24, 
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Center(child: Icon(Icons.sync_alt_rounded, color: Colors.black, size: 14)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text("Interchange", style: GoogleFonts.inter(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ),
        if (platformWidget != null) platformWidget,
      ],
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(text, style: GoogleFonts.inter(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}