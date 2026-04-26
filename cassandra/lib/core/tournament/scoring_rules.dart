import '../../features/predictions/models/pick_option.dart';
import '../../features/predictions/models/prediction_match.dart';
import '../../features/scoring/models/match_outcome.dart';
import '../../features/scoring/models/score_breakdown.dart';

/// Abstract scoring contract for any tournament format.
///
/// Serie A: implemented by [SerieAScoringRules] which delegates
/// to the existing [CassandraScoringEngine] static methods.
abstract class ScoringRules {
  MatchScoreBreakdown scoreMatch({
    required PredictionMatch match,
    required PickOption pick,
    required MatchOutcome outcome,
    DateTime? submittedAt,
  });

  DayScoreBreakdown scoreRound({
    required List<PredictionMatch> matches,
    required Map<String, PickOption> picksByMatchId,
    required Map<String, MatchOutcome> outcomesByMatchId,
    DateTime? submittedAt,
  });
}
