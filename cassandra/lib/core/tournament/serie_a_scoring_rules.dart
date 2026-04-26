import '../../features/predictions/models/pick_option.dart';
import '../../features/predictions/models/prediction_match.dart';
import '../../features/scoring/models/match_outcome.dart';
import '../../features/scoring/models/score_breakdown.dart';
import '../../features/scoring/scoring_engine.dart';
import 'scoring_rules.dart';

/// Serie A scoring: delegates entirely to [CassandraScoringEngine].
///
/// This is a thin adapter — the existing static class is the source of truth.
/// No logic is duplicated or rewritten.
class SerieAScoringRules implements ScoringRules {
  const SerieAScoringRules();

  @override
  MatchScoreBreakdown scoreMatch({
    required PredictionMatch match,
    required PickOption pick,
    required MatchOutcome outcome,
    DateTime? submittedAt,
  }) => CassandraScoringEngine.scoreMatch(
    match: match,
    pick: pick,
    outcome: outcome,
    submittedAt: submittedAt,
  );

  @override
  DayScoreBreakdown scoreRound({
    required List<PredictionMatch> matches,
    required Map<String, PickOption> picksByMatchId,
    required Map<String, MatchOutcome> outcomesByMatchId,
    DateTime? submittedAt,
  }) => CassandraScoringEngine.computeDayScore(
    matches: matches,
    picksByMatchId: picksByMatchId,
    outcomesByMatchId: outcomesByMatchId,
    submittedAt: submittedAt,
  );
}
