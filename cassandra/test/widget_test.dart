import 'package:flutter_test/flutter_test.dart';
import 'package:cassandra/app/cassandra_app.dart';

void main() {
  testWidgets('Splash then Home', (WidgetTester tester) async {
    await tester.pumpWidget(const CassandraApp());

    // Subito: vedo la scritta Cassandra
    expect(find.text('Cassandra'), findsOneWidget);

    // Aspetto abbastanza da far scattare il timer e la navigazione
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    // Dopo: dovrei essere nella Home (tab Pronostici visibile in qualche punto)
    expect(find.text('Pronostici'), findsWidgets);
  });
}
