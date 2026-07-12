// lib/core/widgets/ridel_floating_panel.dart
import 'package:flutter/material.dart';

class RidelFloatingPanel extends StatefulWidget {
  final ScrollableWidgetBuilder builder;
  final double initialChildSize;
  final double minChildSize;
  final double maxHeight;

  const RidelFloatingPanel({
    super.key,
    required this.builder,
    this.initialChildSize = 0.15,
    this.minChildSize = 0.15,
    this.maxHeight = 0.85,
  });

  @override
  State<RidelFloatingPanel> createState() => _RidelFloatingPanelState();
}

class _RidelFloatingPanelState extends State<RidelFloatingPanel> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: widget.initialChildSize,
      minChildSize: widget.minChildSize,
      maxChildSize: widget.maxHeight,
      snap: true,
      snapSizes: [
        widget.initialChildSize,
        0.5, // Semi-open state
        widget.maxHeight, // Full state
      ],
      builder: (context, scrollController) {
        return Material(
          color: Colors.transparent,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0B0E17),
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [
                BoxShadow(color: Colors.black54, blurRadius: 40)
              ],
            ),
            child: Column(
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 14, bottom: 8),
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                // Content builder receives the scrollController
                Expanded(
                  child: widget.builder(context, scrollController),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
