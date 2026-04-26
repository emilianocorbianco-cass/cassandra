import '../../features/predictions/models/pick_option.dart';
import '../../features/predictions/models/prediction_match.dart';
import '../../features/scoring/models/match_outcome.dart';

/// Defines which picks are available for a match and how to check correctness.
///
/// Serie A: 6 options (1/X/2 + double chance).
/// World Cup groups: 3 options (1/X/2 only).
/// Knockout: 8 options (regulation/extra-time/penalties variants).
abstract class PickStrategy {
  /// Available pick options for a given match.
  List<PickOption> availableOptions(PredictionMatch match);

  /// Whether the [pick] is correct given the [outcome].
  bool isCorrect(PickOption pick, MatchOutcome outcome);
}
