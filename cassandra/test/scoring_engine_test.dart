import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/features/scoring/scoring_engine.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';
import 'package:cassandra/features/predictions/models/pick_option.dart';
import 'package:cassandra/features/predictions/models/prediction_match.dart';

void main() {
  const odds = Odds(
    home: 1.98,
    draw: 3.25,
    away: 4.10,
    homeDraw: 1.32,
    drawAway: 1.70,
    homeAway: 1.45,
  );

  final match = PredictionMatch(
    id: 'm1',
    homeTeam: 'A',
    awayTeam: 'B',
    kickoff: DateTime(2026, 1, 1, 18, 0),
    odds: odds,
  );

  test('single correct adds odds', () {
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.home,
      outcome: MatchOutcome.home,
    );

    expect(s.basePoints, closeTo(1.98, 0.0001));
    expect(s.correct, isTrue);
    expect(s.playedOdds, closeTo(1.98, 0.0001));
  });

  test('single wrong subtracts odds', () {
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.home,
      outcome: MatchOutcome.away,
    );

    expect(s.basePoints, closeTo(-1.98, 0.0001));
    expect(s.correct, isFalse);
    expect(s.playedOdds, closeTo(1.98, 0.0001));
  });

  test('double wrong subtracts sum of singles', () {
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.homeDraw,
      outcome: MatchOutcome.away,
    );

    expect(s.basePoints, closeTo(-(1.98 + 3.25), 0.0001));
    expect(s.correct, isFalse);
    expect(s.playedOdds, closeTo(1.32, 0.0001));
  });

  test('not played subtracts max of 1X2', () {
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.none,
      outcome: MatchOutcome.home,
    );

    // max tra 1.98, 3.25, 4.10 = 4.10
    expect(s.basePoints, closeTo(-4.10, 0.0001));
    expect(s.correct, isFalse);
    expect(s.playedOdds, isNull);
  });

  test('voided match yields zero', () {
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.home,
      outcome: MatchOutcome.voided,
    );

    expect(s.basePoints, closeTo(0.0, 0.0001));
    expect(s.correct, isFalse);
    expect(s.playedOdds, isNull);
  });

  test('bonus table sanity checks', () {
    expect(CassandraScoringEngine.bonusForCorrectCount(0), -20);
    expect(CassandraScoringEngine.bonusForCorrectCount(5), 0);
    expect(CassandraScoringEngine.bonusForCorrectCount(10), 20);
  });
}
