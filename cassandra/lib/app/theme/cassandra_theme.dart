import 'package:flutter/material.dart';
import 'cassandra_colors.dart';

class CassandraTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      cardTheme: const CardThemeData(
        color: CassandraColors.cardBg,
        surfaceTintColor: Colors.transparent,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return CassandraColors.primary;
            }
            return null;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return CassandraColors.onPrimary;
            }
            return null;
          }),
        ),
      ),

      // Colori base
      colorSchemeSeed: CassandraColors.primary,
      scaffoldBackgroundColor: CassandraColors.bg,

      // Font: Avenir su iOS spesso esiste; su Android potrebbe fallbackare.
      // Più avanti possiamo decidere un font unico cross-platform.
      fontFamily: 'Avenir',

      appBarTheme: const AppBarTheme(
        backgroundColor: CassandraColors.bg,
        foregroundColor: CassandraColors.primary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),

      textTheme:
          const TextTheme(
            headlineLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w600),
          ).apply(
            bodyColor: CassandraColors.slate,
            displayColor: CassandraColors.slate,
          ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      cardTheme: const CardThemeData(
        surfaceTintColor: Colors.transparent,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return CassandraColors.primary;
            }
            return null;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return CassandraColors.onPrimary;
            }
            return null;
          }),
        ),
      ),

      colorSchemeSeed: CassandraColors.primary,
      fontFamily: 'Avenir',

      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
    );
  }
}
