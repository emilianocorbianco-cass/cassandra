import 'package:flutter/material.dart';
import 'cassandra_colors.dart';

class CassandraTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      cardTheme: CardThemeData(
        color: CassandraColors.cardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return CassandraColors.primary;
            }
            return CassandraColors.charcoal;
          }),
          foregroundColor: WidgetStateProperty.all(
            CassandraColors.brightSnow,
          ),
          side: WidgetStateProperty.all(
            const BorderSide(color: CassandraColors.brightSnow, width: 1),
          ),
        ),
      ),

      // Colori base
      colorSchemeSeed: CassandraColors.primary,
      scaffoldBackgroundColor: CassandraColors.bg,

      // Font: Avenir su iOS spesso esiste; su Android potrebbe fallbackare.
      // Più avanti possiamo decidere un font unico cross-platform.
      fontFamily: 'Avenir',

      // TabBar: snow text, amaranth indicator.
      tabBarTheme: const TabBarThemeData(
        labelColor: CassandraColors.brightSnow,
        unselectedLabelColor: CassandraColors.brightSnow,
        indicatorColor: CassandraColors.primary,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: 'Avenir',
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: 'Avenir',
        ),
      ),

      // AppBar ink black — coerente con la NavBar, crea il "frame scuro" premium.
      appBarTheme: const AppBarTheme(
        backgroundColor: CassandraColors.inkBlackV2,
        foregroundColor: CassandraColors.brightSnow,
        titleTextStyle: TextStyle(
          color: CassandraColors.brightSnow,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          fontFamily: 'Avenir',
        ),
        iconTheme: IconThemeData(color: CassandraColors.brightSnow),
        actionsIconTheme: IconThemeData(color: CassandraColors.brightSnow),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),

      // TextTheme con gerarchia tipografica editoriale.
      textTheme:
          const TextTheme(
            headlineLarge: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              height: 1.1,
              letterSpacing: -1.0,
            ),
            titleLarge: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.15,
              letterSpacing: -0.3,
            ),
            titleMedium: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ).apply(
            bodyColor: CassandraColors.slate,
            displayColor: CassandraColors.navBarBg,
          ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return CassandraColors.primary;
            }
            return CassandraColors.charcoal;
          }),
          foregroundColor: WidgetStateProperty.all(
            CassandraColors.brightSnow,
          ),
          side: WidgetStateProperty.all(
            const BorderSide(color: CassandraColors.brightSnow, width: 1),
          ),
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
