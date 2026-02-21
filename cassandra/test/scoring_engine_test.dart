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

  // ── Nuove regole penalità ────────────────────────────────────────────────

  test('single wrong: home pick subtracts drawAway (X2) odds', () {
    // Gioco 1 e sbaglio → perdo la quota X2 (drawAway = 1.70)
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.home,
      outcome: MatchOutcome.away,
    );

    expect(s.basePoints, closeTo(-1.70, 0.0001)); // -drawAway
    expect(s.correct, isFalse);
    expect(s.playedOdds, closeTo(1.98, 0.0001));
  });

  test('single wrong: draw pick subtracts homeAway (12) odds', () {
    // Gioco X e sbaglio → perdo la quota 12 (homeAway = 1.45)
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.draw,
      outcome: MatchOutcome.home,
    );

    expect(s.basePoints, closeTo(-1.45, 0.0001)); // -homeAway
    expect(s.correct, isFalse);
    expect(s.playedOdds, closeTo(3.25, 0.0001));
  });

  test('single wrong: away pick subtracts homeDraw (1X) odds', () {
    // Gioco 2 e sbaglio → perdo la quota 1X (homeDraw = 1.32)
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.away,
      outcome: MatchOutcome.draw,
    );

    expect(s.basePoints, closeTo(-1.32, 0.0001)); // -homeDraw
    expect(s.correct, isFalse);
    expect(s.playedOdds, closeTo(4.10, 0.0001));
  });

  test('double wrong: homeDraw pick subtracts away × 2', () {
    // Gioco 1X e sbaglio → perdo quota 2 × 2 (away × 2 = 8.20)
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.homeDraw,
      outcome: MatchOutcome.away,
    );

    expect(s.basePoints, closeTo(-(4.10 * 2), 0.0001)); // -8.20
    expect(s.correct, isFalse);
    expect(s.playedOdds, closeTo(1.32, 0.0001));
  });

  test('double wrong: drawAway pick subtracts home × 2', () {
    // Gioco X2 e sbaglio → perdo quota 1 × 2 (home × 2 = 3.96)
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.drawAway,
      outcome: MatchOutcome.home,
    );

    expect(s.basePoints, closeTo(-(1.98 * 2), 0.0001)); // -3.96
    expect(s.correct, isFalse);
    expect(s.playedOdds, closeTo(1.70, 0.0001));
  });

  test('double wrong: homeAway pick subtracts draw × 2', () {
    // Gioco 12 e sbaglio → perdo quota X × 2 (draw × 2 = 6.50)
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.homeAway,
      outcome: MatchOutcome.draw,
    );

    expect(s.basePoints, closeTo(-(3.25 * 2), 0.0001)); // -6.50
    expect(s.correct, isFalse);
    expect(s.playedOdds, closeTo(1.45, 0.0001));
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

  test('pending outcome yields zero (no penalty yet) and no bonus', () {
    final day = CassandraScoringEngine.computeDayScore(
      matches: [match],
      picksByMatchId: {'m1': PickOption.home},
      outcomesByMatchId: {},
    );

    expect(day.baseTotal, closeTo(0.0, 0.0001));
    expect(day.bonusPoints, 0);
    expect(day.total, closeTo(0.0, 0.0001));
    expect(day.correctCount, 0);
    expect(day.averageOddsPlayed, closeTo(1.98, 0.0001));
    expect(day.matchBreakdowns, hasLength(1));
    expect(day.matchBreakdowns.first.basePoints, closeTo(0.0, 0.0001));
    expect(day.matchBreakdowns.first.playedOdds, closeTo(1.98, 0.0001));
  });

  test('pending outcome does not apply not-played penalty yet', () {
    final day = CassandraScoringEngine.computeDayScore(
      matches: [match],
      picksByMatchId: {},
      outcomesByMatchId: {},
    );

    expect(day.matchBreakdowns.first.basePoints, closeTo(0.0, 0.0001));
    expect(day.matchBreakdowns.first.playedOdds, isNull);
  });

  test('bonus is applied only when all matches are graded', () {
    final match2 = PredictionMatch(
      id: 'm2',
      homeTeam: 'C',
      awayTeam: 'D',
      kickoff: DateTime(2026, 1, 1, 20, 0),
      odds: odds,
    );

    final partial = CassandraScoringEngine.computeDayScore(
      matches: [match, match2],
      picksByMatchId: {'m1': PickOption.home, 'm2': PickOption.home},
      outcomesByMatchId: {'m1': MatchOutcome.home},
    );

    expect(partial.baseTotal, closeTo(1.98, 0.0001));
    expect(partial.correctCount, 1);
    expect(partial.bonusPoints, 0);

    final complete = CassandraScoringEngine.computeDayScore(
      matches: [match, match2],
      picksByMatchId: {'m1': PickOption.home, 'm2': PickOption.home},
      outcomesByMatchId: {'m1': MatchOutcome.home, 'm2': MatchOutcome.away},
    );

    // m1: home pick correct → +1.98
    // m2: home pick wrong  → -drawAway = -1.70 (nuova regola)
    // base = +1.98 + (-1.70) = +0.28
    expect(complete.baseTotal, closeTo(0.28, 0.0001));
    expect(complete.correctCount, 1);
    expect(complete.bonusPoints, -10); // 1 su 2 corrette → bonus -10
    expect(complete.total, closeTo(0.28 + (-10), 0.0001)); // -9.72
  });
  test('bonus table sanity checks', () {
    expect(CassandraScoringEngine.bonusForCorrectCount(0), -20);
    expect(CassandraScoringEngine.bonusForCorrectCount(5), 0);
    expect(CassandraScoringEngine.bonusForCorrectCount(10), 20);
  });
}
