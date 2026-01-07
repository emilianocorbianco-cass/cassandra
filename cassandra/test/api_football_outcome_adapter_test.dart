import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/features/scoring/adapters/api_football_outcome_adapter.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';
import 'package:cassandra/services/api_football/models/api_football_fixture.dart';

ApiFootballFixture f({required String status, int? hg, int? ag}) {
  return ApiFootballFixture(
    fixtureId: 123,
    kickoffUtc: DateTime.utc(2026, 1, 1, 18, 0),
    homeName: 'Home',
    awayName: 'Away',
    statusShort: status,
    homeGoals: hg,
    awayGoals: ag,
    round: 'Regular Season - 20',
  );
}

void main() {
  test('FT with goals -> home/draw/away', () {
    expect(
      matchOutcomeFromFixture(f(status: 'FT', hg: 2, ag: 1)),
      MatchOutcome.home,
    );
    expect(
      matchOutcomeFromFixture(f(status: 'FT', hg: 1, ag: 1)),
      MatchOutcome.draw,
    );
    expect(
      matchOutcomeFromFixture(f(status: 'FT', hg: 0, ag: 3)),
      MatchOutcome.away,
    );
  });

  test('AET/PEN behave like finished when goals exist', () {
    expect(
      matchOutcomeFromFixture(f(status: 'AET', hg: 1, ag: 0)),
      MatchOutcome.home,
    );
    expect(
      matchOutcomeFromFixture(f(status: 'PEN', hg: 2, ag: 2)),
      MatchOutcome.draw,
    );
  });

  test('Finished status but missing goals -> pending (safe fallback)', () {
    expect(
      matchOutcomeFromFixture(f(status: 'FT', hg: null, ag: 1)),
      MatchOutcome.pending,
    );
  });

  test('Voided statuses -> voided', () {
    expect(matchOutcomeFromFixture(f(status: 'PST')), MatchOutcome.voided);
    expect(matchOutcomeFromFixture(f(status: 'CANC')), MatchOutcome.voided);
    expect(matchOutcomeFromFixture(f(status: 'ABD')), MatchOutcome.voided);
  });

  test('Non-finished statuses -> pending', () {
    expect(matchOutcomeFromFixture(f(status: 'NS')), MatchOutcome.pending);
    expect(matchOutcomeFromFixture(f(status: '1H')), MatchOutcome.pending);
    expect(matchOutcomeFromFixture(f(status: '2H')), MatchOutcome.pending);
    expect(matchOutcomeFromFixture(f(status: 'HT')), MatchOutcome.pending);
  });
}
