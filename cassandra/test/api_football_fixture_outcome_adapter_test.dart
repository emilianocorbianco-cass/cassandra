import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/features/scoring/adapters/api_football_fixture_outcome_adapter.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';
import 'package:cassandra/services/api_football/models/api_football_fixture.dart';

void main() {
  test('FT 2-0 -> home', () {
    final f = ApiFootballFixture(
      fixtureId: 1,
      kickoffUtc: DateTime.utc(2026, 1, 1, 12),
      homeName: 'Home',
      awayName: 'Away',
      statusShort: 'FT',
      homeGoals: 2,
      awayGoals: 0,
      round: 'Regular Season - 20',
    );

    final o = matchOutcomeFromApiFootballFixture(f);
    expect(o, MatchOutcome.home);
  });

  test('FT 1-1 -> draw', () {
    final f = ApiFootballFixture(
      fixtureId: 2,
      kickoffUtc: DateTime.utc(2026, 1, 1, 12),
      homeName: 'Home',
      awayName: 'Away',
      statusShort: 'FT',
      homeGoals: 1,
      awayGoals: 1,
      round: null,
    );

    final o = matchOutcomeFromApiFootballFixture(f);
    expect(o, MatchOutcome.draw);
  });

  test('FT 0-3 -> away', () {
    final f = ApiFootballFixture(
      fixtureId: 3,
      kickoffUtc: DateTime.utc(2026, 1, 1, 12),
      homeName: 'Home',
      awayName: 'Away',
      statusShort: 'FT',
      homeGoals: 0,
      awayGoals: 3,
      round: null,
    );

    final o = matchOutcomeFromApiFootballFixture(f);
    expect(o, MatchOutcome.away);
  });

  test('NS -> null', () {
    final f = ApiFootballFixture(
      fixtureId: 4,
      kickoffUtc: DateTime.utc(2026, 1, 1, 12),
      homeName: 'Home',
      awayName: 'Away',
      statusShort: 'NS',
      homeGoals: null,
      awayGoals: null,
      round: null,
    );

    final o = matchOutcomeFromApiFootballFixture(f);
    expect(o, isNull);
  });

  test('FT but goals null -> null', () {
    final f = ApiFootballFixture(
      fixtureId: 5,
      kickoffUtc: DateTime.utc(2026, 1, 1, 12),
      homeName: 'Home',
      awayName: 'Away',
      statusShort: 'FT',
      homeGoals: null,
      awayGoals: null,
      round: null,
    );

    final o = matchOutcomeFromApiFootballFixture(f);
    expect(o, isNull);
  });
}
