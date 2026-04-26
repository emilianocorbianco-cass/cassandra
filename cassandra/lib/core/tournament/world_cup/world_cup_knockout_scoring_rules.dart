import '../../../features/predictions/models/pick_option.dart';
import '../../../features/predictions/models/prediction_match.dart';
import '../../../features/scoring/models/match_outcome.dart';
import '../../../features/scoring/models/score_breakdown.dart';
import '../scoring_rules.dart';

/// World Cup knockout scoring:
/// - Correct at regulation: +3
/// - Correct at extra time: +6
/// - Correct at penalties: +10
/// Late submission = 0. No pick = 0.
class WorldCupKnockoutScoringRules implements ScoringRules {
  const WorldCupKnockoutScoringRules();

  /// Points per decidedIn tier. If decidedIn is null, defaults to regulation.
  static double pointsForDecidedIn(DecidedIn? decidedIn) {
    switch (decidedIn) {
      case DecidedIn.regulation:
      case null:
        return 3;
      case DecidedIn.extraTime:
        return 6;
      case DecidedIn.penalties:
        return 10;
    }
  }

  @override
  MatchScoreBreakdown scoreMatch({
    required PredictionMatch match,
    required PickOption pick,
    required MatchOutcome outcome,
    DateTime? submittedAt,
    DecidedIn? decidedIn,
  }) {
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

    if (pick.isNone) {
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: 0,
        correct: false,
        playedOdds: null,
        note: 'No pick',
      );
    }

    // For knockout, only singles are valid (1/X/2 at various stages).
    // The pick itself encodes the prediction — correctness is simple match.
    final correct =
        (pick == PickOption.home && outcome == MatchOutcome.home) ||
        (pick == PickOption.draw && outcome == MatchOutcome.draw) ||
        (pick == PickOption.away && outcome == MatchOutcome.away);

    if (!correct) {
      return MatchScoreBreakdown(
        matchId: match.id,
        basePoints: 0,
        correct: false,
        playedOdds: null,
        note: 'Wrong (0)',
      );
    }

    final points = pointsForDecidedIn(decidedIn);
    final label = switch (decidedIn) {
      DecidedIn.extraTime => 'Correct extra time (+6)',
      DecidedIn.penalties => 'Correct penalties (+10)',
      _ => 'Correct regulation (+3)',
    };

    return MatchScoreBreakdown(
      matchId: match.id,
      basePoints: points,
      correct: true,
      playedOdds: null,
      note: label,
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
}
