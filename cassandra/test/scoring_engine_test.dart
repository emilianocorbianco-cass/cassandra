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

  // ── Singola corretta ─────────────────────────────────────────────────────

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

  // ── Singola sbagliata: 0 punti (regolamento) ────────────────────────────

  test('single wrong: 0 points', () {
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.home,
      outcome: MatchOutcome.away,
    );

    expect(s.basePoints, closeTo(0.0, 0.0001));
    expect(s.correct, isFalse);
    expect(s.playedOdds, closeTo(1.98, 0.0001));
  });

  // ── Doppia corretta ──────────────────────────────────────────────────────

  test('double correct adds double-chance odds', () {
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.homeDraw,
      outcome: MatchOutcome.home,
    );

    expect(s.basePoints, closeTo(1.32, 0.0001));
    expect(s.correct, isTrue);
    expect(s.playedOdds, closeTo(1.32, 0.0001));
  });

  // ── Doppia sbagliata: 0 punti ────────────────────────────────────────────

  test('double wrong: 0 points', () {
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.homeDraw,
      outcome: MatchOutcome.away,
    );

    expect(s.basePoints, closeTo(0.0, 0.0001));
    expect(s.correct, isFalse);
    expect(s.playedOdds, closeTo(1.32, 0.0001));
  });

  // ── Non giocata: auto-assegna quota più bassa ────────────────────────────

  test('not played auto-assigns lowest odds (home=1.98 is lowest)', () {
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.none,
      outcome: MatchOutcome.home,
    );

    // home (1.98) is lowest → auto-assigned home, outcome is home → correct
    expect(s.basePoints, closeTo(1.98, 0.0001));
    expect(s.correct, isTrue);
    expect(s.playedOdds, closeTo(1.98, 0.0001));
  });

  test('not played auto-assigns lowest odds, wrong outcome gives 0', () {
    final s = CassandraScoringEngine.scoreMatch(
      match: match,
      pick: PickOption.none,
      outcome: MatchOutcome.away,
    );

    // home (1.98) is lowest → auto-assigned home, outcome is away → wrong
    expect(s.basePoints, closeTo(0.0, 0.0001));
    expect(s.correct, isFalse);
    expect(s.playedOdds, closeTo(1.98, 0.0001));
  });

  test('auto-assign tiebreak: home wins over draw', () {
    final tieMatch = PredictionMatch(
      id: 'm_tie',
      homeTeam: 'X',
      awayTeam: 'Y',
      kickoff: DateTime(2026, 1, 1, 18, 0),
      odds: const Odds(
        home: 2.50,
        draw: 2.50,
        away: 3.00,
        homeDraw: 1.20,
        drawAway: 1.40,
        homeAway: 1.30,
      ),
    );

    final pick = CassandraScoringEngine.lowestOddsPick(tieMatch);
    expect(pick, PickOption.home); // home wins tiebreak
  });

  // ── Voided / Pending ─────────────────────────────────────────────────────

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

  test('pending outcome yields zero and no bonus', () {
    final day = CassandraScoringEngine.computeDayScore(
      matches: [match],
      picksByMatchId: {'m1': PickOption.home},
      outcomesByMatchId: {},
    );

    expect(day.baseTotal, closeTo(0.0, 0.0001));
    expect(day.bonusPoints, 0);
    expect(day.total, closeTo(0.0, 0.0001));
    expect(day.correctCount, 0);
  });

  // ── Bonus combinato (regolamento ufficiale) ──────────────────────────────

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
    expect(partial.bonusPoints, 0); // not all graded

    final complete = CassandraScoringEngine.computeDayScore(
      matches: [match, match2],
      picksByMatchId: {'m1': PickOption.home, 'm2': PickOption.home},
      outcomesByMatchId: {'m1': MatchOutcome.home, 'm2': MatchOutcome.away},
    );

    // m1: correct → +1.98, m2: wrong → 0. base = 1.98
    // combined = winningOddsSum(1.98) + correctCount(1) = 2.98 → < 9 → bonus -7
    expect(complete.baseTotal, closeTo(1.98, 0.0001));
    expect(complete.correctCount, 1);
    expect(complete.bonusPoints, -7);
    expect(complete.total, closeTo(-5.02, 0.0001));
  });

  // ── Tabella bonus combinato ──────────────────────────────────────────────

  test('bonus table based on combined score (sqv + correct count)', () {
    expect(CassandraScoringEngine.bonusForCombinedScore(0), -7);
    expect(CassandraScoringEngine.bonusForCombinedScore(9), -7);
    expect(CassandraScoringEngine.bonusForCombinedScore(9.01), -4);
    expect(CassandraScoringEngine.bonusForCombinedScore(12), -4);
    expect(CassandraScoringEngine.bonusForCombinedScore(12.01), -1);
    expect(CassandraScoringEngine.bonusForCombinedScore(15), -1);
    expect(CassandraScoringEngine.bonusForCombinedScore(15.01), 0);
    expect(CassandraScoringEngine.bonusForCombinedScore(18), 0);
    expect(CassandraScoringEngine.bonusForCombinedScore(18.01), 1);
    expect(CassandraScoringEngine.bonusForCombinedScore(22), 1);
    expect(CassandraScoringEngine.bonusForCombinedScore(22.01), 4);
    expect(CassandraScoringEngine.bonusForCombinedScore(26), 4);
    expect(CassandraScoringEngine.bonusForCombinedScore(26.01), 7);
    expect(CassandraScoringEngine.bonusForCombinedScore(30), 7);
    expect(CassandraScoringEngine.bonusForCombinedScore(30.01), 10);
    expect(CassandraScoringEngine.bonusForCombinedScore(50), 10);
  });
}
