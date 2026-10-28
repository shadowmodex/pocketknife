import 'package:flutter/material.dart';

/// Central colour tokens for Pocketknife.
/// Vibrant royal blue primary, soft ice-white canvas, clean white cards,
/// and pastel tinted badge tiles matching the reference design.
class AppColors {
  AppColors._();

  // Canvas & surfaces
  static const Color background = Color(0xFFF6F9FC);
  static const Color backgroundTop = Color(0xFFEBF2FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF1F5FB);
  static const Color surfaceSubtle = Color(0xFFEBF2FA);
  static const Color chipInactive = Color(0xFFF1F5F9);

  // Text
  static const Color ink = Color(0xFF0F172A);
  static const Color muted = Color(0xFF64748B);
  static const Color faint = Color(0xFF94A3B8);

  // Brand / Actions
  static const Color primary = Color(0xFF1D61F2); // Vibrant royal blue
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFF1D61F2);
  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color accentSoft = Color(0xFFEFF6FF); // Soft light blue pill/chip fill
  static const Color accentBorder = Color(0xFFBFDBFE);

  // Lines & fills
  static const Color line = Color(0xFFE2E8F0);
  static const Color lineStrong = Color(0xFFCBD5E1);
  static const Color track = Color(0xFFE2E8F0);

  // Status
  static const Color success = Color(0xFF10B981);
  static const Color successBg = Color(0xFFECFDF5);
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerBg = Color(0xFFFEF2F2);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningBg = Color(0xFFFFFBEB);

  // Banner soft pink (Merge PDF summary)
  static const Color bannerPinkBg = Color(0xFFFFF1F2);
  static const Color bannerPinkBorder = Color(0xFFFFE4E6);

  // Tool badge icon colors & backgrounds
  static const Color toolMergePdf = Color(0xFFEF4444);
  static const Color toolMergePdfBg = Color(0xFFFEE2E2);

  static const Color toolImage = Color(0xFF2563EB);
  static const Color toolImageBg = Color(0xFFE0F2FE);

  static const Color toolWord = Color(0xFF1D4ED8);
  static const Color toolWordBg = Color(0xFFDBEAFE);

  static const Color toolText = Color(0xFF10B981);
  static const Color toolTextBg = Color(0xFFDCFCE7);

  static const Color toolSplit = Color(0xFF8B5CF6);
  static const Color toolSplitBg = Color(0xFFF3E8FF);

  static const Color toolCompress = Color(0xFFF59E0B);
  static const Color toolCompressBg = Color(0xFFFEF3C7);

  // Legacy aliases
  static const Color toolDocs = Color(0xFF1D61F2);
  static const Color toolDocsBg = Color(0xFFEFF6FF);
  static const Color toolPhoto = Color(0xFF2563EB);
  static const Color toolPhotoBg = Color(0xFFE0F2FE);
}
