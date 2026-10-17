import 'package:flutter/material.dart';
import 'swarm_colors.dart';

/// I30LTZ IDE typography (from the SWARM Apex design system)
/// Bundled fonts only (works offline): Lato (UI) and Hack (code), see assets/fonts and pubspec.yaml
class SwarmTextStyles {
  SwarmTextStyles._();

  // ─── Display (hero / splash) ────────────────────────────────
  static TextStyle displayLarge = const TextStyle(fontFamily: 'Lato', 
    fontSize: 48,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.2,
    height: 1.1,
    color: SwarmColors.textPrimary,
  );

  static TextStyle displayMedium = const TextStyle(fontFamily: 'Lato', 
    fontSize: 36,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    height: 1.15,
    color: SwarmColors.textPrimary,
  );

  // ─── Heading ───────────────────────────────────────────────
  static TextStyle h1 = const TextStyle(fontFamily: 'Lato', 
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.2,
    color: SwarmColors.textPrimary,
  );

  static TextStyle h2 = const TextStyle(fontFamily: 'Lato', 
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.25,
    color: SwarmColors.textPrimary,
  );

  static TextStyle title = h2;

  static TextStyle h3 = const TextStyle(fontFamily: 'Lato', 
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
    color: SwarmColors.textPrimary,
  );

  // ─── Body ──────────────────────────────────────────────────
  static TextStyle body = const TextStyle(fontFamily: 'Lato', 
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: SwarmColors.textPrimary,
  );

  static TextStyle headlineMedium = h1;
  static TextStyle bodyMedium = body;

  static TextStyle bodySmall = const TextStyle(fontFamily: 'Lato', 
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: SwarmColors.textSecondary,
  );

  // ─── Labels / UI ───────────────────────────────────────────
  static TextStyle label = const TextStyle(fontFamily: 'Lato', 
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    height: 1.2,
    color: SwarmColors.textMuted,
  );

  static TextStyle labelSmall = const TextStyle(fontFamily: 'Lato', 
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.6,
    height: 1.2,
    color: SwarmColors.textMuted,
  );

  static TextStyle stat = const TextStyle(fontFamily: 'Lato', 
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.1,
    color: SwarmColors.accent,
  );

  // ─── Code / Mono ───────────────────────────────────────────
  static TextStyle code = const TextStyle(fontFamily: 'Hack', 
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: SwarmColors.textPrimary,
  );

  static TextStyle codeSmall = const TextStyle(fontFamily: 'Hack', 
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: SwarmColors.textSecondary,
  );

  static TextStyle terminal = const TextStyle(fontFamily: 'Hack', 
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.7,
    color: SwarmColors.accent,
  );
}
