import 'package:flutter/material.dart';

abstract final class RozzaColors {
  static const ink = Color(0xFF08070B);
  static const surface = Color(0xFF111016);
  static const raised = Color(0xFF19171F);
  static const line = Color(0xFF2A2732);
  static const text = Color(0xFFF7F2F5);
  static const muted = Color(0xFFA9A2AB);
  static const rose = Color(0xFFFF3D79);
  static const violet = Color(0xFF9C6BFF);
  static const cyan = Color(0xFF55D6E8);
}

abstract final class RozzaTheme {
  static ThemeData get dark {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'RozzaSans',
    );
    return base.copyWith(
      scaffoldBackgroundColor: RozzaColors.ink,
      colorScheme: const ColorScheme.dark(
        primary: RozzaColors.rose,
        secondary: RozzaColors.violet,
        surface: RozzaColors.surface,
        onSurface: RozzaColors.text,
      ),
      textTheme: base.textTheme
          .apply(bodyColor: RozzaColors.text, displayColor: RozzaColors.text)
          .copyWith(
            displaySmall: base.textTheme.displaySmall?.copyWith(
              fontSize: 36,
              height: 1.02,
              letterSpacing: -1.4,
              fontWeight: FontWeight.w800,
            ),
            headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontSize: 26,
              height: 1.08,
              letterSpacing: -0.7,
              fontWeight: FontWeight.w700,
            ),
            titleLarge: base.textTheme.titleLarge?.copyWith(
              fontSize: 20,
              letterSpacing: -0.3,
              fontWeight: FontWeight.w700,
            ),
            bodyLarge: base.textTheme.bodyLarge?.copyWith(
              fontSize: 16,
              height: 1.35,
            ),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              height: 1.35,
            ),
            labelLarge: base.textTheme.labelLarge?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: Color(0x33FF3D79),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: RozzaColors.text,
        inactiveTrackColor: Color(0x45FFFFFF),
        thumbColor: RozzaColors.text,
        trackHeight: 3,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
