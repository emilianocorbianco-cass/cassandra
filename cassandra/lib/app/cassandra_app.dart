import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'theme/cassandra_theme.dart';
import '../features/splash/splash_screen.dart';
import 'state/cassandra_scope.dart';

class CassandraApp extends StatelessWidget {
  const CassandraApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 1) Prima dichiariamo la variabile (istruzione)
    final appState = CassandraScope.of(context);

    // 2) Poi ritorniamo il widget (espressione)
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // Se null -> segue la lingua del sistema
      locale: appState.localeOverride,

      supportedLocales: const [Locale('it'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      title: 'Cassandra',
      theme: CassandraTheme.light(),
      home: const SplashScreen(),
    );
  }
}
