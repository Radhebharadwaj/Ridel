part of 'map_search_sheet.dart';

// 🚀 FIX: Named the extension to fix method visibility bugs in the Dart analyzer
extension _SearchSheetViewsExt on _MapSearchSheetState {
  Widget _buildProfileStyleCard(
    BuildContext context, {
    required bool isDark,
    required Color bgColor,
    required Widget child,
    double borderRadius = 24.0,
  }) {
    // 🚀 PREMIUM MATTE CARD FOR LISTS & MENUS (Refined Alpha for true Glassmorphism)
    return Material(
      color: isDark ? const Color(0xFF1C1F26) : Colors.white,
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.06),
          ),
          boxShadow: AppShadows.buttonSoft,
        ),
        child: child,
      ),
    );
  }

  Widget _buildCircularQuickAction({
    required IconData icon,
    required String label,
    required bool isDark,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    final Color glassBaseColor = isDark
        ? const Color(0xFF1E1E1E).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.75);

    return RidelBounceButton(
      onTap: () {
        AppHaptics.lightImpact();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: glassBaseColor,
            ),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black87,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnifiedExploreView(bool isDark, double progress) {
    final provider = Provider.of<MapProvider>(context);
    final iconColor = isDark ? Colors.white70 : Colors.black87;
    final isFocused = _searchFocus.hasFocus;
    final isEmpty = _searchCtrl.text.isEmpty;
    final isSelected = _selectedPlace != null;

    final showTransportModes = isSelected;
    final showQuickActions = !isSelected && (!isFocused && !provider.isEditingHistory) && isEmpty;
    final showRecentSearches = !isSelected && (isFocused || provider.isEditingHistory) && isEmpty;

    final isExpanded = progress > (_safeMinSize + 0.05);
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;

    Widget buildHiddenExtra(Widget child) {
      return AnimatedSize(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutExpo, // 🚀 FIX: Upgraded to Apple-like Expo Curve
        alignment: Alignment.topCenter,
        child: isExpanded
            ? AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: 1,
                child: child,
              )
            : const SizedBox(width: double.infinity, height: 0),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          if (showTransportModes || showQuickActions)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOutCubic, // 🚀 FIX: Premium snap without spring
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                          scale: Tween<double>(begin: 0.95, end: 1.0)
                              .animate(animation),
                          child: child));
                },
                child: showTransportModes
                    ? _buildTransportModesRow(context, provider, isDark)
                    : _buildDefaultQuickActionsRow(context, isDark),
              ),
            ),
          if (showQuickActions && isLoggedIn)
            Column(
              children: [
                QuickActionButtons(
                  isDark: isDark,
                  onRequestSearch: (actionType) {
                    _selectedActionType = actionType;
                    _searchFocus.requestFocus();
                  },
                  onNavigateReady: (destination) {
                    AppHaptics.heavyImpact();
                    _searchFocus.unfocus();
                    rebuildState(() {
                      _selectedPlace = destination;
                    });
                    _openDirectionsView();
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          if (showRecentSearches)
            buildHiddenExtra(
              Material(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Premium Header Row
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            Icon(CupertinoIcons.clock, color: iconColor, size: 24), // matched icon size
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Recent Searches',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.9)
                                      : Colors.black87,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (provider.recentSearches.isNotEmpty)
                              provider.isEditingHistory
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // 1. DELETE ALL BUTTON
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            FocusScope.of(context).requestFocus(_searchFocus); // PREVENT SHEET COLLAPSE
                                            provider.deleteAllHistory(); 
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                            child: Text("Delete All", style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w500)),
                                          ),
                                        ),
                                        // 2. DONE BUTTON
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            FocusScope.of(context).requestFocus(_searchFocus); // PREVENT SHEET COLLAPSE
                                            provider.deleteSelectedHistory(); 
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.only(left: 8.0, top: 8.0, bottom: 8.0),
                                            child: Text("Done", style: TextStyle(color: Colors.blueAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                      ],
                                    )
                                  : ExcludeFocus( // 🛡️ PREVENTS BUTTON FROM STEALING FOCUS
                                      child: Listener(
                                        behavior: HitTestBehavior.opaque,
                                        onPointerDown: (_) {
                                          AppHaptics.selectionClick();
                                          
                                          // 1. Capture current focus (the search bar)
                                          FocusNode? currentFocus = FocusManager.instance.primaryFocus;
                                          
                                          // 2. Change state to Edit Mode
                                          provider.setIsEditingHistory(true);
                                          
                                          // 3. Forcefully keep the focus alive so the sheet DOES NOT collapse!
                                          currentFocus?.requestFocus();
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                          child: Text(
                                            "Delete",
                                            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 16),
                                          ),
                                        ),
                                      ),
                                    ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black12),
                      provider.recentSearches.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32.0),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.travel_explore, color: isDark ? Colors.white24 : Colors.black26, size: 48),
                                    const SizedBox(height: 12),
                                    Text(
                                      "No recent searches",
                                      style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 15, fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Your search history will appear here.",
                                      style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320), // Height for approx 5 items
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          itemCount: provider.recentSearches.length,
                          itemBuilder: (context, index) {
                            final place = provider.recentSearches[index];
                            final isLast = index == provider.recentSearches.length - 1;
                            
                            // Fetch provider safely BEFORE the gesture callback using the stable build context
                            final safeProvider = Provider.of<MapProvider>(context, listen: false);

                            return Dismissible(
                              key: Key('recent_${index}_${place.name}'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: Colors.redAccent,
                                child: const Icon(
                                  CupertinoIcons.delete,
                                  color: Colors.white,
                                ),
                              ),
                              onDismissed: (_) {
                                AppHaptics.mediumImpact();
                                safeProvider.deleteSingleHistory(place);
                              },
                              child: Column(
                                children: [
                                  Listener(
                                    behavior: HitTestBehavior.opaque,
                                    // Trigger INSTANTLY on touch, before any keyboard unfocus events can destroy the widget
                                    onPointerDown: (event) async {
                                      // --- NEW INTERCEPTOR FOR EDIT MODE ---
                                      if (safeProvider.isEditingHistory) {
                                        safeProvider.toggleDeletionSelection(place.placeId);
                                        return; // STOP execution here, do not fly camera!
                                      }
                                      // --- END INTERCEPTOR ---
                                      
                                      debugPrint("💥 RAW POINTER DOWN REGISTERED ON: ${place.name}");
                                      AppHaptics.selectionClick();
                                      
                                      try {
                                        // 1. Lock State FIRST using the pre-fetched safe provider
                                        safeProvider.setDestinationSelected(true);
                                        safeProvider.engine.setUIState(MapUIState.placeSelected);
                                        
                                        // Safely animate sheet to Pill View size
                                        if (_sheetController.isAttached) {
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            if (_sheetController.isAttached) {
                                              _sheetController.animateTo(
                                                _safeMinSize,
                                                duration: const Duration(milliseconds: 300),
                                                curve: Curves.easeOutCubic,
                                              );
                                            }
                                          });
                                        }
                                        
                                        // 2. NOW unfocus the keyboard
                                        FocusManager.instance.primaryFocus?.unfocus();
                                        
                                        // 3. Process Coordinates
                                        double lat = place.latitude;
                                        double lng = place.longitude;
                                        
                                        if (lat == 0.0 || lng == 0.0) {
                                          if (place.placeId.isNotEmpty) {
                                            try {
                                              final exactCoords = await PlaceService.getPlaceDetails(place.placeId);
                                              if (exactCoords != null) {
                                                lat = exactCoords.latitude;
                                                lng = exactCoords.longitude;
                                              }
                                            } catch (_) {}
                                          }
                                        }
                                        
                                        // 4. Fly Camera
                                        if (lat != 0.0 && lng != 0.0) {
                                          safeProvider.setTargetDestination(LatLng(lat, lng));
                                          rebuildState(() => _selectedPlace = place);
                                          if (_sheetController.isAttached) {
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              if (_sheetController.isAttached) {
                                                _sheetController.animateTo(
                                                  _safeMinSize,
                                                  duration: const Duration(milliseconds: 300),
                                                  curve: Curves.easeOutCubic,
                                                );
                                              }
                                            });
                                          }
                                          // Drop the native Red Circle at the selected place coordinates
                                          if (lat != 0.0 && lng != 0.0) {
                                            safeProvider.addNativeDestinationPin(LatLng(lat, lng));
                                          }
                                          await safeProvider.flyToPlace(lat, lng);
                                        } else {
                                          safeProvider.engine.setUIState(MapUIState.idle);
                                        }
                                      } catch (e) {
                                        debugPrint("🔥 CRASH CAUGHT: $e");
                                      }
                                    },
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        leading: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color:
                                                isDark ? Colors.white12 : Colors.black12,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            CupertinoIcons.clock,
                                            color: Colors.grey,
                                            size: 18,
                                          ),
                                        ),
                                        title: Text(
                                          place.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                        subtitle: Text(
                                          place.address,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color:
                                                isDark ? Colors.white54 : Colors.black54,
                                            fontSize: 13,
                                          ),
                                        ),
                                        trailing: safeProvider.isEditingHistory
                                            ? IgnorePointer(
                                                child: Checkbox(
                                                  shape: const CircleBorder(), // 🔴 THIS MAKES IT CIRCULAR
                                                  value: provider.selectedForDeletion.contains(place.placeId),
                                                  activeColor: Colors.redAccent,
                                                  onChanged: (bool? selected) {},
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                  if (!isLast)
                                    Divider(
                                      height: 1,
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : Colors.black12,
                                      indent: 60,
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (showRecentSearches && !isSelected)
            const SizedBox(height: 16),
          if (!isSelected && !isFocused && isEmpty)
            Material(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Column(
                children: [
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                      unselectedWidgetColor: iconColor,
                    ),
                    child: ExpansionTile(
                      controller: _nearbyTileCtrl,
                      collapsedShape: const Border(),
                      shape: const Border(),
                      tilePadding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 16),
                      onExpansionChanged: (expanded) {
                        AppHaptics.lightImpact();
                        rebuildState(() {});
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          Future.delayed(const Duration(milliseconds: 50), () {
                            if (_sheetController.isAttached) {
                              unawaited(
                                _sheetController.animateTo(
                                  expanded ? _safeMaxSize : _safeMidSize,
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.fastLinearToSlowEaseIn,
                                ),
                              );
                            }
                          });
                        });
                      },
                      leading: const Icon(Icons.directions_transit_rounded,
                          color: Color(0xFF00E5FF)),
                      title: Text(
                        'Transit Quick Actions',
                        style: TextStyle(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.9)
                              : Colors.black87,
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      iconColor: iconColor,
                      collapsedIconColor: iconColor,
                      children: [
                        _buildNearbyTile(
                          Icons.directions_subway_filled_rounded,
                          const [Color(0xFF5AC8FA), Color(0xFF007AFF)],
                          'Metro Stations',
                          isDark,
                          false,
                        ),
                        _buildNearbyTile(
                          Icons.directions_bus_filled_rounded,
                          const [Color(0xFF65D57B), Color(0xFF34C759)],
                          'Bus Stops',
                          isDark,
                          false,
                        ),
                        _buildNearbyTile(
                          Icons.train_rounded,
                          const [Color(0xFF4CABFF), Color(0xFF0A84FF)],
                          'Railway Stations',
                          isDark,
                          true,
                        ),
                      ],
                    ),
                  ),
                  if (showQuickActions)
                    Column(
                              children: [
                                Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  indent: 52,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.08),
                                ),
                                RidelBounceButton(
                                  onTap: () async {
                                    AppHaptics.lightImpact();
                                    final locService = Provider.of<GlobalLocationService>(context, listen: false);
                                    if (locService.currentPosition == null) {
                                      await locService.forceRefreshLocation();
                                    }
                                    final pos = locService.currentPosition;
                                    if (pos != null) {
                                      await MapShareService.shareCurrentLocation(
                                          LatLng(pos.latitude, pos.longitude));
                                    } else {
                                      _showPremiumNotification('Could not get current location.', isError: true);
                                    }
                                  },
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    leading: const Icon(CupertinoIcons.share,
                                        color: Color(0xFF00E5FF), size: 22),
                                    title: Text(
                                      'Share My Location',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white.withValues(alpha: 0.9)
                                            : Colors.black87,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    trailing: Icon(
                                      Icons.chevron_right_rounded,
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.3)
                                          : Colors.black.withValues(alpha: 0.3),
                                    ),
                                  ),
                                ),
                                Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  indent: 52,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.08),
                                ),
                                buildHiddenExtra(
                                  RidelBounceButton(
                                    onTap: () async {
                                      AppHaptics.success();
                                      unawaited(
                                        Provider.of<MapProvider>(
                                          context,
                                          listen: false,
                                        ).markCurrentPosition(context),
                                      );
                                      // 🚀 FIX: Removed ugly SnackBar, using NotificationService
                                      _showPremiumNotification(
                                        'Your current location has been pinned on the map.',
                                      );
                                    },
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      leading: const Icon(CupertinoIcons.pin,
                                          color: Color(0xFF00E5FF), size: 22),
                                      title: Text(
                                        'Mark My Location',
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.9)
                                              : Colors.black87,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      trailing: Icon(
                                        Icons.chevron_right_rounded,
                                        color: isDark
                                            ? Colors.white.withValues(alpha: 0.3)
                                            : Colors.black.withValues(alpha: 0.3),
                                      ),
                                    ),
                                  ),
                                ),  // closes buildHiddenExtra(
                              ],
                            ),  // closes Column(children:
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultQuickActionsRow(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      key: const ValueKey('default_actions_row'),
      scrollDirection: Axis.horizontal,
      physics:
          const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCircularQuickAction(
            icon: CupertinoIcons.house_fill,
            label: 'Home',
            isDark: isDark,
            iconColor: Colors.blueAccent,
            onTap: () => _handleSmartQuickAction('HOME'),
          ),
          const SizedBox(width: 24),
          _buildCircularQuickAction(
            icon: CupertinoIcons.briefcase_fill,
            label: 'Work',
            isDark: isDark,
            iconColor: Colors.blueAccent,
            onTap: () => _handleSmartQuickAction('WORK'),
          ),
          const SizedBox(width: 24),
          _buildCircularQuickAction(
            icon: CupertinoIcons.add,
            label: 'Add Place',
            isDark: isDark,
            iconColor: Colors.blueAccent,
            onTap: () {
              AppHaptics.mediumImpact();
              // Logic for adding custom place
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTransportModesRow(
      BuildContext context, MapProvider provider, bool isDark) {
    return Padding(
      key: const ValueKey('transport_modes_row'),
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: provider.isRouteCalculated
          ? SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A84FF), // Premium Blue
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  // TODO: Phase 3 - Start Turn-by-Turn Navigation
                  debugPrint("Start Navigation Tapped!");
                },
                child: const Text("Start",
                    style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCircularModeButton(context, provider,
                    Icons.directions_walk_rounded, 'Walk', 'walking', isDark),
                _buildCircularModeButton(context, provider, Icons.two_wheeler_rounded,
                    'Bike', 'twowheeler', isDark),
                
                // Wired Car Button
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RidelLiquidButton(
                      width: 52,
                      height: 52,
                      shapeType: LiquidShapeType.circle,
                      onTap: () async {
                        AppHaptics.selectionClick();
                        provider.currentNavMode = 'driving';
                        await provider.calculateAndDrawNativeRoute(context, 'driving');
                        rebuildState(() {});
                      },
                      child: Center(
                        child: Icon(
                          CupertinoIcons.car_detailed,
                          size: 24,
                          color: provider.currentNavMode == 'driving' ? Colors.blueAccent : (isDark ? Colors.white54 : Colors.black54),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Car',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: provider.currentNavMode == 'driving' ? FontWeight.w600 : FontWeight.w500,
                        color: provider.currentNavMode == 'driving' ? Colors.blueAccent : (isDark ? Colors.white54 : Colors.black54),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),

                _buildCircularModeButton(context, provider,
                    Icons.local_shipping_rounded, 'Heavy', 'heavy', isDark),
              ],
            ),
    );
  }

  Widget _buildCircularModeButton(BuildContext context, MapProvider provider,
      IconData icon, String label, String mode, bool isDark) {
    final isSelected = provider.currentNavMode == mode;

    // Minimalist colors: Active is blue, inactive is subtle grey
    const activeColor = Colors.blueAccent;
    final inactiveColor = isDark ? Colors.white54 : Colors.black54;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 🚀 EXACT MATCH: Using your custom Liquid Button for the true premium glass look
        RidelLiquidButton(
          width: 52,
          height: 52,
          shapeType: LiquidShapeType.circle, // Perfect circular shape
          onTap: () async {
            AppHaptics
                .selectionClick(); // 🚀 FIX: iOS style subtle selection haptic

            final hasRouteDrawn = provider.engine.mapUIState.value == MapUIState.routeDrawn;

            // If a route is already drawn for this exact mode, do nothing
            if (isSelected && hasRouteDrawn) return;

            if (!isSelected) {
              // Mode changed → setNavMode handles re-draw internally
              await provider.setNavMode(context, mode);
            } else {
              // Same mode but no route yet (first tap on freshly selected place)
              // → Force draw the route for the current default mode
              if (provider.targetDestination != null) {
                await provider.autoDrawRouteTo(
                    provider.targetDestination!, context);
              }
            }

            // 🚀 FIX: Force UI to rebuild to show the new active color state locally
            rebuildState(() {});
          },
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                icon,
                key: ValueKey<bool>(
                    isSelected), // Ensures smooth transition when color changes
                size: 24,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? activeColor : inactiveColor,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonBox(bool isDark, double width, double height,
      {BoxShape shape = BoxShape.rectangle, double borderRadius = 0}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        shape: shape,
        borderRadius: shape == BoxShape.rectangle
            ? BorderRadius.circular(borderRadius)
            : null,
      ),
    );
  }

  Widget _buildSearchResultsView(bool isDark) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final provider = Provider.of<MapProvider>(context, listen: false);
    final localMatches = provider.recentSearches.where((place) => place.name.toLowerCase().contains(query)).toList();

    // Combine local matches with API results, avoiding duplicates by name
    final combinedResults = [
      ...localMatches,
      ..._searchResults.where((apiPlace) => !localMatches.any((local) => local.name == apiPlace.name))
    ];

    if (_isSearching && combinedResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildProfileStyleCard(
          context,
          isDark: isDark,
          bgColor: isDark ? const Color(0xFF1C1F26) : Colors.white,
          child: Column(
            children: List.generate(4, (index) {
              final isLast = index == 3;
              return Column(
                children: [
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                    leading: _buildSkeletonBox(isDark, 34, 34,
                        shape: BoxShape.circle),
                    title: Padding(
                      padding: const EdgeInsets.only(bottom: 8.0, right: 60),
                      child: _buildSkeletonBox(isDark, double.infinity, 14,
                          borderRadius: 4),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(right: 120),
                      child: _buildSkeletonBox(isDark, double.infinity, 12,
                          borderRadius: 4),
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black12,
                      indent: 60,
                    ),
                ],
              );
            }),
          ),
        ),
      );
    }

    if (combinedResults.isEmpty && !_isSearching) {
      return Padding(
        padding: const EdgeInsets.only(top: 32, bottom: 20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.search,
                size: 42,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
              const SizedBox(height: 12),
              Text(
                'No places found',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try adjusting your search query',
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final dynamicRadius = combinedResults.length == 1 ? 50.0 : 24.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _buildProfileStyleCard(
        context,
        isDark: isDark,
        bgColor: isDark ? const Color(0xFF1C1F26) : Colors.white,
        borderRadius: dynamicRadius,
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          children: combinedResults.asMap().entries.map((entry) {
            final index = entry.key;
            final place = entry.value;
            final isLast = index == combinedResults.length - 1;
            
            // Fetch provider safely BEFORE the gesture callback using the stable build context
            final safeProvider = Provider.of<MapProvider>(context, listen: false);

            return Column(
              children: [
                Listener(
                  behavior: HitTestBehavior.opaque,
                  // Trigger INSTANTLY on touch, before any keyboard unfocus events can destroy the widget
                  onPointerDown: (event) async {
                    debugPrint("💥 RAW POINTER DOWN REGISTERED ON: ${place.name}");
                    AppHaptics.selectionClick();
                    
                    try {
                      // 1. SAVE THE SEARCH TO HISTORY
                      safeProvider.saveNewSearch(place);

                      // 2. Lock State FIRST using the pre-fetched safe provider
                      safeProvider.setDestinationSelected(true);
                      safeProvider.engine.setUIState(MapUIState.placeSelected);
                      
                      // Safely animate sheet to Pill View size
                      if (_sheetController.isAttached) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_sheetController.isAttached) {
                            _sheetController.animateTo(
                              _safeMinSize,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        });
                      }
                      
                      // 2. NOW unfocus the keyboard
                      FocusManager.instance.primaryFocus?.unfocus();
                      
                      // 3. Process Coordinates
                      double lat = place.latitude;
                      double lng = place.longitude;
                      
                      if (lat == 0.0 || lng == 0.0) {
                        if (place.placeId.isNotEmpty) {
                          try {
                            final exactCoords = await PlaceService.getPlaceDetails(place.placeId);
                            if (exactCoords != null) {
                              lat = exactCoords.latitude;
                              lng = exactCoords.longitude;
                            }
                          } catch (_) {}
                        }
                      }
                      
                      // 4. Fly Camera
                      if (lat != 0.0 && lng != 0.0) {
                        safeProvider.setTargetDestination(LatLng(lat, lng));
                        rebuildState(() => _selectedPlace = place);
                        if (_sheetController.isAttached) {
                          _sheetController.animateTo(
                            _safeMinSize,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                          );
                        }
                        // Drop the native Red Circle at the selected place coordinates
                        if (lat != 0.0 && lng != 0.0) {
                          safeProvider.addNativeDestinationPin(LatLng(lat, lng));
                        }
                        await safeProvider.flyToPlace(lat, lng);
                      } else {
                        safeProvider.engine.setUIState(MapUIState.idle); // Fallback
                      }
                    } catch (e) {
                      debugPrint("🔥 CRASH CAUGHT: $e");
                    }
                  },
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : Colors.black12,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.location_solid,
                        color: Colors.grey,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      place.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Divider(
                    height: 1,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black12,
                    indent: 60,
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSheetContent(bool isDark, double progress) {
    if (_searchCtrl.text.isNotEmpty && _selectedPlace == null) {
      return _buildSearchResultsView(isDark);
    }
    return _buildUnifiedExploreView(isDark, progress);
  }

  Widget _buildNearbyTile(
    IconData icon,
    List<Color> colors,
    String label,
    bool isDark,
    bool isLast,
  ) {
    return Column(
      children: [
        RidelBounceButton(
          onTap: () {
            AppHaptics.selectionClick();
            _submitSearch(null, label);
          },
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colors.first.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            title: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white24 : Colors.black12,
              size: 20,
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
            indent: 60,
          ),
      ],
    );
  }
}
