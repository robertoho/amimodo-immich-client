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

class _PinchZoomGridState extends State<PinchZoomGrid>
    with TickerProviderStateMixin {
  final GridScaleService _gridScaleService = GridScaleService();
  late double _initialScale;
  late double _currentScale;
  bool _isScaling = false;

  // Visual transform state for smooth pinch zoom
  Matrix4 _visualTransform = Matrix4.identity();
  double _visualScale = 1.0;
  double _transitionStartScale = 1.0; // Store the scale at start of transition
  late AnimationController _transitionController;
  late Animation<double> _transitionAnimation;
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    _initialScale = _gridScaleService.scaleFactor;
    _currentScale = _initialScale;

    // Animation controller for smooth transition from visual zoom to grid adaptation
    _transitionController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _transitionAnimation = CurvedAnimation(
      parent: _transitionController,
      curve: Curves.easeOutCubic,
    );

    _transitionAnimation.addListener(_onTransitionUpdate);
    _transitionController.addStatusListener(_onTransitionStatus);
  }

  @override
  void dispose() {
    _transitionController.dispose();
    super.dispose();
  }

  void _onTransitionUpdate() {
    setState(() {
      // Interpolate from transition start scale back to 1.0 as grid adapts
      final currentProgress = _transitionAnimation.value;
      _visualScale = _transitionStartScale +
          (1.0 - _transitionStartScale) * currentProgress;
      _visualTransform = Matrix4.identity()..scale(_visualScale);
    });
  }

  void _onTransitionStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() {
        _isTransitioning = false;
        _visualTransform = Matrix4.identity();
        _visualScale = 1.0;
      });
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _initialScale = _gridScaleService.scaleFactor;
    _currentScale = _initialScale;
    _isScaling = true;

    // Stop any ongoing transition
    if (_isTransitioning) {
      _transitionController.stop();
      _isTransitioning = false;
    }

    // Reset visual transform
    _visualTransform = Matrix4.identity();
    _visualScale = 1.0;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount == 2 && _isScaling) {
      // Only respond to pinch gestures (2 fingers)
      _currentScale = _initialScale * details.scale;
      _currentScale = _currentScale.clamp(
        _gridScaleService.getMinScale(),
        _gridScaleService.getMaxScale(),
      );

      // Apply visual transform instead of immediately updating grid scale
      // This creates the smooth zoom effect during the gesture
      setState(() {
        _visualScale = details.scale;
        _visualTransform = Matrix4.identity()..scale(_visualScale);
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!_isScaling) return;

    _isScaling = false;

    // Now update the grid scale service to adapt the tiles
    _gridScaleService.setScaleFactorImmediate(_currentScale);
    _gridScaleService.persistScaleFactor(_currentScale);

    // Start transition animation to smoothly transition from visual zoom to grid adaptation
    if (_visualScale != 1.0) {
      setState(() {
        _isTransitioning = true;
        _transitionStartScale = _visualScale; // Store current visual scale
      });
      _transitionController.forward(from: 0.0);
    }

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
      child: Transform(
        transform: _visualTransform,
        alignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}
