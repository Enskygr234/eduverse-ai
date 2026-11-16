import 'package:flutter/material.dart';

/// Design tokens. Screens use these instead of raw values so the look stays consistent.
class AppColors {
  const AppColors._();

  static const brand = Color(0xFF5B4CF0); // violet
  static const brandDeep = Color(0xFF3F31C9);
  static const xp = Color(0xFFFFB020); // gold
  static const streak = Color(0xFFFF6B3D); // flame
  static const success = Color(0xFF1FB85A);
  static const successSoft = Color(0xFFD9F7E5);
  static const danger = Color(0xFFE5484D);
  static const dangerSoft = Color(0xFFFDE3E4);

  static const lightBg = Color(0xFFF6F5FB);
  static const lightSurface = Colors.white;
  static const lightBorder = Color(0xFFE4E2EF);
  static const lightText = Color(0xFF1B1A2E);
  static const lightMuted = Color(0xFF6B6984);

  static const darkBg = Color(0xFF111020);
  static const darkSurface = Color(0xFF1C1B2E);
  static const darkBorder = Color(0xFF2E2C47);
  static const darkText = Color(0xFFF1F0FA);
  static const darkMuted = Color(0xFFA19FBD);

  static Color fromHex(String hex, {Color fallback = brand}) {
    final h = hex.replaceFirst('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v == null ? fallback : Color(v);
  }
}

class Space {
  const Space._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class Radii {
  const Radii._();
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const pill = 999.0;
}

class Motion {
  const Motion._();
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const curve = Curves.easeOutCubic;
}
