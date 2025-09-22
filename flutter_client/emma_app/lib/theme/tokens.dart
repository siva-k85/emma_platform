import 'dart:ui';
import 'package:flutter/material.dart';

class AppColors {
  static const teal600 = Color(0xFF12C2B8);
  static const surface = Colors.white;
  static const surfaceVariant = Color(0xFFF5F7F9);
  static const textPrimary = Color(0xFF111416);
  static const textSecondary = Color(0xFF6B7280);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
}

class AppSpacing {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
}

class AppRadius {
  static const card = Radius.circular(24);
  static const button = Radius.circular(32);
}

class AppThemeExt extends ThemeExtension<AppThemeExt> {
  final double cardElevation;
  const AppThemeExt({this.cardElevation = 1});

  @override
  ThemeExtension<AppThemeExt> copyWith({double? cardElevation}) {
    return AppThemeExt(cardElevation: cardElevation ?? this.cardElevation);
  }

  @override
  ThemeExtension<AppThemeExt> lerp(ThemeExtension<AppThemeExt>? other, double t) {
    if (other is! AppThemeExt) return this;
    return AppThemeExt(cardElevation: lerpDouble(cardElevation, other.cardElevation, t)!);
  }
}
