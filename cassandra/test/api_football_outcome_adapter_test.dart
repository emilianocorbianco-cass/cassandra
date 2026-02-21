import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/features/scoring/adapters/api_football_outcome_adapter.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';
import 'package:cassandra/services/api_football/models/api_football_fixture.dart';

ApiFootballFixture _fixture({
  required String statusShort,
  int? homeGoals,
  int? awayGoals,
  int fixtureId = 1,
}) => ApiFootballFixture(
  fixtureId: fixtureId,
  kickoffUtc: DateTime.utc(2026, 1, 1, 18),
  homeName: 'A',
  awayName: 'B',
  statusShort: statusShort,
  homeGoals: homeGoals,
  awayGoals: awayGoals,
);

void main() {
  group('matchOutcomeFromFixture', () {
    group('finished statuses with goals', () {
      for (final status in ['FT', 'AET', 'PEN', 'WO', 'AWD']) {
        test('$status 2-1 -> home', () {
          expect(
            matchOutcomeFromFixture(
              _fixture(statusShort: status, homeGoals: 2, awayGoals: 1),
            ),
            MatchOutcome.home,
          );
        });

        test('$status 1-1 -> draw', () {
          expect(
            matchOutcomeFromFixture(
              _fixture(statusShort: status, homeGoals: 1, awayGoals: 1),
            ),
            MatchOutcome.draw,
          );
        });

        test('$status 0-1 -> away', () {
          expect(
            matchOutcomeFromFixture(
              _fixture(statusShort: status, homeGoals: 0, awayGoals: 1),
            ),
            MatchOutcome.away,
          );
        });
      }
    });

    group('finished status with null goals -> pending', () {
      for (final status in ['FT', 'AET', 'PEN']) {
        test('$status with null goals -> pending', () {
          expect(
            matchOutcomeFromFixture(
              _fixture(statusShort: status, homeGoals: null, awayGoals: null),
            ),
            MatchOutcome.pending,
          );
        });
      }
    });

    group('pending statuses', () {
      for (final status in [
        'NS',
        '1H',
        'HT',
        '2H',
        'ET',
        'PST',
        'SUSP',
        'INT',
        'ABD',
      ]) {
        test('$status -> pending', () {
          expect(
            matchOutcomeFromFixture(_fixture(statusShort: status)),
            MatchOutcome.pending,
          );
        });
      }
    });

    test('CANC -> voided', () {
      expect(
        matchOutcomeFromFixture(_fixture(statusShort: 'CANC')),
        MatchOutcome.voided,
      );
    });
  });

  group('outcomesByMatchIdFromFixtures', () {
    test('uses fixtureId.toString() as map key', () {
      final f = _fixture(
        statusShort: 'FT',
        homeGoals: 1,
        awayGoals: 0,
        fixtureId: 99,
      );
      final map = outcomesByMatchIdFromFixtures([f]);
      expect(map['99'], MatchOutcome.home);
    });

    test('includes all fixtures — pending and voided are not dropped', () {
      final fixtures = [
        _fixture(statusShort: 'FT', homeGoals: 1, awayGoals: 0, fixtureId: 1),
        _fixture(statusShort: 'NS', fixtureId: 2),
        _fixture(statusShort: 'CANC', fixtureId: 3),
      ];
      final map = outcomesByMatchIdFromFixtures(fixtures);
      expect(map.length, 3);
      expect(map['1'], MatchOutcome.home);
      expect(map['2'], MatchOutcome.pending);
      expect(map['3'], MatchOutcome.voided);
    });

    test('accepts empty iterable', () {
      expect(outcomesByMatchIdFromFixtures([]), isEmpty);
    });
  });
}
