import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GridScaleService extends ChangeNotifier {
  static final GridScaleService _instance = GridScaleService._internal();
  factory GridScaleService() => _instance;
  GridScaleService._internal();

  static const String _scaleKey = 'grid_scale_factor';
  static const double _defaultScale = 1.0;
  static const double _minScale = 0.3;
  static const double _maxScale = 3.0;

  double _scaleFactor = _defaultScale;
  double get scaleFactor => _scaleFactor;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _scaleFactor = prefs.getDouble(_scaleKey) ?? _defaultScale;
    notifyListeners();
  }

  Future<void> setScaleFactor(double scale) async {
    scale = scale.clamp(_minScale, _maxScale);
    if ((_scaleFactor - scale).abs() > 0.01) {
      // Only update if change is significant
      _scaleFactor = scale;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_scaleKey, _scaleFactor);
      notifyListeners();
    }
  }

  // Immediate update without persistence for smooth real-time scaling
  void setScaleFactorImmediate(double scale) {
    scale = scale.clamp(_minScale, _maxScale);
    if (_scaleFactor != scale) {
      _scaleFactor = scale;
      notifyListeners();
    }
  }

  // Persist the scale factor to preferences (called at end of gesture)
  Future<void> persistScaleFactor(double scale) async {
    scale = scale.clamp(_minScale, _maxScale);
    _scaleFactor = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scaleKey, _scaleFactor);
  }

  void updateScale(double delta) {
    final newScale = (_scaleFactor + delta).clamp(_minScale, _maxScale);
    setScaleFactor(newScale);
  }

  int getGridColumnCount(double width) {
    // Base column counts based on screen width
    int baseColumns;
    if (width > 1200) {
      baseColumns = 5;
    } else if (width > 800) {
      baseColumns = 4;
    } else if (width > 600) {
      baseColumns = 3;
    } else {
      baseColumns = 2;
    }

    // Apply scale factor with proper pinch behavior
    // Higher scale factor = fewer columns = bigger tiles (pinch out)
    // Lower scale factor = more columns = smaller tiles (pinch in)
    final scaledColumns = (baseColumns / _scaleFactor).round();

    // Ensure we have at least 1 column and reasonable maximum
    final maxColumns = (baseColumns * 3).round();
    return scaledColumns.clamp(1, maxColumns);
  }

  double getMinScale() => _minScale;
  double getMaxScale() => _maxScale;
}
