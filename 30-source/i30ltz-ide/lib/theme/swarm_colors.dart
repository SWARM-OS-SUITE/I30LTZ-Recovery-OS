import 'package:flutter/material.dart';

/// SWARM OS Design Tokens
/// Ported from oklch-based CSS design system in globals.css
class SwarmColors {
  SwarmColors._();

  // ─── Core Background Palette ────────────────────────────────
  static const Color bg = Color(0xFF04080C);           // oklch(0.12 0.04 280)
  static const Color bgSurface = Color(0xFF08121A);     // oklch(0.15 0.05 280)
  static const Color bgElevated = Color(0xFF0B1822);    // oklch(0.17 0.06 280)
  static const Color bgPanel = Color(0xFF0F1F2B);       // oklch(0.19 0.07 280)
  static const Color bgHover = Color(0xFF14283A);       // oklch(0.21 0.08 280)

  // ─── Text Palette ──────────────────────────────────────────
  static const Color textPrimary = Color(0xFFECFFF6);   // oklch(0.92 0.03 280)
  static const Color textSecondary = Color(0xFF9FC4B4); // oklch(0.72 0.06 280)
  static const Color textMuted = Color(0xFF6C9886);     // oklch(0.55 0.07 280)
  static const Color textDisabled = Color(0xFF3E5C50);   // oklch(0.38 0.08 280)

  // ─── Border & Divider ──────────────────────────────────────
  static const Color border = Color(0xFF16342A);        // oklch(0.22 0.06 280)
  static const Color borderSubtle = Color(0xFF0F241D);  // oklch(0.18 0.05 280)
  static const Color borderFocus = Color(0xFF39FF88);   // I30LTZ green

  // ─── Accent: NVIDIA Green ──────────────────────────────────
  static const Color accent = Color(0xFF39FF88);         // I30LTZ green primary
  static const Color accentDim = Color(0xFF1F9E55);      // Dimmed variant
  static const Color accentGlow = Color(0x3339FF88);     // 20% opacity glow
  static const Color accentSurface = Color(0x1A39FF88);  // 10% for backgrounds

  // ─── Status Colors ─────────────────────────────────────────
  static const Color statusOnline = Color(0xFF22C55E);   // Green
  static const Color statusOffline = Color(0xFFEF4444);  // Red
  static const Color statusIdle = Color(0xFFF59E0B);     // Amber
  static const Color statusBusy = Color(0xFFF97316);     // Orange
  static const Color statusCritical = Color(0xFFDC2626); // Dark Red

  // ─── Agent Accent Palette ──────────────────────────────────
  static const Color agentPurple = Color(0xFF8B5CF6);    // Violet
  static const Color agentCyan = Color(0xFF06B6D4);      // Cyan
  static const Color agentAmber = Color(0xFFF59E0B);     // Amber
  static const Color agentRose = Color(0xFFF43F5E);      // Rose
  static const Color agentEmerald = Color(0xFF10B981);   // Emerald
  static const Color agentSky = Color(0xFF0EA5E9);       // Sky blue
  static const Color agentIndigo = Color(0xFF6366F1);    // Indigo
  static const Color agentOrange = Color(0xFFF97316);    // Orange
  static const Color agentTeal = Color(0xFF14B8A6);      // Teal
  static const Color agentPink = Color(0xFFEC4899);      // Pink
  static const Color agentLime = Color(0xFF84CC16);      // Lime

  // ─── Overlay & Scrim ───────────────────────────────────────
  static const Color scrim = Color(0xCC04080C);          // 80% bg
  static const Color overlay = Color(0x8004080C);        // 50% bg

  // ─── Aliases & Convenience Colors ──────────────────────────
  static const Color bgBase = bg;
  static const Color statusHealthy = statusOnline;
  static const Color statusWarning = statusIdle;
  static const Color accentMuted = accentDim;
  static const Color success = statusOnline;
  static const Color warning = statusIdle;
  static const Color error = statusCritical;
  static const Color accentSky = agentSky;
  static const Color accentCyan = agentCyan;
  static const Color agentGreen = agentEmerald;
}

/// Helper for rounded shape borders
OutlinedBorder roundedCornerShape(double radius) =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
