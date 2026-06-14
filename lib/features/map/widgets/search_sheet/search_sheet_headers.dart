part of 'map_search_sheet.dart';

// 🚀 FIX: Named the extension to fix method visibility bugs in the Dart analyzer
extension _SearchSheetHeadersExt on _MapSearchSheetState {
  Widget _buildPremiumCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
    Color? bgColor,
    double size = 44.0,
    double iconSize = 20.0,
  }) {
    return RidelBounceButton(
      onTap: () {
        AppHaptics.lightImpact();
        onTap();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.20),
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.06),
            ],
          ),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              spreadRadius: -2,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );
  }

  Widget _buildNavigationDashboardOverlay(bool isDark) {
    final provider = Provider.of<MapProvider>(context, listen: false);
    final routeResult = provider.currentRouteResult;

    final distanceKm = routeResult?.distanceKm.toStringAsFixed(1) ?? '—';
    final durationMins = routeResult?.durationMins.toString() ?? '—';

    final Color primaryText = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final Color secondaryText = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.42);
    final Color dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    final Color sheetBgColor = isDark
        ? const Color(0xFF0B0E17).withValues(alpha: 0.80)
        : Colors.white.withValues(alpha: 0.65);

    return PointerInterceptor(
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30.0, sigmaY: 30.0),
                  child: Container(
                    width: MediaQuery.sizeOf(context).width - 32,
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: sheetBgColor,
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1.0,
                      ),
                      boxShadow: [
                        if (!isDark)
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
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.bottomCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MouseRegion(
                            onEnter: (_) => _pokeDash(),
                            onHover: (_) => _pokeDash(),
                            child: Listener(
                              onPointerDown: (_) => _pokeDash(),
                              onPointerMove: (_) => _pokeDash(),
                              behavior: HitTestBehavior.opaque,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  _pokeDash();
                                  rebuildState(() {
                                    _isNavSheetExpanded = !_isNavSheetExpanded;
                                  });
                                },
                                onVerticalDragDown: (_) => _pokeDash(),
                                onVerticalDragEnd: (details) {
                                  if ((details.primaryVelocity ?? 0) < -100 &&
                                      !_isNavSheetExpanded) {
                                    rebuildState(
                                        () => _isNavSheetExpanded = true);
                                  } else if ((details.primaryVelocity ?? 0) >
                                          100 &&
                                      _isNavSheetExpanded) {
                                    rebuildState(
                                        () => _isNavSheetExpanded = false);
                                  }
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Single Drag Handle
                                    AnimatedOpacity(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      opacity: _isDashVisible ? 1.0 : 0.0,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                            top: 12, bottom: 6),
                                        child: Container(
                                          width: 40,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? Colors.white
                                                    .withValues(alpha: 0.15)
                                                : Colors.black
                                                    .withValues(alpha: 0.10),
                                            borderRadius:
                                                BorderRadius.circular(100),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Collapsed Stats Capsule
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 8),
                                      child: ValueListenableBuilder<double>(
                                        valueListenable: provider.engine
                                            .navigation.remainingDuration,
                                        builder: (context, duration, child) {
                                          final arrivalTime = DateTime.now()
                                              .add(Duration(
                                                  seconds: duration.toInt()));
                                          final formattedArrival =
                                              "${arrivalTime.hour}:${arrivalTime.minute.toString().padLeft(2, '0')}";
                                          final mins = (duration / 60).floor();
                                          return ValueListenableBuilder<double>(
                                            valueListenable: provider.engine
                                                .navigation.remainingDistance,
                                            builder:
                                                (context, distance, child) {
                                              final distParts =
                                                  RouteUtils.formatDistance(
                                                          distance)
                                                      .split(' ');
                                              return Row(
                                                children: [
                                                  // Arrival
                                                  Expanded(
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          formattedArrival,
                                                          style: TextStyle(
                                                            color: primaryText,
                                                            fontSize: 26,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            letterSpacing: -1.0,
                                                            height: 1.0,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 2),
                                                        Text(
                                                          'arrival',
                                                          style: TextStyle(
                                                            color:
                                                                secondaryText,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            letterSpacing: 0.2,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  // Minutes
                                                  Expanded(
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          mins.toString(),
                                                          style: TextStyle(
                                                            color: primaryText,
                                                            fontSize: 26,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            letterSpacing: -1.0,
                                                            height: 1.0,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 2),
                                                        Text(
                                                          'min',
                                                          style: TextStyle(
                                                            color:
                                                                secondaryText,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            letterSpacing: 0.2,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  // Distance
                                                  Expanded(
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          distParts[0],
                                                          style: TextStyle(
                                                            color: primaryText,
                                                            fontSize: 26,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            letterSpacing: -1.0,
                                                            height: 1.0,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 2),
                                                        Text(
                                                          distParts.length > 1
                                                              ? distParts[1]
                                                              : '',
                                                          style: TextStyle(
                                                            color:
                                                                secondaryText,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            letterSpacing: 0.2,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                    if (!_isNavSheetExpanded)
                                      const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Expanded Content
                          if (_isNavSheetExpanded)
                            Flexible(
                              child: SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Divider
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24),
                                      child: Container(
                                          height: 0.5, color: dividerColor),
                                    ),
                                    // Section A: Quick Pit Stops
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          20, 16, 20, 8),
                                      child: Row(
                                        children: [
                                          _buildPitStopPill(
                                              '⛽', 'Petrol', isDark),
                                          const SizedBox(width: 10),
                                          _buildPitStopPill(
                                              '🍃', 'CNG', isDark),
                                          const SizedBox(width: 10),
                                          _buildPitStopPill(
                                              '⚡', 'EV Charge', isDark),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Divider
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24),
                                      child: Container(
                                          height: 0.5, color: dividerColor),
                                    ),
                                    // Section B: Action List
                                    _buildNavAction(
                                      icon: CupertinoIcons.add_circled,
                                      label: 'Add Stop',
                                      color: const Color(0xFF0A84FF),
                                      isDark: isDark,
                                      onTap: () {
                                        AppHaptics.lightImpact();
                                      },
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24),
                                      child: Container(
                                          height: 0.5, color: dividerColor),
                                    ),
                                    _buildNavAction(
                                      icon: CupertinoIcons.location_fill,
                                      label: 'Share ETA',
                                      color: const Color(0xFF30D158),
                                      isDark: isDark,
                                      onTap: () async {
                                        AppHaptics.lightImpact();
                                        final shareText =
                                            'I\'ll arrive in ~$durationMins min ($distanceKm km away)';
                                        await Clipboard.setData(
                                            ClipboardData(text: shareText));
                                        if (context.mounted) {
                                          _showPremiumNotification(
                                              'ETA copied to clipboard!');
                                        }
                                      },
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24),
                                      child: Container(
                                          height: 0.5, color: dividerColor),
                                    ),
                                    _buildNavAction(
                                      icon: CupertinoIcons
                                          .exclamationmark_triangle_fill,
                                      label: 'Report an Incident',
                                      color: const Color(0xFFFF9F0A),
                                      isDark: isDark,
                                      onTap: () {
                                        AppHaptics.lightImpact();
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              ),
                            ),
                          // Section C: End Route Button
                          if (_isNavSheetExpanded)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                              child: RidelBounceButton(
                                scaleFactor: 0.95,
                                onTap: () async {
                                  debugPrint('End Route: Start');
                                  AppHaptics.heavyImpact();
                                  rebuildState(
                                      () => _isNavSheetExpanded = false);
                                  final p = Provider.of<MapProvider>(context,
                                      listen: false);
                                      
                                  debugPrint('End Route: Calling cancelAndClearRoute');
                                  try {
                                    await p.cancelAndClearRoute();
                                    debugPrint('End Route: cancelAndClearRoute success');
                                  } catch (e) {
                                    debugPrint('End Route Cleanup Failed: $e');
                                  } finally {
                                    debugPrint('End Route: Ensuring UI Dismissal');
                                    p.isActiveNavigation = false;
                                    p.clearError(); // Safely triggers notifyListeners()
                                    debugPrint('End Route: Finished');
                                  }
                                },
                                child: RidelLiquidButton(
                                  width: double.infinity,
                                  height: 56,
                                  enableStretch: true,
                                  glassTint: const Color(0xFFFF3B30)
                                      .withValues(alpha: 0.18),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'End Route',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: Colors.white,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.stop_circle_outlined,
                                        size: 20,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          // Removed extra bracket because of the ...[ block being converted to single Expanded widget
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
    );
  }

  Widget _buildPitStopPill(String emoji, String label, bool isDark) {
    return Expanded(
      child: RidelBounceButton(
        onTap: () => AppHaptics.lightImpact(),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavAction({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return RidelBounceButton(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(icon, color: color, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            Icon(
              CupertinoIcons.chevron_right,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.20),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionsHeader(double headerHeight, bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black;
    // 🚀 PREMIUM MATTE PILL BASE FOR INPUTS
    final mattePillBase = isDark ? const Color(0xFF1E2129) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    return SizedBox(
      key: const ValueKey('directions_header'),
      height: headerHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RidelBounceButton(
                  onTap: _closeDirectionsView,
                  child: Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      color: mattePillBase,
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor),
                      boxShadow: AppShadows.buttonSoft,
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: textColor,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: mattePillBase,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderColor),
                      boxShadow: AppShadows.buttonSoft,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildModeIcon(
                          CupertinoIcons.car_detailed,
                          'driving',
                          isDark,
                        ),
                        _buildModeIcon(
                          Icons.directions_walk_rounded,
                          'walking',
                          isDark,
                        ),
                        _buildModeIcon(
                          Icons.directions_transit_rounded,
                          'transit',
                          isDark,
                        ),
                        _buildModeIcon(
                          Icons.pedal_bike_rounded,
                          'cycling',
                          isDark,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: mattePillBase,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
                boxShadow: AppShadows.buttonSoft,
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            border: Border.all(
                              // 🚀 FIX: Qualified static reference
                              color: _activeRoutingField == 'origin'
                                  ? _MapSearchSheetState.neonCyan
                                  : (_originPlace != null
                                      ? Colors.white54
                                      : _MapSearchSheetState.neonCyan),
                              width: 3,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Container(
                            width: 2,
                            color: isDark ? Colors.white24 : Colors.black12,
                          ),
                        ),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            // 🚀 FIX: Qualified static reference
                            color: _activeRoutingField == 'dest'
                                ? _MapSearchSheetState.neonCyan
                                : Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextField(
                              controller: _originCtrl,
                              focusNode: _originFocus,
                              readOnly: true,
                              onTap: () {
                                AppHaptics.lightImpact();
                                // 🚀 FIX: Using the created rebuild() method to bypass setState protection
                                rebuildState(
                                    () => _activeRoutingField = 'origin');

                                // 🚀 FIX: Removed Ugly White Notification & added Custom Service
                                _showPremiumNotification(
                                  'Tap on the map to set starting point',
                                );

                                if (_sheetController.isAttached) {
                                  unawaited(
                                    _sheetController.animateTo(
                                      _safeMinSize,
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeOutCubic,
                                    ),
                                  );
                                }
                              },
                              style: TextStyle(
                                // 🚀 FIX: Qualified static reference
                                color: _activeRoutingField == 'origin'
                                    ? _MapSearchSheetState.neonCyan
                                    : textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Choose starting point',
                                hintStyle: TextStyle(
                                  color:
                                      isDark ? Colors.white30 : Colors.black38,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (_originPlace != null ||
                                        _originCtrl.text != 'Your Location')
                                      IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.grey,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          AppHaptics.lightImpact();
                                          rebuildState(() {
                                            _originPlace = null;
                                            _originCtrl.text = '';
                                            _activeRoutingField = 'origin';
                                          });
                                        },
                                      ),
                                    if (_originPlace != null)
                                      IconButton(
                                        // 🚀 FIX: Qualified static reference
                                        icon: const Icon(
                                          Icons.my_location,
                                          color: _MapSearchSheetState.neonCyan,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          AppHaptics.lightImpact();
                                          rebuildState(() {
                                            _originPlace = null;
                                            _originCtrl.text = 'Your Location';
                                            _activeRoutingField = null;
                                          });
                                          unawaited(_checkAndFetchRoute());
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Container(height: 1, color: borderColor),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextField(
                              controller: _destCtrl,
                              focusNode: _destFocus,
                              readOnly: true,
                              onTap: () {
                                AppHaptics.lightImpact();
                                rebuildState(
                                    () => _activeRoutingField = 'dest');

                                // 🚀 FIX: Removed Ugly White Notification
                                _showPremiumNotification(
                                  'Tap on the map to set destination',
                                );

                                if (_sheetController.isAttached) {
                                  unawaited(
                                    _sheetController.animateTo(
                                      _safeMinSize,
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeOutCubic,
                                    ),
                                  );
                                }
                              },
                              style: TextStyle(
                                // 🚀 FIX: Qualified static reference
                                color: _activeRoutingField == 'dest'
                                    ? _MapSearchSheetState.neonCyan
                                    : textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Choose destination',
                                hintStyle: TextStyle(
                                  color:
                                      isDark ? Colors.white30 : Colors.black38,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                suffixIcon: _destCtrl.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.grey,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          AppHaptics.lightImpact();
                                          rebuildState(() {
                                            _destPlace = null;
                                            _destCtrl.text = '';
                                            _activeRoutingField = 'dest';
                                            _currentRoute = null;
                                          });
                                        },
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  RidelBounceButton(
                    onTap: () {
                      AppHaptics.lightImpact();
                      rebuildState(() {
                        final tempText = _originCtrl.text;
                        _originCtrl.text = _destCtrl.text;
                        _destCtrl.text = tempText;
                        final tempPlace = _originPlace;
                        _originPlace = _destPlace;
                        _destPlace = tempPlace;
                      });
                      unawaited(_checkAndFetchRoute());
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF121419)
                              : Colors.black.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.arrow_up_arrow_down,
                          color: _MapSearchSheetState.neonCyan,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_currentRoute != null)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: CupertinoButton(
                  color: _MapSearchSheetState.neonCyan,
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
                      color: Colors.black, // High contrast text
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedPlaceHeader(
      double headerHeight, double progress, bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final btnIconColor = isDark ? Colors.white : Colors.black;
    final mattePillBase = isDark ? const Color(0xFF1E2129) : Colors.white;

    String subtitleText = 'Place • ${_selectedPlace!.address}';
    if (_selectedPlace!.name == 'Dropped Pin' ||
        _selectedPlace!.address.isEmpty ||
        _selectedPlace!.address.contains('Lat:')) {
      subtitleText =
          'Lat: ${_selectedPlace!.latitude.toStringAsFixed(4)}, Lng: ${_selectedPlace!.longitude.toStringAsFixed(4)}';
    }

    return SizedBox(
      key: const ValueKey('place_header'),
      height: headerHeight,
      child: Center(
        child: Padding(
          padding: EdgeInsets.only(
            left: 12 + (8 * progress),
            right: 12 + (8 * progress),
            top: 5 * progress,
          ),
          child: Row(
            children: [
              _buildPremiumCircleButton(
                icon: CupertinoIcons.share,
                iconColor: btnIconColor,
                bgColor: mattePillBase,
                onTap: () async {
                  final shareLink =
                      'https://maps.apple/p/~${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

                  await Clipboard.setData(ClipboardData(text: shareLink));

                  // 🚀 FIX: Removed Ugly White Snackbar
                  _showPremiumNotification(
                    'Link copied successfully!',
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Colors.black,
                        Colors.black,
                        Colors.transparent
                      ],
                      stops: [0.0, 0.08, 0.92, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          _selectedPlace!.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitleText,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            color: subTextColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildPremiumCircleButton(
                icon: Icons.close_rounded,
                iconColor: btnIconColor,
                bgColor: mattePillBase,
                onTap: () {
                  final provider =
                      Provider.of<MapProvider>(context, listen: false);
                  _handleCancelRoute(context, provider);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchHeader(double headerHeight, double progress, bool isDark) {
    final isDesktop = MediaQuery.of(context).size.width > 600;
    // 🚀 PREMIUM GLASS SEARCH PILL
    final pillBaseColor = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : Colors.white.withValues(alpha: 0.9);
    final borderColor = Colors.white.withValues(alpha: 0.05);

    // Original closed state was 8.0, new open is 24.0
    final horizontalPadding = lerpDouble(8.0, 24.0, progress) ?? 8.0;
    // Original closed state was 46.0, new open is 54.0
    final dynamicHeight = lerpDouble(46.0, 54.0, progress) ?? 46.0;
    // Original closed state was 100.0, new open is 20.0
    final dynamicRadius = lerpDouble(100.0, 20.0, progress) ?? 100.0;

    // Original closed top padding was statically 6.0, new open pushes down to 18.0
    final topPadding = lerpDouble(6.0, 18.0, progress) ?? 6.0;
    // Bottom padding was always 10.0 in the original code
    const bottomPadding = 10.0;

    return SizedBox(
      key: const ValueKey('search_header'),
      height: headerHeight,
      child: Padding(
        // Use the new dynamic top padding here
        padding: EdgeInsets.only(
            top: topPadding,
            bottom: bottomPadding,
            left: horizontalPadding,
            right: horizontalPadding),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(dynamicRadius),
          // 🚀 FIX: Wrapped BackdropFilter in RepaintBoundary to prevent extreme frame drops during animations
          child: RepaintBoundary(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
              child: Container(
                height: dynamicHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(dynamicRadius),
                  color: pillBaseColor,
                  border: Border.all(color: borderColor, width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.search,
                      color: isDark ? Colors.white54 : Colors.black54,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        textAlignVertical: TextAlignVertical.center,
                        onTap: () {
                          if (_sheetController.isAttached) {
                            _sheetController.animateTo(
                              _safeMaxSize,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                            );
                          }
                          Future.delayed(const Duration(milliseconds: 350), () {
                            if (mounted && !_searchFocus.hasFocus) {
                              FocusScope.of(context).requestFocus(_searchFocus);
                            }
                          });
                        },
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Ridel Maps',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.only(bottom: 2),
                        ),
                        onSubmitted: (value) async {
                          FocusScope.of(context).unfocus();
                          final query = value.trim();
                          if (query.isEmpty) return;

                          List<PlaceModel> suggestions =
                              List.from(_searchResults);

                          if (suggestions.isEmpty) {
                            final globalLoc =
                                Provider.of<GlobalLocationService>(context,
                                    listen: false);
                            final pos = globalLoc.currentPosition;
                            final latLng = pos != null
                                ? LatLng(pos.latitude, pos.longitude)
                                : null;
                            suggestions = await MasterSearchService()
                                .searchPlaces(query, userLocation: latLng);
                          }

                          if (!mounted) return;

                          if (suggestions.isNotEmpty) {
                            final topSuggestion = suggestions.first;
                            AppHaptics.selectionClick();
                            await _selectPlaceFromList(topSuggestion);
                          } else {
                            ToastService.showInfo(
                                context, "No places found for '$query'");
                          }
                        },
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: _searchCtrl,
                      builder: (context, value, child) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (value.text.isNotEmpty)
                              RidelBounceButton(
                                onTap: () {
                                  AppHaptics.lightImpact();
                                  _searchCtrl.clear();
                                  rebuildState(() {});
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white30
                                        : Colors.black26,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.close,
                                    size: 12,
                                    color:
                                        isDark ? Colors.black87 : Colors.white,
                                  ),
                                ),
                              ),
                            if (value.text.isEmpty)
                              UniversalMicButton(
                                isDark: isDark,
                                onTextRecognized: (text) =>
                                    _searchCtrl.text = text,
                              ),
                          ],
                        );
                      },
                    ),
                    if (!isDesktop) ...[
                      const SizedBox(width: 12),
                      ValueListenableBuilder(
                        valueListenable: _searchCtrl,
                        builder: (context, value, child) {
                          final isTyping = value.text.isNotEmpty;
                          return RidelBounceButton(
                            onTap: () {
                              if (isTyping) {
                                _handleSearchExecution(value.text);
                              } else {
                                _handleCancelTap();
                              }
                            },
                            child: Container(
                              alignment: Alignment.center,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                isTyping ? 'Done' : 'Cancel',
                                style: TextStyle(
                                  // 🚀 FIX: Qualified static reference
                                  color: isDark
                                      ? _MapSearchSheetState.neonCyan
                                      : const Color(0xFF00B8D4),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeIcon(IconData icon, String mode, bool isDark) {
    final isActive = _selectedNavMode == mode;
    return RidelBounceButton(
      onTap: () {
        AppHaptics.selectionClick();
        // 🚀 FIX: Syncing Provider with local UI State to fix Mode Overlap/Routing bug
        Provider.of<MapProvider>(context, listen: false)
            .setNavMode(context, mode);
        rebuildState(() => _selectedNavMode = mode);
        unawaited(_checkAndFetchRoute());
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive
              ? _MapSearchSheetState.neonCyan.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: isActive
              ? _MapSearchSheetState.neonCyan
              : (isDark ? Colors.white38 : Colors.black38),
          size: 22,
        ),
      ),
    );
  }
}
