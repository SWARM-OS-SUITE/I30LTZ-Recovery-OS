import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Global accessibility state (singleton) ───────────────────────────────────
class AccessibilitySettings extends ChangeNotifier {
  static final AccessibilitySettings instance = AccessibilitySettings._();
  AccessibilitySettings._();

  double _fontSize = 13.5;
  bool _highContrast = false;
  bool _focusRings = true;
  bool _reducedMotion = false;
  double _lineHeight = 20.0;

  double get fontSize => _fontSize;
  bool get highContrast => _highContrast;
  bool get focusRings => _focusRings;
  bool get reducedMotion => _reducedMotion;
  double get lineHeight => _lineHeight;

  static const _kFontSize       = 'a11y_fontSize';
  static const _kHighContrast   = 'a11y_highContrast';
  static const _kFocusRings     = 'a11y_focusRings';
  static const _kReducedMotion  = 'a11y_reducedMotion';
  static const _kLineHeight     = 'a11y_lineHeight';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _fontSize      = p.getDouble(_kFontSize)     ?? 13.5;
    _highContrast  = p.getBool(_kHighContrast)   ?? false;
    _focusRings    = p.getBool(_kFocusRings)     ?? true;
    _reducedMotion = p.getBool(_kReducedMotion)  ?? false;
    _lineHeight    = p.getDouble(_kLineHeight)   ?? 20.0;
    notifyListeners();
  }

  Future<void> setFontSize(double v) async {
    _fontSize = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_kFontSize, v);
  }

  Future<void> setHighContrast(bool v) async {
    _highContrast = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_kHighContrast, v);
  }

  Future<void> setFocusRings(bool v) async {
    _focusRings = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_kFocusRings, v);
  }

  Future<void> setReducedMotion(bool v) async {
    _reducedMotion = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_kReducedMotion, v);
  }

  Future<void> setLineHeight(double v) async {
    _lineHeight = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setDouble(_kLineHeight, v);
  }

  Future<void> resetDefaults() async {
    await setFontSize(13.5);
    await setHighContrast(false);
    await setFocusRings(true);
    await setReducedMotion(false);
    await setLineHeight(20.0);
  }
}
