import re

with open('lib/features/commute/metro/map/metro_map_screen.dart', 'r') as f:
    content = f.read()

# Remove flutter_map import
content = re.sub(r"import 'package:flutter_map/flutter_map\.dart';\n", "", content)

# Replace MapController with TransformationController
content = re.sub(r"final MapController _mapController = MapController\(\);", "final TransformationController _transformationController = TransformationController();", content)

# Remove _isMapReady, _isMapCentered
content = re.sub(r"bool _isMapCentered = false;\n\s*bool _isMapReady = false;\n", "", content)

# Replace _animatedMapMove logic
animated_map_move_replacement = """
  void _animatedMapMove(Offset destOffset, double destScale) {
    _animController?.stop();
    _animController?.dispose();

    _animController = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    final Animation<double> animation =
        CurvedAnimation(parent: _animController!, curve: Curves.easeOutCubic);

    final Matrix4 startMatrix = _transformationController.value;
    
    // Calculate end matrix
    // We want the destOffset on the canvas to be at the center of the viewport
    final Size viewportSize = MediaQuery.of(context).size;
    final Matrix4 endMatrix = Matrix4.identity()
      ..translate(
          viewportSize.width / 2.0 - destOffset.dx * destScale,
          viewportSize.height / 2.0 - destOffset.dy * destScale)
      ..scale(destScale);

    final Matrix4Tween matrixTween = Matrix4Tween(begin: startMatrix, end: endMatrix);

    _animController!.addListener(() {
      if (!mounted) return;
      _transformationController.value = matrixTween.evaluate(animation);
    });

    _animController!.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _animController?.dispose();
        _animController = null;
      }
    });

    _animController!.forward();
  }
"""

# We'll just replace the whole body of _MetroMapScreenState to be safe, because there are so many map-specific things.
