import 'package:flutter/material.dart';
import 'package:ridel/features/commute/metro/map/metro_map_screen.dart';

class NetworkMapSheetContent extends StatelessWidget {
  const NetworkMapSheetContent({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: MediaQuery.of(context).size.height * 0.75, // 75% of screen
      child: const ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
        child: MetroMapScreen(
          isPanelOpen: false,
          showAppBar: false,
        ),
      ),
    );
  }
}
