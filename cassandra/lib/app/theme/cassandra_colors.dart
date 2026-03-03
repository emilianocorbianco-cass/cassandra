import 'package:flutter/material.dart';

class CassandraColors {
  // ── Card / badge ──────────────────────────────────────────────────────────
  static const Color cardBg = Color(0xFFECF0F2); // platinum

  static const Color simBadgeBg = Color(0xFFF5F5F5);
  static const Color simBadgeBorder = Color(0xFFE0E0E0);

  // ── App background ────────────────────────────────────────────────────────
  // Charcoal — global page background.
  static const Color bg = Color(0xFF344A54);

  // ── Brand / primary ───────────────────────────────────────────────────────
  // Amaranth — drives the Material 3 colorSchemeSeed.
  static const Color primary = Color(0xFFE01E48);

  // Testo chiaro su sfondi primari selezionati (es. SegmentedButton).
  static const Color onPrimary = Color(0xFFF6F4EF);

  // Grigio/blu scuro neutro per testi secondari.
  static const Color slate = Color(0xFF405058);

  // ── Navigation bar ────────────────────────────────────────────────────────
  static const Color navBarBg = Color(0xFF0F1F26); // ink black
  static const Color navBarFg = Color(0xFFF6F4EF); // cream — icons & labels

  // ── Offline banner ────────────────────────────────────────────────────────
  static const Color offlineBannerBg = Color(0xFFF9EAC1); // warm yellow
  static const Color offlineContent = Color(0xFF3E5966); // icon & text

  // ── Chat ──────────────────────────────────────────────────────────────────
  // Avatar background for the other user's messages.
  static const Color chatOtherAvatarBg = Color(0xFFF1E6D1);

  // Background of image-message containers (both sides).
  static const Color chatImageBubbleBg = Color(0xFFFDFDFD);

  // Input field border when not focused (muted primary, 30 % opacity).
  static const Color chatInputBorderIdle = Color(0x4D804046);

  // ── Predictions live ──────────────────────────────────────────────────────
  static const Color inkBlack = Color(0xFF0F1F26);
  static const Color darkCyan = Color(0xFF00B884);

  // ── Dividers ──────────────────────────────────────────────────────────────
  // Soft 10 % black divider line.
  static const Color dividerSoft = Color(0x1A000000);

  // ── Predictions v2 palette ──────────────────────────────────────────────
  /// Charcoal — page background for predictions.
  static const Color charcoal = Color(0xFF344A54);

  /// Ink Black v2 — hero card, footer, nav bar, selected odds.
  static const Color inkBlackV2 = Color(0xFF01131B);

  /// Bright Snow — text on dark surfaces.
  static const Color brightSnow = Color(0xFFF6F8F9);

  /// Platinum — match card background.
  static const Color platinum = Color(0xFFECF0F2);
}
