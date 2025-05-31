import 'package:flutter/material.dart';
import '../services/grid_scale_service.dart';

class PinchZoomGrid extends StatefulWidget {
  final Widget child;

  const PinchZoomGrid({
    super.key,
    required this.child,
  });

  @override
  State<PinchZoomGrid> createState() => _PinchZoomGridState();
}

class _PinchZoomGridState extends State<PinchZoomGrid> {
  final GridScaleService _gridScaleService = GridScaleService();
  late double _initialScale;
  late double _currentScale;
  bool _isScaling = false;

  @override
  void initState() {
    super.initState();
    _initialScale = _gridScaleService.scaleFactor;
    _currentScale = _initialScale;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _initialScale = _gridScaleService.scaleFactor;
    _currentScale = _initialScale;
    _isScaling = true;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount == 2 && _isScaling) {
      // Only respond to pinch gestures (2 fingers)
      _currentScale = _initialScale * details.scale;
      _currentScale = _currentScale.clamp(
        _gridScaleService.getMinScale(),
        _gridScaleService.getMaxScale(),
      );

      // Update immediately for buttery smooth animation
      _gridScaleService.setScaleFactorImmediate(_currentScale);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _isScaling = false;

    // Persist final scale to preferences
    _gridScaleService.persistScaleFactor(_currentScale);

    // Show scale indicator
    if (mounted) {
      final scalePercentage = (_currentScale * 100).round();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Grid scale: $scalePercentage%'),
          duration: const Duration(milliseconds: 600),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height * 0.8,
            left: 20,
            right: 20,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      child: widget.child,
    );
  }
}
