import 'package:flutter/material.dart';

/// Central colour tokens for Pocketknife. Derived from the product mockup:
/// a clean, private "everyday file tools" utility — soft blue canvas, white
/// cards, deep-navy primary actions, and one bright accent blue.
class AppColors {
  AppColors._();

  // Canvas & surfaces
  static const Color background = Color(0xFFEEF3F8);
  static const Color backgroundTop = Color(0xFFE4EDF6); // splash gradient top
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF4F7FB);

  // Text
  static const Color ink = Color(0xFF0F1B2D);
  static const Color muted = Color(0xFF64748B);
  static const Color faint = Color(0xFF94A3B8);

  // Brand
  static const Color primary = Color(0xFF16233B); // deep navy — primary buttons
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFF2563EB); // bright blue — links, selection
  static const Color onAccent = Color(0xFFFFFFFF);

  // Lines & fills
  static const Color line = Color(0xFFE2E8F0);
  static const Color lineStrong = Color(0xFFCBD5E1);
  static const Color track = Color(0xFFE7EDF4);

  // Status
  static const Color success = Color(0xFF16A34A);
  static const Color successBg = Color(0xFFE7F6EE);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);

  // Accent-tinted chip (e.g. "Recommended")
  static const Color accentSoft = Color(0xFFE7F0FF);

  // Per-tool accents (icon tiles)
  static const Color toolVideo = Color(0xFFEF4444);
  static const Color toolVideoBg = Color(0xFFFDECEC);
  static const Color toolMp3 = Color(0xFF3B82F6);
  static const Color toolMp3Bg = Color(0xFFE9F1FE);
  static const Color toolPhoto = Color(0xFF22A45D);
  static const Color toolPhotoBg = Color(0xFFE6F5EC);
  static const Color toolDocs = Color(0xFFF59E0B);
  static const Color toolDocsBg = Color(0xFFFDF3E2);
}
