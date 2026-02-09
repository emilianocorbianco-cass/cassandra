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
              return const Color(0xFF9C1A39);
            }
            return null;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFFF6F4EF);
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
      ),

      textTheme:
          const TextTheme(
            headlineLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w600),
          ).apply(
            bodyColor: CassandraColors.primary,
            displayColor: CassandraColors.primary,
          ),
    );
  }
}
