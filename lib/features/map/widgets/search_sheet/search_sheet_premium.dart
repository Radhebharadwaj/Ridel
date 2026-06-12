part of 'map_search_sheet.dart';

extension _PremiumDetailsExt on _MapSearchSheetState {
  // ignore: unused_element
  Widget _buildPremiumGlassSheet(
      BuildContext context, MapProvider provider, bool isDark) {
    const currentSideMargin = 16.0;
    const currentBottomMargin = 24.0;
    const sheetRadius = 32.0;

    final Color sheetBgColor = isDark
        ? const Color(0xFF0B0E17).withValues(alpha: 0.80)
        : Colors.white.withValues(alpha: 0.65);
    const double blurAmount = 30.0;

    return Align(
      alignment: Alignment.bottomCenter,
      child: PointerInterceptor(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width > 600 ? 800 : 450,
          ),
          child: RepaintBoundary(
            child: Container(
              margin: EdgeInsets.only(
                left: currentSideMargin,
                right: currentSideMargin,
                bottom:
                    currentBottomMargin + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(sheetRadius),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 15,
                      offset: const Offset(0, 5)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(sheetRadius),
                child: BackdropFilter(
                  filter:
                      ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
                  child: Container(
                    decoration: BoxDecoration(
                      color: sheetBgColor,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1.0,
                      ),
                    ),
                    child: _buildPremiumDetails(context, provider),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumDetails(BuildContext context, MapProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeTitle = _selectedPlace?.name ?? "Destination";
    final placeSubtitle = _selectedPlace?.address ?? "";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 2. TITLE, SUBTITLE & TOP BUTTONS
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      placeTitle,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                          height: 1.2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      placeSubtitle,
                      style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.black54,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(CupertinoIcons.share,
                    color: isDark ? Colors.white : Colors.black87, size: 22),
                onPressed: () {
                  AppHaptics.lightImpact();
                  final shareLink =
                      'https://maps.apple/p/~${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
                  Clipboard.setData(ClipboardData(text: shareLink));
                  _showPremiumNotification('Link copied successfully!');
                },
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded,
                    color: isDark ? Colors.white : Colors.black87, size: 24),
                onPressed: () {
                  AppHaptics.lightImpact();
                  final safeProvider =
                      Provider.of<MapProvider>(context, listen: false);
                  _handleCancelRoute(context, safeProvider);
                },
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 3. TRANSPORT MODES
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildGlassyTransportMode(context,
                  icon: Icons.directions_walk_rounded,
                  label: 'Walk',
                  isActive: provider.currentRouteResult != null && provider.currentNavMode == 'walking', onTap: () async {
                if (provider.currentNavMode == 'walking') return;
                AppHaptics.selectionClick();
                provider.currentNavMode = 'walking';
                rebuildState(() {});
                await provider.calculateAndDrawNativeRoute(
                    context, provider.currentNavMode);
                rebuildState(() {});
              }),
              _buildGlassyTransportMode(context,
                  icon: Icons.two_wheeler_rounded,
                  label: 'Bike',
                  isActive: provider.currentRouteResult != null && (provider.currentNavMode == 'bicycling' ||
                      provider.currentNavMode == 'twowheeler'), onTap: () async {
                if (provider.currentNavMode == 'twowheeler') return;
                AppHaptics.selectionClick();
                provider.currentNavMode = 'twowheeler';
                rebuildState(() {});
                await provider.calculateAndDrawNativeRoute(
                    context, provider.currentNavMode);
                rebuildState(() {});
              }),
              _buildGlassyTransportMode(context,
                  icon: CupertinoIcons.car_detailed,
                  label: 'Car',
                  isActive: provider.currentRouteResult != null && provider.currentNavMode == 'driving', onTap: () async {
                if (provider.currentNavMode == 'driving') return;
                AppHaptics.selectionClick();
                provider.currentNavMode = 'driving';
                rebuildState(() {});
                await provider.calculateAndDrawNativeRoute(
                    context, provider.currentNavMode);
                rebuildState(() {});
              }),
              _buildGlassyTransportMode(context,
                  icon: Icons.local_shipping_rounded,
                  label: 'Heavy',
                  isActive: provider.currentRouteResult != null && provider.currentNavMode == 'heavy', onTap: () async {
                if (provider.currentNavMode == 'heavy') return;
                AppHaptics.selectionClick();
                provider.currentNavMode = 'heavy';
                rebuildState(() {});
                await provider.calculateAndDrawNativeRoute(
                    context, provider.currentNavMode);
                rebuildState(() {});
              }),
            ],
          ),

          const SizedBox(height: 24),

          // 🚨 4. ORIGIN & DESTINATION CARD (The missing piece!)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1F26) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Builder(builder: (context) {
              final locService = Provider.of<GlobalLocationService>(context);
              final String originAddress =
                  locService.currentAddressName ?? "Locating...";
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🟢 CURRENT LOCATION (ORIGIN)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(CupertinoIcons.location_solid,
                          color: Color(0xFF0A84FF), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Current Location",
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                            Text(
                              originAddress,
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          if (originAddress.isNotEmpty &&
                              originAddress != "Locating...") {
                            Clipboard.setData(
                                ClipboardData(text: originAddress));
                            AppHaptics.selectionClick();
                            ToastService.showSuccess(
                                context, "Location Copied!");
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: isDark ? Colors.white12 : Colors.black12,
                              borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.copy_rounded,
                              color: isDark ? Colors.white70 : Colors.black54,
                              size: 16),
                        ),
                      ),
                    ],
                  ),

                  Padding(
                    padding:
                        const EdgeInsets.only(left: 9.0, top: 4, bottom: 4),
                    child: SizedBox(
                        height: 14,
                        child: VerticalDivider(
                            color: isDark ? Colors.white24 : Colors.black26,
                            thickness: 1.5)),
                  ),

                  // 🔴 DESTINATION
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.redAccent, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Destination",
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                            Text(
                              placeSubtitle.isNotEmpty
                                  ? placeSubtitle
                                  : placeTitle,
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(
                              text: "$placeTitle, $placeSubtitle"));
                          AppHaptics.selectionClick();
                          ToastService.showSuccess(context, "Address Copied!");
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: isDark ? Colors.white12 : Colors.black12,
                              borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.copy_rounded,
                              color: isDark ? Colors.white70 : Colors.black54,
                              size: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }),
          ),

          // 5. ETA & DISTANCE BADGE (Shows when Route is calculated)
          if (provider.currentRouteResult != null) ...[
            const SizedBox(height: 16),
            Builder(builder: (context) {
              int totalMinutes = provider.currentRouteResult!.durationMins;
              int hours = totalMinutes ~/ 60;
              int minutes = totalMinutes % 60;
              String formattedDuration =
                  hours > 0 ? "$hours hr $minutes min" : "$minutes min";
              DateTime arrivalTime =
                  DateTime.now().add(Duration(minutes: totalMinutes));
              String formattedArrival =
                  TimeOfDay.fromDateTime(arrivalTime).format(context);

              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0A84FF).withValues(alpha: 0.15)
                      : const Color(0xFF0A84FF).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF0A84FF).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time_filled_rounded,
                            color: Color(0xFF0A84FF), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          "$formattedDuration • ${provider.currentRouteResult!.distanceKm.toStringAsFixed(1)} km",
                          style: const TextStyle(
                              color: Color(0xFF0A84FF),
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Arrives at $formattedArrival",
                      style: TextStyle(
                          color: isDark
                              ? const Color(0xFF0A84FF).withValues(alpha: 0.8)
                              : const Color(0xFF0A84FF).withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 24),

            // 6. START NAVIGATION BUTTON
            SizedBox(
              width: double.infinity,
              height: 52,
              child: CupertinoButton(
                color: const Color(0xFF0A84FF),
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(16),
                onPressed: () {
                  AppHaptics.heavyImpact();
                  Provider.of<MapProvider>(context, listen: false)
                      .startActiveNavigation(context);

                  if (_sheetController.isAttached) {
                    _sheetController.animateTo(
                      _safeMinSize,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
                child: const Text(
                  'Start Navigation',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }


}
