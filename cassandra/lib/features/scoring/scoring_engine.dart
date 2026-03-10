import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import 'models/match_outcome.dart';
import 'models/score_breakdown.dart';

class CassandraScoringEngine {
  /// Bonus/malus basato sulla somma delle quote vincenti.
  static int bonusForWinningOddsSum(double winningOddsSum) {
    if (winningOddsSum < 3) return -10;
    if (winningOddsSum < 5) return -4;
    if (winningOddsSum < 7) return -1;
    if (winningOddsSum < 10) return 0;
    if (winningOddsSum < 12) return 1;
    if (winningOddsSum < 14) return 4;
    if (winningOddsSum < 20) return 10;
    return 20;
  }

  /// Legacy alias kept for callers that still reference correct-count bonus.
  static int bonusForCorrectCount(int correctCount) {
    // No longer used for actual scoring — kept to avoid breaking callers.
    return 0;
  }

  /// Public accessor for the odds of a given pick on a match.
  static double oddsForPick(PredictionMatch match, PickOption pick) {
    return _oddsPlayedForPick(match, pick) ?? 0;
  }

  /// Public accessor for single wrong penalty.
  static double wrongSinglePenalty(PredictionMatch match, PickOption pick) {
    return _wrongSinglePenalty(match, pick);
  }

  /// Public accessor for double-chance wrong penalty.
  static double wrongDoublePenalty(PredictionMatch match, PickOption pick) {
    return _wrongDoublePenalty(match, pick);
  }

  static double _max1X2(Odds o) {
    var m = o.home;
    if (o.draw > m) m = o.draw;
    if (o.away > m) m = o.away;
    return m;
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

  /// Penalità per singola sbagliata: si perde la quota doppia chance opposta.
  ///   Gioco 1 e sbaglio → perdo quota X2 (drawAway)
  ///   Gioco X e sbaglio → perdo quota 12 (homeAway)
  ///   Gioco 2 e sbaglio → perdo quota 1X (homeDraw)
  static double _wrongSinglePenalty(PredictionMatch match, PickOption pick) {
    switch (pick) {
      case PickOption.home:
        return match.odds.drawAway;
      case PickOption.draw:
        return match.odds.homeAway;
      case PickOption.away:
        return match.odds.homeDraw;
      default:
        return 0;
    }
  }

  /// Penalità per doppia chance sbagliata: si perde la quota singola opposta.
  ///   Gioco 1X e sbaglio → perdo quota 2 (away)
  ///   Gioco X2 e sbaglio → perdo quota 1 (home)
  ///   Gioco 12 e sbaglio → perdo quota X (draw)
  static double _wrongDoublePenalty(PredictionMatch match, PickOption pick) {
    switch (pick) {
      case PickOption.homeDraw:
        return match.odds.away;
      case PickOption.drawAway:
        return match.odds.home;
      case PickOption.homeAway:
        return match.odds.draw;
      default:
        return 0;
    }
  }

  /// Calcola punteggio per singola partita (senza bonus giornata).
  static MatchScoreBreakdown scoreMatch({
    required PredictionMatch match,
    required PickOption pick,
    required MatchOutcome outcome,
  }) {
    // 0) OUTCOME NON ANCORA DISPONIBILE -> 0 punti per ora (nessuna penalità).
    // Questo evita di penalizzare "non giocata" prima che la partita sia finita.
    if (outcome.isPending) {
      final played = pick.isNone ? null : _oddsPlayedForPick(match, pick);
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: 0,
        correct: false,
        playedOdds: played,
        note: 'Outcome pending: 0 per ora',
      );
    }

    // 1) Partita annullata/voided: 0 per tutti e non conta quota media
    if (outcome.isVoided) {
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: 0,
        correct: false,
        playedOdds: null,
        note: 'Match voided: 0 per tutti',
      );
    }

    // 2) Partita non giocata dall’utente: -quota più alta (tra 1/X/2)
    if (pick.isNone) {
      final penalty = _max1X2(match.odds);
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: -penalty,
        correct: false,
        playedOdds: null,
        note: 'Non giocata: -max(1,X,2)',
      );
    }

    // 3) Singole
    if (pick.isSingle) {
      final played = _oddsPlayedForPick(match, pick)!;
      final correct = _isCorrectSingle(pick, outcome);
      final base = correct ? played : -_wrongSinglePenalty(match, pick);

      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: base,
        correct: correct,
        playedOdds: played,
        note: correct
            ? 'Singola corretta'
            : 'Singola sbagliata: -quota doppia opposta',
      );
    }

    // 4) Doppie chance
    if (pick.isDouble) {
      final played = _oddsPlayedForPick(match, pick)!;
      final correct = _isCorrectDouble(pick, outcome);

      if (correct) {
        return MatchScoreBreakdown(
          matchId: match.id,
          basePoints: played,
          correct: true,
          playedOdds: played,
          note: 'Doppia corretta',
        );
      } else {
        final penalty = _wrongDoublePenalty(match, pick);
        return MatchScoreBreakdown(
          matchId: match.id,
          basePoints: -penalty,
          correct: false,
          playedOdds: played,
          note: 'Doppia sbagliata: -quota singola opposta',
        );
      }
    }

    // 5) Fallback (non dovrebbe mai succedere)
    return MatchScoreBreakdown(
      matchId: match.id,
      basePoints: 0,
      correct: false,
      playedOdds: null,
      note: 'Caso non gestito',
    );
  }

  /// Calcolo completo della giornata:
  /// somma punti match + bonus in base ai corretti.
  ///
  /// Regola importante:
  /// - il bonus si applica SOLO quando TUTTE le partite hanno un outcome "graded"
  ///   (cioè nessuna è pending).
  static DayScoreBreakdown computeDayScore({
    required List<PredictionMatch> matches,
    required Map<String, PickOption> picksByMatchId,
    required Map<String, MatchOutcome> outcomesByMatchId,
  }) {
    final breakdowns = <MatchScoreBreakdown>[];

    for (final match in matches) {
      final pick = picksByMatchId[match.id] ?? PickOption.none;

      // Se manca outcome per quel match -> pending (non voided!)
      final outcome = outcomesByMatchId[match.id] ?? MatchOutcome.pending;

      breakdowns.add(scoreMatch(match: match, pick: pick, outcome: outcome));
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

    final bonus = allGraded ? bonusForWinningOddsSum(winningOddsSum) : 0;
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
      total: total,
      correctCount: correctCount,
      averageOddsPlayed: avgOdds,
    );
  }
}
