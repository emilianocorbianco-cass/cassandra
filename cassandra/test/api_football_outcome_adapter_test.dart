import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/features/scoring/adapters/api_football_outcome_adapter.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';
import 'package:cassandra/services/api_football/models/api_football_fixture.dart';

void main() {
  test('FT with goals -> home/draw/away', () {
    final homeWin = ApiFootballFixture(
      fixtureId: 10,
      kickoffUtc: DateTime.utc(2026, 1, 1, 18, 0),
      homeName: 'A',
      awayName: 'B',
      statusShort: 'FT',
      homeGoals: 2,
      awayGoals: 1,
    );
    expect(matchOutcomeFromFixture(homeWin), MatchOutcome.home);

    final draw = ApiFootballFixture(
      fixtureId: 11,
      kickoffUtc: DateTime.utc(2026, 1, 1, 18, 0),
      homeName: 'A',
      awayName: 'B',
      statusShort: 'FT',
      homeGoals: 0,
      awayGoals: 0,
    );
    expect(matchOutcomeFromFixture(draw), MatchOutcome.draw);

    final awayWin = ApiFootballFixture(
      fixtureId: 12,
      kickoffUtc: DateTime.utc(2026, 1, 1, 18, 0),
      homeName: 'A',
      awayName: 'B',
      statusShort: 'FT',
      homeGoals: 1,
      awayGoals: 3,
    );
    expect(matchOutcomeFromFixture(awayWin), MatchOutcome.away);
  });

  test('NS/live -> pending', () {
    final ns = ApiFootballFixture(
      fixtureId: 20,
      kickoffUtc: DateTime.utc(2026, 1, 1, 18, 0),
      homeName: 'A',
      awayName: 'B',
      statusShort: 'NS',
      homeGoals: null,
      awayGoals: null,
    );
    expect(matchOutcomeFromFixture(ns), MatchOutcome.pending);

    final live = ApiFootballFixture(
      fixtureId: 21,
      kickoffUtc: DateTime.utc(2026, 1, 1, 18, 0),
      homeName: 'A',
      awayName: 'B',
      statusShort: '1H',
      homeGoals: 1,
      awayGoals: 0,
    );
    expect(matchOutcomeFromFixture(live), MatchOutcome.pending);
  });

  test('PST/CANC -> voided', () {
    final pst = ApiFootballFixture(
      fixtureId: 30,
      kickoffUtc: DateTime.utc(2026, 1, 1, 18, 0),
      homeName: 'A',
      awayName: 'B',
      statusShort: 'PST',
      homeGoals: null,
      awayGoals: null,
    );
    expect(matchOutcomeFromFixture(pst), MatchOutcome.voided);
  });

  test('map builder uses fixtureId.toString() as key', () {
    final f = ApiFootballFixture(
      fixtureId: 99,
      kickoffUtc: DateTime.utc(2026, 1, 1, 18, 0),
      homeName: 'A',
      awayName: 'B',
      statusShort: 'FT',
      homeGoals: 1,
      awayGoals: 0,
    );

    final map = outcomesByMatchIdFromFixtures([f]);
    expect(map['99'], MatchOutcome.home);
  });
}
