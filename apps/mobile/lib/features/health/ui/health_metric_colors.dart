/// Shared accent colors for health metric visual identity.
///
/// Each metric kind has a consistent color used across Trend chart lines,
/// Plan input chips, and any future health surfaces. Centralizing these
/// values avoids the same hex literal appearing in multiple files.
///
/// These are *semantic accents*, not theme tokens — they stay constant
/// across light/dark mode because they represent data categories, not
/// chrome. If a brand refresh changes the palette, update this file only.
library;

import 'dart:ui';

/// Accent color per health metric identity.
///
/// Grouped by the visual role each color plays (recovery / activity / body)
/// but the map is flat so callers can look up by a string key.
abstract final class HealthMetricColors {
  // ── Recovery ──────────────────────────────────────────────────────
  static const Color hrv = Color(0xFF6366F1); // indigo
  static const Color sleep = Color(0xFF8B5CF6); // violet
  static const Color heartRate = Color(0xFFEF4444); // red
  static const Color rhr = Color(0xFFF97316); // orange
  static const Color spo2 = Color(0xFF06B6D4); // cyan
  static const Color respiratoryRate = Color(0xFF14B8A6); // teal
  static const Color bodyBattery = Color(0xFF22C55E); // green
  static const Color stress = Color(0xFFF59E0B); // amber

  // ── Activity ──────────────────────────────────────────────────────
  static const Color workout = Color(0xFFEF4444); // red
  static const Color steps = Color(0xFF22C55E); // green
  static const Color walkingDistance = Color(0xFF3B82F6); // blue
  static const Color floors = Color(0xFFF97316); // orange
  static const Color trainingLoad = Color(0xFFEF4444); // red
  static const Color trainingEffect = Color(0xFFF59E0B); // amber
  static const Color totalEnergy = Color(0xFFF97316); // orange

  // ── Body ──────────────────────────────────────────────────────────
  static const Color weight = Color(0xFF3B82F6); // blue
  static const Color bodyFat = Color(0xFF8B5CF6); // violet
  static const Color vo2Max = Color(0xFF22C55E); // green

  // ── Plan metrics ──────────────────────────────────────────────────
  static const Color confidence = Color(0xFF3B82F6); // blue
}
