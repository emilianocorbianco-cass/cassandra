import 'package:cassandra/features/predictions/models/pick_option.dart';
import 'package:cassandra/features/predictions/models/prediction_match.dart';
import 'package:cassandra/features/predictions/widgets/prediction_match_card.dart';
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

PredictionMatch _match() {
  return PredictionMatch(
    id: 'm1',
    homeTeam: 'Inter',
    awayTeam: 'Milan',
    kickoff: DateTime.utc(2026, 2, 20, 20, 45),
    odds: const Odds(
      home: 2.10,
      draw: 3.20,
      away: 3.40,
      homeDraw: 1.30,
      drawAway: 1.80,
      homeAway: 1.35,
    ),
  );
}

void main() {
  group('PredictionMatchCard', () {
    testWidgets('renders teams and odds', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PredictionMatchCard(
            match: _match(),
            pick: PickOption.none,
            locked: false,
            onPick: (_) {},
          ),
        ),
      );

      expect(find.text('Inter'), findsOneWidget);
      expect(find.text('Milan'), findsOneWidget);

      expect(find.text('1'), findsWidgets);
      expect(find.text('X'), findsWidgets);
      expect(find.text('2'), findsWidgets);
      expect(find.text('1X'), findsOneWidget);
      expect(find.text('X2'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);

      expect(find.text('2,10'), findsOneWidget);
      expect(find.text('1,80'), findsOneWidget);
    });

    testWidgets('fires onPick when unlocked', (tester) async {
      PickOption? picked;

      await tester.pumpWidget(
        _wrap(
          PredictionMatchCard(
            match: _match(),
            pick: PickOption.none,
            locked: false,
            onPick: (value) => picked = value,
          ),
        ),
      );

      await tester.tap(find.text('X2'));
      await tester.pumpAndSettle();

      expect(picked, PickOption.drawAway);
    });

    testWidgets('does not fire onPick when locked', (tester) async {
      PickOption? picked;

      await tester.pumpWidget(
        _wrap(
          PredictionMatchCard(
            match: _match(),
            pick: PickOption.none,
            locked: true,
            onPick: (value) => picked = value,
          ),
        ),
      );

      await tester.tap(find.text('X2'));
      await tester.pumpAndSettle();

      expect(picked, isNull);
    });
  });
}
