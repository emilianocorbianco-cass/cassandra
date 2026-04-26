import '../../../features/predictions/models/pick_option.dart';
import '../../../features/predictions/models/prediction_match.dart';
import '../../../features/scoring/models/match_outcome.dart';
import '../../../features/scoring/models/score_breakdown.dart';
import '../scoring_rules.dart';

/// World Cup group stage scoring: fixed +3 for correct, 0 for wrong.
/// No odds, no bonus. Late submission = 0 (not -2 like Serie A).
class WorldCupGroupScoringRules implements ScoringRules {
  const WorldCupGroupScoringRules();

  static const double _correctPoints = 3;

  @override
  MatchScoreBreakdown scoreMatch({
    required PredictionMatch match,
    required PickOption pick,
    required MatchOutcome outcome,
    DateTime? submittedAt,
  }) {
    // Late submission → 0 points (tournament policy).
    if (submittedAt != null && match.kickoff.isBefore(submittedAt)) {
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: 0,
        correct: false,
        playedOdds: null,
        note: 'Late submission',
      );
    }

    if (outcome.isPending) {
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: 0,
        correct: false,
        playedOdds: null,
        note: 'Outcome pending',
      );
    }

    if (outcome.isVoided) {
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: 0,
        correct: false,
        playedOdds: null,
        note: 'Match voided',
      );
    }

    // No pick → 0 (no auto-assign in tournaments).
    if (pick.isNone) {
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: 0,
        correct: false,
        playedOdds: null,
        note: 'No pick',
      );
    }

    final correct = _isCorrect(pick, outcome);
    return MatchScoreBreakdown(
      matchId: match.id,
      basePoints: correct ? _correctPoints : 0,
      correct: correct,
      playedOdds: null,
      note: correct ? 'Correct (+3)' : 'Wrong (0)',
    );
  }

  @override
  DayScoreBreakdown scoreRound({
    required List<PredictionMatch> matches,
    required Map<String, PickOption> picksByMatchId,
    required Map<String, MatchOutcome> outcomesByMatchId,
    DateTime? submittedAt,
  }) {
    final breakdowns = <MatchScoreBreakdown>[];
    for (final m in matches) {
      final pick = picksByMatchId[m.id] ?? PickOption.none;
      final outcome = outcomesByMatchId[m.id] ?? MatchOutcome.pending;
      breakdowns.add(scoreMatch(
        match: m,
        pick: pick,
        outcome: outcome,
        submittedAt: submittedAt,
      ));
    }

    final baseTotal =
        breakdowns.fold<double>(0, (sum, b) => sum + b.basePoints);
    final correctCount = breakdowns.where((b) => b.correct).length;

    return DayScoreBreakdown(
      matchBreakdowns: breakdowns,
      baseTotal: baseTotal,
      bonusPoints: 0,
      oddsBonusPoints: 0,
      correctBonusPoints: 0,
      total: baseTotal,
      correctCount: correctCount,
      averageOddsPlayed: null,
    );
  }

  static bool _isCorrect(PickOption pick, MatchOutcome outcome) {
    return (pick == PickOption.home && outcome == MatchOutcome.home) ||
        (pick == PickOption.draw && outcome == MatchOutcome.draw) ||
        (pick == PickOption.away && outcome == MatchOutcome.away);
  }
}
