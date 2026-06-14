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
/// Health surfaces are intentionally restrained: the three domain groups get
/// distinct accents, while individual metrics inherit from their group. Trend
/// charts still keep semantic identity without turning the page into a rainbow.
abstract final class HealthMetricColors {
  static const Color recovery = Color(0xFF0F766E); // teal
  static const Color activity = Color(0xFF2563EB); // blue
  static const Color body = Color(0xFF7C3AED); // violet

  // ── Recovery ──────────────────────────────────────────────────────
  static const Color hrv = recovery;
  static const Color sleep = recovery;
  static const Color heartRate = recovery;
  static const Color rhr = recovery;
  static const Color spo2 = recovery;
  static const Color respiratoryRate = recovery;
  static const Color bodyBattery = recovery;
  static const Color stress = recovery;

  // ── Activity ──────────────────────────────────────────────────────
  static const Color workout = activity;
  static const Color steps = activity;
  static const Color walkingDistance = activity;
  static const Color floors = activity;
  static const Color trainingLoad = activity;
  static const Color trainingEffect = activity;
  static const Color totalEnergy = activity;

  // ── Body ──────────────────────────────────────────────────────────
  static const Color weight = body;
  static const Color bodyFat = body;
  static const Color vo2Max = body;

  // ── Plan metrics ──────────────────────────────────────────────────
  static const Color confidence = activity;
}
