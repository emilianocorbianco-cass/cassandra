import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import 'models/match_outcome.dart';
import 'models/score_breakdown.dart';

class CassandraScoringEngine {
  /// Bonus/malus basato sulla somma delle quote vincenti (sqv).
  ///   sqv < 5        → -10
  ///   5 ≤ sqv < 8    → -7
  ///   8 ≤ sqv < 10   → -4
  ///   10 ≤ sqv < 11  → -1
  ///   11 ≤ sqv < 12  → +1
  ///   12 ≤ sqv < 13  → +4
  ///   13 ≤ sqv < 15  → +7
  ///   sqv ≥ 15       → +10
  static int bonusForWinningOddsSum(double winningOddsSum) {
    if (winningOddsSum < 5) return -10;
    if (winningOddsSum < 8) return -7;
    if (winningOddsSum < 10) return -4;
    if (winningOddsSum < 11) return -1;
    if (winningOddsSum < 12) return 1;
    if (winningOddsSum < 13) return 4;
    if (winningOddsSum < 15) return 7;
    return 10;
  }

  /// Bonus/malus basato sul numero di pronostici corretti.
  ///   0-1 corretti  → -10
  ///   2-3 corretti  → -7
  ///   4-5 corretti  → -4
  ///   6 corretti    → -1
  ///   7 corretti    → +1
  ///   8 corretti    → +4
  ///   9 corretti    → +7
  ///   10 corretti   → +10
  static int bonusForCorrectCount(int correctCount) {
    if (correctCount <= 1) return -10;
    if (correctCount <= 3) return -7;
    if (correctCount <= 5) return -4;
    if (correctCount == 6) return -1;
    if (correctCount == 7) return 1;
    if (correctCount == 8) return 4;
    if (correctCount == 9) return 7;
    return 10;
  }

  /// Bonus/malus basato sulla somma combinata (sqv + corretti).
  ///   ≤9  → -7 | ≤12 → -4 | ≤15 → -1 | ≤18 → 0
  ///   ≤22 → +1 | ≤26 → +4 | ≤30 → +7 | >30 → +10
  static int bonusForCombinedScore(num combinedScore) {
    if (combinedScore <= 9) return -7;
    if (combinedScore <= 12) return -4;
    if (combinedScore <= 15) return -1;
    if (combinedScore <= 18) return 0;
    if (combinedScore <= 22) return 1;
    if (combinedScore <= 26) return 4;
    if (combinedScore <= 30) return 7;
    return 10;
  }

  /// Returns the single pick (home/draw/away) with the lowest odds.
  static PickOption lowestOddsPick(PredictionMatch match) {
    var min = match.odds.home;
    var pick = PickOption.home;
    if (match.odds.draw < min) {
      min = match.odds.draw;
      pick = PickOption.draw;
    }
    if (match.odds.away < min) {
      pick = PickOption.away;
    }
    return pick;
  }

  /// Public accessor for the odds of a given pick on a match.
  static double oddsForPick(PredictionMatch match, PickOption pick) {
    return _oddsPlayedForPick(match, pick) ?? 0;
  }

  /// Public accessor for single wrong penalty (legacy — now always 0).
  static double wrongSinglePenalty(PredictionMatch match, PickOption pick) {
    return 0;
  }

  /// Public accessor for double-chance wrong penalty (legacy — now always 0).
  static double wrongDoublePenalty(PredictionMatch match, PickOption pick) {
    return 0;
  }

  static double? _oddsPlayedForPick(PredictionMatch match, PickOption pick) {
    switch (pick) {
      case PickOption.none:
        return null;

      case PickOption.home:
        return match.odds.home;
      case PickOption.draw:
        return match.odds.draw;
      case PickOption.away:
        return match.odds.away;

      case PickOption.homeDraw:
        return match.odds.homeDraw;
      case PickOption.drawAway:
        return match.odds.drawAway;
      case PickOption.homeAway:
        return match.odds.homeAway;
    }
  }

  static bool _isCorrectSingle(PickOption pick, MatchOutcome outcome) {
    return (pick == PickOption.home && outcome == MatchOutcome.home) ||
        (pick == PickOption.draw && outcome == MatchOutcome.draw) ||
        (pick == PickOption.away && outcome == MatchOutcome.away);
  }

  static bool _isCorrectDouble(PickOption pick, MatchOutcome outcome) {
    switch (pick) {
      case PickOption.homeDraw:
        return outcome == MatchOutcome.home || outcome == MatchOutcome.draw;
      case PickOption.drawAway:
        return outcome == MatchOutcome.draw || outcome == MatchOutcome.away;
      case PickOption.homeAway:
        return outcome == MatchOutcome.home || outcome == MatchOutcome.away;
      default:
        return false;
    }
  }

  /// Penalità per match il cui kickoff è precedente alla sottomissione.
  static const double lateMatchPenalty = -2;

  /// Calcola punteggio per singola partita.
  ///
  /// Regole:
  /// - Match iniziato prima della sottomissione → -2 punti
  /// - Corretta → guadagni punti pari alla quota giocata
  /// - Sbagliata → 0 punti (nessuna penalità)
  /// - Non giocata → 0 punti
  /// - Voided → 0 punti
  static MatchScoreBreakdown scoreMatch({
    required PredictionMatch match,
    required PickOption pick,
    required MatchOutcome outcome,
    DateTime? submittedAt,
  }) {
    // 0) Match già iniziato al momento della sottomissione → -2.
    if (submittedAt != null && match.kickoff.isBefore(submittedAt)) {
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: lateMatchPenalty,
        correct: false,
        playedOdds: null,
        note: 'Late submission',
      );
    }

    // 1) Outcome non ancora disponibile → 0 punti provvisori.
    if (outcome.isPending) {
      final played = pick.isNone ? null : _oddsPlayedForPick(match, pick);
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: 0,
        correct: false,
        playedOdds: played,
        note: 'Outcome pending',
      );
    }

    // 2) Partita annullata/voided: 0 per tutti
    if (outcome.isVoided) {
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: 0,
        correct: false,
        playedOdds: null,
        note: 'Match voided',
      );
    }

    // 3) Partita non giocata dall'utente: 0 punti
    if (pick.isNone) {
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: 0,
        correct: false,
        playedOdds: null,
        note: 'Non giocata',
      );
    }

    // 4) Singole
    if (pick.isSingle) {
      final played = _oddsPlayedForPick(match, pick)!;
      final correct = _isCorrectSingle(pick, outcome);
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: correct ? played : 0,
        correct: correct,
        playedOdds: played,
        note: correct ? 'Singola corretta' : 'Singola sbagliata',
      );
    }

    // 5) Doppie chance
    if (pick.isDouble) {
      final played = _oddsPlayedForPick(match, pick)!;
      final correct = _isCorrectDouble(pick, outcome);
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: correct ? played : 0,
        correct: correct,
        playedOdds: played,
        note: correct ? 'Doppia corretta' : 'Doppia sbagliata',
      );
    }

    // 6) Fallback
    return MatchScoreBreakdown(
      matchId: match.id,
      basePoints: 0,
      correct: false,
      playedOdds: null,
      note: 'Caso non gestito',
    );
  }

  /// Calcolo completo della giornata:
  /// somma punti match + bonus in base alla somma quote vincenti.
  ///
  /// Il bonus si applica SOLO quando TUTTE le partite hanno outcome graded.
  static DayScoreBreakdown computeDayScore({
    required List<PredictionMatch> matches,
    required Map<String, PickOption> picksByMatchId,
    required Map<String, MatchOutcome> outcomesByMatchId,
    DateTime? submittedAt,
  }) {
    final breakdowns = <MatchScoreBreakdown>[];

    for (final match in matches) {
      final pick = picksByMatchId[match.id] ?? PickOption.none;
      final outcome = outcomesByMatchId[match.id] ?? MatchOutcome.pending;
      breakdowns.add(scoreMatch(
        match: match,
        pick: pick,
        outcome: outcome,
        submittedAt: submittedAt,
      ));
    }

    final baseTotal = breakdowns.fold<double>(
      0,
      (sum, b) => sum + b.basePoints,
    );
    final correctCount = breakdowns.where((b) => b.correct).length;

    // Somma delle quote vincenti (solo partite corrette).
    final winningOddsSum = breakdowns
        .where((b) => b.correct && b.playedOdds != null)
        .fold<double>(0, (sum, b) => sum + b.playedOdds!);

    // Bonus solo se tutte le partite sono graded (nessun pending).
    final allGraded = matches.every((m) {
      final o = outcomesByMatchId[m.id];
      return o != null && !o.isPending;
    });

    final oddsBonus = allGraded ? bonusForWinningOddsSum(winningOddsSum) : 0;
    final correctBonus = allGraded ? bonusForCorrectCount(correctCount) : 0;
    final bonus = oddsBonus + correctBonus;
    final total = baseTotal + bonus;

    final playedOddsValues = breakdowns
        .map((b) => b.playedOdds)
        .whereType<double>()
        .toList();

    final avgOdds = playedOddsValues.isEmpty
        ? null
        : playedOddsValues.reduce((a, b) => a + b) / playedOddsValues.length;

    return DayScoreBreakdown(
      matchBreakdowns: breakdowns,
      baseTotal: baseTotal,
      bonusPoints: bonus,
      oddsBonusPoints: oddsBonus,
      correctBonusPoints: correctBonus,
      total: total,
      correctCount: correctCount,
      averageOddsPlayed: avgOdds,
    );
  }
}
