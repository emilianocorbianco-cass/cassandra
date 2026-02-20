import 'package:cassandra/features/predictions/widgets/odds_button.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

Widget _inRow(OddsButton button) => Row(children: [button]);

void main() {
  group('OddsButton', () {
    testWidgets('renders label and formatted odds', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _inRow(
            OddsButton(
              label: '1X',
              odds: 1.33,
              selected: false,
              locked: false,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.text('1X'), findsOneWidget);
      expect(find.text('1,33'), findsOneWidget);
    });

    testWidgets('fires callback when unlocked', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        _wrap(
          _inRow(
            OddsButton(
              label: '2',
              odds: 3.40,
              selected: true,
              locked: false,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('does not fire callback when locked', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        _wrap(
          _inRow(
            OddsButton(
              label: 'X',
              odds: 3.20,
              selected: false,
              locked: true,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      expect(tapped, isFalse);
    });
  });
}
