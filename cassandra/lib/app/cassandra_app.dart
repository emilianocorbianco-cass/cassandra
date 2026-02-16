import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'theme/cassandra_theme.dart';
import '../features/splash/splash_screen.dart';
import 'state/cassandra_scope.dart';

class CassandraApp extends StatelessWidget {
  const CassandraApp({super.key});

  void _dismissKeyboardOnOutsideTap(PointerDownEvent event) {
    final focusNode = FocusManager.instance.primaryFocus;
    if (focusNode == null) return;

    final focusContext = focusNode.context;
    if (focusContext != null) {
      final renderObject = focusContext.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        final localOffset = renderObject.globalToLocal(event.position);
        final bounds = Offset.zero & renderObject.size;
        if (bounds.contains(localOffset)) {
          // Tap dentro il campo attivo: non chiudere tastiera.
          return;
        }
      }
    }

    focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    // 1) Prima dichiariamo la variabile (istruzione)
    final appState = CassandraScope.of(context);

    // 2) Poi ritorniamo il widget (espressione)
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // Se null -> segue la lingua del sistema
      locale: appState.localeOverride,

      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      title: 'Cassandra',
      theme: CassandraTheme.light(),
      builder: (context, child) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _dismissKeyboardOnOutsideTap,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SplashScreen(),
    );
  }
}
