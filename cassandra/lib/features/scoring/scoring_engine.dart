import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import 'models/match_outcome.dart';
import 'models/score_breakdown.dart';

class CassandraScoringEngine {
  // Tabella bonus/malus (come da regole Cassandra)
  static const Map<int, int> _bonusByCorrect = {
    0: -20,
    1: -10,
    2: -5,
    3: -2,
    4: -1,
    5: 0,
    6: 1,
    7: 2,
    8: 5,
    9: 10,
    10: 20,
  };

  static int bonusForCorrectCount(int correctCount) {
    final int c = correctCount.clamp(0, 10);
    return _bonusByCorrect[c] ?? 0;
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

  static double _wrongDoublePenaltySumSingles(
    PredictionMatch match,
    PickOption pick,
  ) {
    switch (pick) {
      case PickOption.homeDraw:
        return match.odds.home + match.odds.draw;
      case PickOption.drawAway:
        return match.odds.draw + match.odds.away;
      case PickOption.homeAway:
        return match.odds.home + match.odds.away;
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
      final base = correct ? played : -played;

      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: base,
        correct: correct,
        playedOdds: played,
        note: correct ? 'Singola corretta' : 'Singola sbagliata',
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
        final sumSingles = _wrongDoublePenaltySumSingles(match, pick);
        return MatchScoreBreakdown(
          matchId: match.id,
          basePoints: -sumSingles,
          correct: false,
          playedOdds: played,
          note: 'Doppia sbagliata: -somma quote singole',
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

    // Bonus solo se tutte le partite sono graded (nessun pending).
    final allGraded = matches.every((m) {
      final o = outcomesByMatchId[m.id];
      return o != null && !o.isPending;
    });

    final bonus = allGraded ? bonusForCorrectCount(correctCount) : 0;
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
