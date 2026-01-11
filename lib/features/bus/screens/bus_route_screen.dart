import 'package:flutter/material.dart';

import 'dart:async';
import '../../../core/utils/app_haptics.dart';

class BusRouteScreen extends StatefulWidget {
  const BusRouteScreen({super.key});

  @override
  State<BusRouteScreen> createState() => _BusRouteScreenState();
}

class _BusRouteScreenState extends State<BusRouteScreen> with TickerProviderStateMixin {
  final String fromStation = "Laxmi Nagar";
  final String toStation = "Noida Sec 18";
  
  int _timeIndex = 0;
  final List<String> _arrivalTimes = [
    "Arriving in 4 min", 
    "Arriving in 19 min", 
    "10:45 AM", 
    "11:15 AM"
  ];

  final PageController _pageController = PageController();
  int _activePage = 0;
  Timer? _carouselTimer;
  
  bool _isStepsExpanded = false;

  @override
  void initState() {
    super.initState();
    _startAutoSlide();
  }

  void _startAutoSlide() {
    _carouselTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (_pageController.hasClients) {
        int nextPage = _activePage + 1;
        if (nextPage > 1) nextPage = 0;
        _pageController.animateToPage(
          nextPage, 
          duration: const Duration(milliseconds: 800), 
          curve: Curves.fastOutSlowIn
        );
      }
    });
  }

  void _cycleTime(int direction) {
    AppHaptics.tickImpact(); // Feel: Cycle time
    setState(() {
      _timeIndex = (_timeIndex + direction) % _arrivalTimes.length;
      if (_timeIndex < 0) _timeIndex = _arrivalTimes.length - 1;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _carouselTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ✅ OPTIMIZATION: Replaced Blur with BoxShadow
          Positioned(
            top: -100, right: -50,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.1),
                    blurRadius: 150,
                    spreadRadius: 20,
                  )
                ]
              ),
            ),
          ),

          // 2. Main Content
          Column(
            children: [
              _buildGlassHeader(topPadding),
              
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 15),
                      
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildCompactSummaryCard(),
                      ),
                      
                      const SizedBox(height: 25),

                      // --- MAP PLACEHOLDER ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          height: 180,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF151515),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.map_rounded, color: Colors.white.withValues(alpha: 0.2), size: 40),
                                const SizedBox(height: 10),
                                Text("Route Map", style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 25),

                      // --- SLIDER TITLE ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Journey Options", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            Row(
                              children: List.generate(2, (index) => AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.only(left: 6),
                                height: 4, width: _activePage == index ? 16 : 4,
                                decoration: BoxDecoration(
                                  color: _activePage == index ? Colors.orange : Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              )),
                            )
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      // --- PREMIUM CARDS ---
                      SizedBox(
                        height: 240, 
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: (index) => setState(() => _activePage = index),
                          children: [
                            _buildJourneyCard(
                              type: "FASTEST",
                              color: Colors.blueAccent,
                              content: _buildCleanInterchangeInfo(),
                              badgeText: "Save 10 min",
                            ),
                            _buildJourneyCard(
                              type: "DIRECT",
                              color: Colors.green,
                              content: _buildDirectBusInfo(),
                              badgeText: "No Change",
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 15),

                      // --- COLLAPSIBLE STEP GUIDE ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildCollapsibleStepGuide(),
                      ),
                      
                      const SizedBox(height: 50),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildGlassHeader(double topPadding) {
    return Container(
      padding: EdgeInsets.only(top: topPadding + 10, bottom: 15, left: 20, right: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF151515).withValues(alpha: 0.95), // Solid background for performance
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () {
               AppHaptics.lightImpact(); // FEEL: Back
               Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.1)),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
            ),
          ),
          const Text("Route Details", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          
          // PREMIUM PAY BUTTON
          GestureDetector(
            onTap: () {
               AppHaptics.mediumImpact(); // FEEL: Pay
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.grey.shade900, Colors.black],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)), 
                boxShadow: [
                    BoxShadow(color: Colors.white.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
                ]
              ),
              child: const Row(
                children: [
                  Text("Pay Now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  SizedBox(width: 6),
                  Icon(Icons.payment, color: Colors.white70, size: 14)
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJourneyCard({required String type, required Color color, required Widget content, required String badgeText}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                          child: Text(type, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ),
                        Row(
                          children: [
                            Icon(Icons.bolt, color: Colors.yellow.shade700, size: 12),
                            const SizedBox(width: 4),
                            Text(badgeText, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: content),
                  ],
                ),
              ),
            ),
            Container(
              height: 45,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF0A0A0A),
                border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () { },
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Text("Full Schedule", style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      InkWell(
                        onTap: () => _cycleTime(-1),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(Icons.arrow_left_rounded, color: Colors.grey.shade600, size: 20),
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(begin: const Offset(0.0, 0.5), end: Offset.zero).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            _arrivalTimes[_timeIndex],
                            key: ValueKey<int>(_timeIndex),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _cycleTime(1),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(Icons.arrow_right_rounded, color: Colors.grey.shade600, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ... (Keep _buildCleanInterchangeInfo, _buildDirectBusInfo, _buildCollapsibleStepGuide same as before)
  // Just ensure they use const constructors where possible.
  
  Widget _buildCleanInterchangeInfo() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            _buildBusBadge("729", Colors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Towards ITO", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  Text("Arriving in 4 min", style: TextStyle(color: Colors.greenAccent.withValues(alpha: 0.8), fontSize: 11)),
                ],
              ),
            ),
            _buildLiveTrackButton(),
          ],
        ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.only(left: 22),
          child: Row(
            children: [
              Container(width: 2, height: 16, color: Colors.white.withValues(alpha: 0.1)),
              const SizedBox(width: 20),
              const Icon(Icons.swap_calls_rounded, color: Colors.grey, size: 14),
              const SizedBox(width: 6),
              const Text("Change at Mandi House", style: TextStyle(color: Colors.grey, fontSize: 10, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        Row(
          children: [
            _buildBusBadge("534", Colors.blue),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Towards Noida", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  Text("Freq: Every 10 min", style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            const Text("22 min ride", style: TextStyle(color: Colors.grey, fontSize: 10)),
          ],
        ),
      ],
    );
  }

  Widget _buildDirectBusInfo() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Bus Number", style: TextStyle(color: Colors.grey, fontSize: 11)),
                const SizedBox(height: 2),
                const Text("419", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                  child: const Text("Seats Available", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                )
              ],
            ),
            _buildLiveTrackButton(),
          ],
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Next Bus", style: TextStyle(color: Colors.grey, fontSize: 11)),
                SizedBox(height: 2),
                Text("12 min", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("Duration", style: TextStyle(color: Colors.grey, fontSize: 11)),
                SizedBox(height: 2),
                Text("48 min", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        )
      ],
    );
  }

  Widget _buildCollapsibleStepGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
             AppHaptics.lightImpact();
             setState(() => _isStepsExpanded = !_isStepsExpanded);
          },
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15), 
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                  const Row(
                    children: [
                      Icon(Icons.directions_walk_rounded, color: Colors.white70, size: 18),
                      SizedBox(width: 10),
                      Text("View Walking Instructions", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                AnimatedRotation(
                  turns: _isStepsExpanded ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: const Icon(Icons.expand_more_rounded, color: Colors.grey, size: 22),
                ),
              ],
            ),
          ),
        ),

        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity), 
          secondChild: Container(
            margin: const EdgeInsets.only(top: 5),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                _buildStepItem("1", "Walk 200m", "to Laxmi Nagar Stand", isFirst: true, icon: Icons.directions_walk),
                _buildStepItem("2", "Board Bus 729", "Wait at Stand A. Low crowd expected.", icon: Icons.directions_bus),
                _buildStepItem("3", "De-board at Mandi House", "Walk 50m to opposite stand.", icon: Icons.transfer_within_a_station),
                _buildStepItem("4", "Board Bus 534", "Ride 8 stops to Noida.", icon: Icons.directions_bus),
                _buildStepItem("5", "Arrive Destination", "Noida Sec 18", isLast: true, icon: Icons.flag),
              ],
            ),
          ),
          crossFadeState: _isStepsExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
      ],
    );
  }

  // ... (Keep helper widgets: _buildCompactSummaryCard, _buildStationInfo, _buildPriceTag, _buildMiniStat, _buildStepItem, _buildLiveTrackButton, _buildBusBadge same)
  // Ensure they are copied over from previous code or let me know if you need full code again.
  // I will include them below for completeness.

  Widget _buildCompactSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16), 
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          IntrinsicHeight( 
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildStationInfo("From", fromStation, CrossAxisAlignment.start)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(Icons.arrow_forward_rounded, color: Colors.blue, size: 16),
                      ),
                      Expanded(child: _buildStationInfo("To", toStation, CrossAxisAlignment.end)),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 15),
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildPriceTag("₹15", "Non-AC", Colors.white),
                    const SizedBox(height: 6),
                    _buildPriceTag("₹25", "AC Bus", Colors.cyanAccent),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniStat(Icons.schedule_rounded, "48 min", Colors.orange),
              _buildMiniStat(Icons.directions_bus_outlined, "18 Stops", Colors.blue),
              _buildMiniStat(Icons.straighten_rounded, "12 km", Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(String step, String title, String desc, {bool isFirst = false, bool isLast = false, required IconData icon}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 24, height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isFirst ? Colors.green : (isLast ? Colors.red : Colors.blueGrey.shade800),
                  shape: BoxShape.circle,
                ),
                child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              if (!isLast) Expanded(child: Container(width: 1, color: Colors.white.withValues(alpha: 0.1))),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(desc, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStationInfo(String label, String name, CrossAxisAlignment alignment) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        const SizedBox(height: 2),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPriceTag(String price, String type, Color color) {
    return Row(
      children: [
        Text(type, style: TextStyle(color: Colors.grey.shade600, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        Text(price, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMiniStat(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildLiveTrackButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.my_location_rounded, color: Colors.green, size: 12),
          SizedBox(width: 4),
          Text("LIVE", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBusBadge(String number, Color color) {
    return Container(
      width: 45, height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(number, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w900)),
    );
  }
}