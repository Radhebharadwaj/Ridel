part of 'map_search_sheet.dart';

extension _PremiumDetailsExt on _MapSearchSheetState {
  // ignore: unused_element
  Widget _buildPremiumGlassSheet(
      BuildContext context, MapProvider provider, bool isDark) {
    const currentSideMargin = 16.0;
    const currentBottomMargin = 24.0;
    const sheetRadius = 32.0; // Slightly smaller radius for shrink-wrapped look

    final Color sheetBgColor = isDark
        ? const Color(0xFF0B0E17).withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.85);
    const double blurAmount = 35.0;

    return PointerInterceptor(
      child: Align(
        alignment: Alignment.bottomCenter,
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
    final distanceString = provider.currentRouteDistance ?? "";

    final placeTitle = _selectedPlace?.name ?? "Destination";
    final placeSubtitle = _selectedPlace?.address ?? "";

    return Padding(
      // Normal padding, NO massive bottom padding that creates empty space
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        mainAxisSize: MainAxisSize
            .min, // 🚨 CRITICAL: Forces the sheet to hug the content tightly at the bottom
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 2. Title & Buttons Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  placeTitle,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.2),
                ),
              ),
              IconButton(
                icon:
                    const Icon(Icons.ios_share, color: Colors.white, size: 22),
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
                icon: const Icon(Icons.close, color: Colors.white, size: 24),
                onPressed: () {
                  AppHaptics.lightImpact();
                  final provider =
                      Provider.of<MapProvider>(context, listen: false);
                  _handleCancelRoute(context, provider);
                },
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 3. Subtitle & Copy Button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  placeSubtitle,
                  style: const TextStyle(
                      fontSize: 14, color: Colors.white70, height: 1.4),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: "$placeTitle, $placeSubtitle"));
                  AppHaptics.selectionClick();
                  _showPremiumNotification("Address Copied!");
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.copy_rounded,
                      color: Colors.white70, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 4. Distance Badge (If route exists)
          if (distanceString.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0A84FF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF0A84FF).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.route_rounded,
                      color: Color(0xFF0A84FF), size: 16),
                  const SizedBox(width: 6),
                  Text(distanceString,
                      style: const TextStyle(
                          color: Color(0xFF0A84FF),
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // 5. Transport Modes (Glassy Buttons)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildGlassyTransportMode(context,
                  icon: Icons.directions_walk_rounded,
                  label: 'Walk',
                  isActive: provider.currentNavMode == 'walking' && provider.currentRouteResult != null, 
                  onTap: () {
                AppHaptics.selectionClick();
                provider.currentNavMode = 'walking';
                provider.calculateAndDrawNativeRoute(context, provider.currentNavMode);
              }),
              _buildGlassyTransportMode(context,
                  icon: Icons.two_wheeler_rounded,
                  label: 'Bike',
                  isActive: (provider.currentNavMode == 'bicycling' || provider.currentNavMode == 'twowheeler') && provider.currentRouteResult != null, 
                  onTap: () {
                AppHaptics.selectionClick();
                provider.currentNavMode = 'twowheeler';
                provider.calculateAndDrawNativeRoute(context, provider.currentNavMode);
              }),
              _buildGlassyTransportMode(context,
                  icon: CupertinoIcons.car_detailed,
                  label: 'Car',
                  isActive: provider.currentNavMode == 'driving' && provider.currentRouteResult != null, 
                  onTap: () {
                AppHaptics.selectionClick();
                provider.currentNavMode = 'driving';
                provider.calculateAndDrawNativeRoute(context, provider.currentNavMode);
              }),
              _buildGlassyTransportMode(context,
                  icon: Icons.local_shipping_rounded,
                  label: 'Heavy',
                  isActive: provider.currentNavMode == 'heavy' && provider.currentRouteResult != null, 
                  onTap: () {
                AppHaptics.selectionClick();
                provider.currentNavMode = 'heavy';
                provider.calculateAndDrawNativeRoute(context, provider.currentNavMode);
              }),
            ],
          ),

          // Safe bottom padding for modern phones
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
