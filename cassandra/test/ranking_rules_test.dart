import 'package:cassandra/features/scoring/ranking_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareCassandraRanking', () {
    test('orders by total points descending first', () {
      final compare = compareCassandraRanking(
        aTotal: 12,
        bTotal: 9,
        aAverageOddsPlayed: 1.9,
        bAverageOddsPlayed: 3.2,
        aTeamName: 'Alpha',
        bTeamName: 'Beta',
      );

      expect(compare, lessThan(0));
    });

    test('uses average odds as tie-breaker when totals are equal', () {
      final compare = compareCassandraRanking(
        aTotal: 10,
        bTotal: 10,
        aAverageOddsPlayed: 2.1,
        bAverageOddsPlayed: 1.8,
        aTeamName: 'Alpha',
        bTeamName: 'Beta',
      );

      expect(compare, lessThan(0));
    });

    test('treats null average odds as lower than any played average', () {
      final compare = compareCassandraRanking(
        aTotal: 7,
        bTotal: 7,
        aAverageOddsPlayed: null,
        bAverageOddsPlayed: 1.2,
        aTeamName: 'Alpha',
        bTeamName: 'Beta',
      );

      expect(compare, greaterThan(0));
    });

    test('falls back to team name ascending when fully tied', () {
      final compare = compareCassandraRanking(
        aTotal: 5,
        bTotal: 5,
        aAverageOddsPlayed: 1.5,
        bAverageOddsPlayed: 1.5,
        aTeamName: 'Alpha',
        bTeamName: 'Beta',
      );

      expect(compare, lessThan(0));
    });
  });
}
