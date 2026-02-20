import 'package:cassandra/app/widgets/demo_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('DemoBanner', () {
    testWidgets('renders label and info icon', (tester) async {
      const label = 'Sample data - wait for backend sync';

      await tester.pumpWidget(_wrap(const DemoBanner(label: label)));

      expect(find.text(label), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byType(Container), findsWidgets);
    });
  });
}
