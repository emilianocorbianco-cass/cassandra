import '../../../features/predictions/models/pick_option.dart';
import '../../../features/predictions/models/prediction_match.dart';
import '../../../features/scoring/models/match_outcome.dart';
import '../pick_strategy.dart';

/// World Cup group stage: 1/X/2 only (no double chance).
class WorldCupGroupPickStrategy implements PickStrategy {
  const WorldCupGroupPickStrategy();

  @override
  List<PickOption> availableOptions(PredictionMatch match) => const [
    PickOption.home,
    PickOption.draw,
    PickOption.away,
  ];

  @override
  bool isCorrect(PickOption pick, MatchOutcome outcome) {
    if (outcome.isPending || outcome.isVoided) return false;
    return (pick == PickOption.home && outcome == MatchOutcome.home) ||
        (pick == PickOption.draw && outcome == MatchOutcome.draw) ||
        (pick == PickOption.away && outcome == MatchOutcome.away);
  }
}
