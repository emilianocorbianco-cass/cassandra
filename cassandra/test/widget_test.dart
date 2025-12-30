import 'package:flutter_test/flutter_test.dart';
import 'package:cassandra/app/cassandra_app.dart';

void main() {
  testWidgets('CassandraApp builds and shows title', (WidgetTester tester) async {
    await tester.pumpWidget(const CassandraApp());
    expect(find.text('Cassandra'), findsOneWidget);
  });
}
