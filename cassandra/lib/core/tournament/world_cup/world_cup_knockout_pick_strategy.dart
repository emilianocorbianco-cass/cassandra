import '../../../features/predictions/models/pick_option.dart';
import '../../../features/predictions/models/prediction_match.dart';
import '../../../features/scoring/models/match_outcome.dart';
import '../pick_strategy.dart';

/// World Cup knockout: 1/X/2 at 90 minutes.
///
/// The full 8-option system (1/X/2 at 90', 1/X/2 at 120', 1/2 at penalties)
/// requires extending PickOption with knockout-specific values.
/// For now, picks are 1/X/2 and scoring tiers come from MatchResult.decidedIn.
class WorldCupKnockoutPickStrategy implements PickStrategy {
  const WorldCupKnockoutPickStrategy();

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
