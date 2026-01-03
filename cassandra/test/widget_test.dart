import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/app/cassandra_app.dart';
import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/app/state/cassandra_scope.dart';

void main() {
  testWidgets('CassandraApp: splash then home', (WidgetTester tester) async {
    // Simula uno schermo iPhone (evita layout “desktop”)
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    // AppState finto (non usa SharedPreferences)
    final appState = AppState.inMemory();

    // Pump dell'app wrappata con CassandraScope
    await tester.pumpWidget(
      CassandraScope(notifier: appState, child: const CassandraApp()),
    );

    // Primo frame
    await tester.pump();

    // Lascia finire splash timer + animazioni
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    // Assert robusto: basta che esista una navigation principale
    final hasNav = find.byType(NavigationBar).evaluate().isNotEmpty;
    final hasBottom = find.byType(BottomNavigationBar).evaluate().isNotEmpty;
    final hasRail = find.byType(NavigationRail).evaluate().isNotEmpty;

    if (!hasNav && !hasBottom && !hasRail) {
      debugDumpApp();
    }

    expect(hasNav || hasBottom || hasRail, isTrue);
  });
}
