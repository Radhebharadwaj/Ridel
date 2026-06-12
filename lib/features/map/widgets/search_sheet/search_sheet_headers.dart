part of 'map_search_sheet.dart';

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
          gradient: bgColor == null
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.20),
                    Colors.white.withValues(alpha: 0.10),
                    Colors.white.withValues(alpha: 0.06),
                  ],
                )
              : null,
          color: bgColor,
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
          boxShadow: bgColor == null
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 20,
                    spreadRadius: -2,
                    offset: const Offset(0, 14),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );
  }

  Widget _buildDirectionsHeader(double headerHeight, bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black;
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
                              color: _activeRoutingField == 'origin'
                                  ? _MapSearchSheetState.premiumBlue
                                  : (_originPlace != null
                                      ? Colors.white54
                                      : _MapSearchSheetState.premiumBlue),
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
                            color: _activeRoutingField == 'dest'
                                ? _MapSearchSheetState.premiumBlue
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
                                FocusManager.instance.primaryFocus?.unfocus();
                                rebuildState(
                                    () => _activeRoutingField = 'origin');

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
                                color: _activeRoutingField == 'origin'
                                    ? _MapSearchSheetState.premiumBlue
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
                                        icon: const Icon(
                                          Icons.my_location,
                                          color: _MapSearchSheetState.premiumBlue,
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
                                FocusManager.instance.primaryFocus?.unfocus();
                                rebuildState(
                                    () => _activeRoutingField = 'dest');

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
                                color: _activeRoutingField == 'dest'
                                    ? _MapSearchSheetState.premiumBlue
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
                          color: _MapSearchSheetState.premiumBlue,
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
                  color: _MapSearchSheetState.premiumBlue,
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
                  if (!mounted) return;

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

    final pillBaseColor = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : Colors.white.withValues(alpha: 0.9);
    final borderColor = Colors.white.withValues(alpha: 0.05);

    final horizontalPadding = lerpDouble(8.0, 24.0, progress) ?? 8.0;
    final dynamicHeight = lerpDouble(46.0, 54.0, progress) ?? 46.0;
    final dynamicRadius = lerpDouble(100.0, 20.0, progress) ?? 100.0;

    final topPadding = lerpDouble(6.0, 18.0, progress) ?? 6.0;
    const bottomPadding = 10.0;

    return SizedBox(
      key: const ValueKey('search_header'),
      height: headerHeight,
      child: Padding(
        padding: EdgeInsets.only(
            top: topPadding,
            bottom: bottomPadding,
            left: horizontalPadding,
            right: horizontalPadding),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(dynamicRadius),
          child: RepaintBoundary(
            // 🚀 UX FIX: Added RepaintBoundary around Glass Search Bar
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
                          if (query.isEmpty) {
                            return;
                          }

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

                          if (!mounted) {
                            return;
                          }

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
                                  color: isDark
                                      ? _MapSearchSheetState.premiumBlue
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
        if (_selectedNavMode == mode) return;
        AppHaptics.selectionClick();
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
              ? _MapSearchSheetState.premiumBlue.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: isActive
              ? _MapSearchSheetState.premiumBlue
              : (isDark ? Colors.white38 : Colors.black38),
          size: 22,
        ),
      ),
    );
  }
}
