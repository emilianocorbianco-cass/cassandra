import 'package:cassandra/features/predictions/widgets/serie_a_standings_table.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:cassandra/services/api_football/models/api_football_standing.dart';
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

void main() {
  group('SerieAStandingsTable', () {
    testWidgets('renders title, headers and rows', (tester) async {
      final standings = [
        ApiFootballStanding(
          rank: 1,
          teamName: 'Inter',
          played: 25,
          wins: 20,
          draws: 3,
          losses: 2,
          goalsFor: 60,
          goalsAgainst: 20,
          goalDiff: 40,
          points: 63,
          form: 'WWDWW',
        ),
        ApiFootballStanding(
          rank: 2,
          teamName: 'Milan',
          played: 25,
          wins: 18,
          draws: 4,
          losses: 3,
          goalsFor: 52,
          goalsAgainst: 24,
          goalDiff: 28,
          points: 58,
          form: 'WDWLW',
        ),
      ];

      await tester.pumpWidget(
        _wrap(SerieAStandingsTable(standings: standings)),
      );

      final context = tester.element(find.byType(SerieAStandingsTable));
      final l10n = AppLocalizations.of(context)!;

      expect(find.text(l10n.serieAStandingsTitle), findsOneWidget);
      expect(find.text(l10n.serieATeamColumn), findsOneWidget);
      expect(find.text(l10n.serieAPointsColumn), findsOneWidget);

      expect(find.text('Inter'), findsOneWidget);
      expect(find.text('Milan'), findsOneWidget);
      expect(find.text('63'), findsOneWidget);
      expect(find.text('58'), findsOneWidget);

      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(find.text('2'), findsWidgets);
    });
  });
}
