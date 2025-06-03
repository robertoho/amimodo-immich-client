import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:math' as math;

class SmoothInteractiveViewer extends StatefulWidget {
  final Widget child;
  final double minScale;
  final double maxScale;
  final TransformationController? transformationController;
  final VoidCallback? onInteractionStart;
  final VoidCallback? onInteractionEnd;
  final void Function(ScaleUpdateDetails)? onInteractionUpdate;
  final bool showZoomIndicator;

  const SmoothInteractiveViewer({
    super.key,
    required this.child,
    this.minScale = 0.1,
    this.maxScale = 4.0,
    this.transformationController,
    this.onInteractionStart,
    this.onInteractionEnd,
    this.onInteractionUpdate,
    this.showZoomIndicator = true,
  });

  @override
  State<SmoothInteractiveViewer> createState() =>
      _SmoothInteractiveViewerState();
}

class _SmoothInteractiveViewerState extends State<SmoothInteractiveViewer>
    with TickerProviderStateMixin {
  late TransformationController _transformationController;
  late AnimationController _animationController;
  late AnimationController _indicatorController;
  late Animation<Matrix4> _scaleAnimation;
  late Animation<double> _indicatorAnimation;

  // Direct visual state - this is what makes it smooth
  Matrix4 _currentTransform = Matrix4.identity();
  double _currentScale = 1.0;
  Offset _currentTranslation = Offset.zero;

  // Gesture state
  bool _isScaling = false;
  double _baseScale = 1.0;
  Offset _baseTranslation = Offset.zero;
  Offset _focalPoint = Offset.zero;

  // Animation state
  bool _isAnimating = false;

  // Zoom indicator state
  bool _showIndicator = false;

  // Standard zoom levels (like macOS Photos)
  static const List<double> _zoomLevels = [0.25, 0.5, 1.0, 2.0, 3.0, 4.0];

  @override
  void initState() {
    super.initState();
    _transformationController =
        widget.transformationController ?? TransformationController();

    // Initialize from controller if provided
    _currentTransform = _transformationController.value;
    _currentScale = _getScaleFromMatrix(_currentTransform);
    _currentTranslation = _getTranslationFromMatrix(_currentTransform);

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _indicatorController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Matrix4Tween().animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _indicatorAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _indicatorController,
        curve: Curves.easeOut,
      ),
    );

    _scaleAnimation.addListener(_onAnimationUpdate);
    _animationController.addStatusListener(_onAnimationStatus);
    _indicatorAnimation.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (widget.transformationController == null) {
      _transformationController.dispose();
    }
    _animationController.dispose();
    _indicatorController.dispose();
    super.dispose();
  }

  void _showZoomIndicator() {
    if (!widget.showZoomIndicator) return;

    setState(() {
      _showIndicator = true;
    });

    _indicatorController.forward();

    // Hide indicator after 1.2 seconds
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && !_isScaling && !_isAnimating) {
        _indicatorController.reverse().then((_) {
          if (mounted) {
            setState(() {
              _showIndicator = false;
            });
          }
        });
      }
    });
  }

  void _onAnimationUpdate() {
    if (_isAnimating && _scaleAnimation.value != null) {
      setState(() {
        _currentTransform = _scaleAnimation.value!;
        _currentScale = _getScaleFromMatrix(_currentTransform);
        _currentTranslation = _getTranslationFromMatrix(_currentTransform);
      });
      _transformationController.value = _currentTransform;
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _isAnimating = false;
    }
  }

  double _getScaleFromMatrix(Matrix4 matrix) {
    return math.sqrt(
        math.pow(matrix.entry(0, 0), 2) + math.pow(matrix.entry(1, 0), 2));
  }

  Offset _getTranslationFromMatrix(Matrix4 matrix) {
    return Offset(matrix.entry(0, 3), matrix.entry(1, 3));
  }

  double _findNearestZoomLevel(double currentScale) {
    double nearestLevel = _zoomLevels.first;
    double minDifference = (currentScale - nearestLevel).abs();

    for (double level in _zoomLevels) {
      final difference = (currentScale - level).abs();
      if (difference < minDifference) {
        minDifference = difference;
        nearestLevel = level;
      }
    }

    return nearestLevel;
  }

  Matrix4 _createMatrix(double scale, Offset translation) {
    return Matrix4.identity()
      ..scale(scale)
      ..translate(translation.dx, translation.dy);
  }

  void _animateToScale(double targetScale) {
    if (_isAnimating || (targetScale - _currentScale).abs() < 0.01) return;

    // Calculate target translation to keep content centered for fit-to-screen
    Offset targetTranslation = _currentTranslation;
    if (targetScale <= 1.0) {
      targetTranslation = Offset.zero; // Center when fitting to screen
    } else {
      // Maintain relative position when zooming
      final scaleFactor = targetScale / _currentScale;
      targetTranslation = Offset(
        _currentTranslation.dx * scaleFactor,
        _currentTranslation.dy * scaleFactor,
      );
    }

    final targetMatrix = _createMatrix(targetScale, targetTranslation);

    _scaleAnimation = Matrix4Tween(
      begin: _currentTransform,
      end: targetMatrix,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _isAnimating = true;
    _animationController.forward(from: 0.0);
    _showZoomIndicator();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _isScaling = true;
    _baseScale = _currentScale;
    _baseTranslation = _currentTranslation;
    _focalPoint = details.localFocalPoint;

    // Stop any ongoing animation
    if (_isAnimating) {
      _animationController.stop();
      _isAnimating = false;
    }

    _showZoomIndicator();
    widget.onInteractionStart?.call();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_isScaling) return;

    // Calculate new scale - allow wide range for smooth gesture
    final newScale = _baseScale * details.scale;

    // Calculate new translation based on focal point
    final focalPointDelta = details.localFocalPoint - _focalPoint;
    final scaleDelta = newScale - _baseScale;

    // Apply focal point scaling
    final newTranslation = Offset(
      _baseTranslation.dx +
          focalPointDelta.dx -
          (details.localFocalPoint.dx * scaleDelta),
      _baseTranslation.dy +
          focalPointDelta.dy -
          (details.localFocalPoint.dy * scaleDelta),
    );

    // Update state immediately for smooth visual feedback
    setState(() {
      _currentScale = newScale;
      _currentTranslation = newTranslation;
      _currentTransform = _createMatrix(_currentScale, _currentTranslation);
    });

    // Also update the controller for external listeners
    _transformationController.value = _currentTransform;

    widget.onInteractionUpdate?.call(details);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!_isScaling) return;

    _isScaling = false;

    // Calculate if this was a significant zoom gesture
    final scaleChange = (_currentScale - _baseScale).abs();
    final significantZoom = scaleChange > 0.1;

    if (significantZoom) {
      // Find the nearest standard zoom level and clamp to bounds
      final targetScale = _findNearestZoomLevel(_currentScale)
          .clamp(widget.minScale, widget.maxScale);

      // Only animate if we're not already close to the target
      if ((targetScale - _currentScale).abs() > 0.05) {
        _animateToScale(targetScale);
      }
    } else {
      // For small gestures, just ensure we're within bounds
      final clampedScale =
          _currentScale.clamp(widget.minScale, widget.maxScale);
      if ((clampedScale - _currentScale).abs() > 0.01) {
        _animateToScale(clampedScale);
      }
    }

    widget.onInteractionEnd?.call();
  }

  void _onDoubleTap() {
    final targetScale = _currentScale < 1.0 ? 1.0 : 0.5;
    _animateToScale(targetScale);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onDoubleTap: _onDoubleTap,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: Transform(
            transform: _currentTransform,
            child: widget.child,
          ),
        ),

        // Zoom level indicator
        if (_showIndicator && widget.showZoomIndicator)
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedBuilder(
                animation: _indicatorAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _indicatorAnimation.value,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${(_currentScale * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
