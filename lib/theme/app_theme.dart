import 'package:flutter/material.dart';

class AppPalette {
  final String id;
  final String nameAr;
  final Brightness brightness;
  final Color bgPrimary;
  final Color bgCard;
  final Color bgElevated;
  final Color borderSubtle;
  final Color accentPrimary;
  final Color accentSecondary;
  final List<Color> waveGradient;
  final Color textPrimary;
  final Color textSecondary;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  const AppPalette({
    required this.id,
    required this.nameAr,
    required this.brightness,
    required this.bgPrimary,
    required this.bgCard,
    required this.bgElevated,
    required this.borderSubtle,
    required this.accentPrimary,
    required this.accentSecondary,
    required this.waveGradient,
    required this.textPrimary,
    required this.textSecondary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  static const midnightRoyal = AppPalette(
    id: 'midnight',
    nameAr: 'الداكن الملكي',
    brightness: Brightness.dark,
    bgPrimary: Color(0xFF090C14),
    bgCard: Color(0xFF121826),
    bgElevated: Color(0xFF1B2336),
    borderSubtle: Color(0xFF28344E),
    accentPrimary: Color(0xFFA855F7),
    accentSecondary: Color(0xFFEC4899),
    waveGradient: [
      Color(0xFFF472B6),
      Color(0xFFD946EF),
      Color(0xFF6D28D9),
    ],
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF97316),
    danger: Color(0xFFEF4444),
    info: Color(0xFF38BDF8),
  );

  static const cyberCyan = AppPalette(
    id: 'cyber',
    nameAr: 'نيون سماوي',
    brightness: Brightness.dark,
    bgPrimary: Color(0xFF071018),
    bgCard: Color(0xFF0F1D2B),
    bgElevated: Color(0xFF172B3F),
    borderSubtle: Color(0xFF223D58),
    accentPrimary: Color(0xFF06B6D4),
    accentSecondary: Color(0xFF3B82F6),
    waveGradient: [
      Color(0xFF67E8F9),
      Color(0xFF06B6D4),
      Color(0xFF1D4ED8),
    ],
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF94A3B8),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFF43F5E),
    info: Color(0xFF38BDF8),
  );

  static const emeraldNight = AppPalette(
    id: 'emerald',
    nameAr: 'زمردي ليلي',
    brightness: Brightness.dark,
    bgPrimary: Color(0xFF08120F),
    bgCard: Color(0xFF10211B),
    bgElevated: Color(0xFF193229),
    borderSubtle: Color(0xFF24473B),
    accentPrimary: Color(0xFF10B981),
    accentSecondary: Color(0xFF14B8A6),
    waveGradient: [
      Color(0xFF6EE7B7),
      Color(0xFF10B981),
      Color(0xFF047857),
    ],
    textPrimary: Color(0xFFF0FDF4),
    textSecondary: Color(0xFF9CA3AF),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    info: Color(0xFF3B82F6),
  );

  static const cleanLight = AppPalette(
    id: 'light',
    nameAr: 'الوضع النهاري الفاتح',
    brightness: Brightness.light,
    bgPrimary: Color(0xFFF1F5F9),
    bgCard: Color(0xFFFFFFFF),
    bgElevated: Color(0xFFE2E8F0),
    borderSubtle: Color(0xFFCBD5E1),
    accentPrimary: Color(0xFF7C3AED),
    accentSecondary: Color(0xFFDB2777),
    waveGradient: [
      Color(0xFFF472B6),
      Color(0xFFA855F7),
      Color(0xFF6D28D9),
    ],
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    success: Color(0xFF16A34A),
    warning: Color(0xFFEA580C),
    danger: Color(0xFFDC2626),
    info: Color(0xFF2563EB),
  );

  static const List<AppPalette> all = [
    midnightRoyal,
    cyberCyan,
    emeraldNight,
    cleanLight,
  ];

  static AppPalette byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return midnightRoyal;
  }

  ThemeData toThemeData() {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Cairo',
      scaffoldBackgroundColor: bgPrimary,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accentPrimary,
        onPrimary: Colors.white,
        secondary: accentSecondary,
        onSecondary: Colors.white,
        error: danger,
        onError: Colors.white,
        surface: bgCard,
        onSurface: textPrimary,
      ),
      cardColor: bgCard,
      dividerColor: borderSubtle,
      dialogBackgroundColor: bgCard,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgElevated,
        contentTextStyle: TextStyle(
          fontFamily: 'Cairo',
          color: textPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
