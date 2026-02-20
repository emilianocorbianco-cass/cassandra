import 'package:cassandra/features/group/models/group_member.dart';
import 'package:cassandra/features/group/widgets/group_matchday_leaderboard.dart';
import 'package:cassandra/features/predictions/models/pick_option.dart';
import 'package:cassandra/features/predictions/models/prediction_match.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';
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
  group('GroupMatchdayLeaderboard', () {
    testWidgets('shows localized empty state when there are no entries', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupMatchdayLeaderboard(
            matches: [],
            outcomesByMatchId: {},
            members: [],
          ),
        ),
      );

      final context = tester.element(find.byType(GroupMatchdayLeaderboard));
      final l10n = AppLocalizations.of(context)!;

      expect(find.text(l10n.commonNoDataAvailable), findsOneWidget);
    });

    testWidgets('renders leaderboard entries for group members', (
      tester,
    ) async {
      final members = const [
        GroupMember(
          id: 'u1',
          displayName: 'Alice',
          teamName: 'FC Alpha',
          avatarSeed: 11,
        ),
        GroupMember(
          id: 'u2',
          displayName: 'Bob',
          teamName: 'FC Beta',
          avatarSeed: 22,
        ),
      ];

      final overrides = {
        'u1': {'m1': PickOption.home},
        'u2': {'m1': PickOption.away},
      };

      await tester.pumpWidget(
        _wrap(
          GroupMatchdayLeaderboard(
            matches: [_match()],
            outcomesByMatchId: const {'m1': MatchOutcome.home},
            members: members,
            overridePicksByMemberId: overrides,
          ),
        ),
      );

      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text('FC Alpha'), findsOneWidget);
      expect(find.text('FC Beta'), findsOneWidget);

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
    });
  });
}
