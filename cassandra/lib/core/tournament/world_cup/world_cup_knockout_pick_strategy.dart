import '../../../features/predictions/models/pick_option.dart';
import '../../../features/predictions/models/prediction_match.dart';
import '../../../features/scoring/models/match_outcome.dart';
import '../pick_strategy.dart';

/// World Cup knockout: 8 pick options covering regulation, extra time,
/// and penalties outcomes.
///
/// - homeReg / drawReg / awayReg — result at 90 minutes
/// - homeEt / drawEt / awayEt — result at 120 minutes
/// - homePen / awayPen — winner decided on penalties
class WorldCupKnockoutPickStrategy implements PickStrategy {
  const WorldCupKnockoutPickStrategy();

  @override
  List<PickOption> availableOptions(PredictionMatch match) => const [
    PickOption.homeReg,
    PickOption.drawReg,
    PickOption.awayReg,
    PickOption.homeEt,
    PickOption.drawEt,
    PickOption.awayEt,
    PickOption.homePen,
    PickOption.awayPen,
  ];

  @override
  bool isCorrect(PickOption pick, MatchOutcome outcome) {
    if (outcome.isPending || outcome.isVoided) return false;

    // For knockout, correctness requires matching both the outcome AND
    // the decidedIn tier. Since MatchOutcome alone doesn't carry decidedIn,
    // this basic check only validates the outcome direction.
    // Full decidedIn validation happens in the scoring rules.
    switch (pick) {
      case PickOption.homeReg:
      case PickOption.homeEt:
      case PickOption.homePen:
        return outcome == MatchOutcome.home;
      case PickOption.drawReg:
      case PickOption.drawEt:
        return outcome == MatchOutcome.draw;
      case PickOption.awayReg:
      case PickOption.awayEt:
      case PickOption.awayPen:
        return outcome == MatchOutcome.away;
      default:
        return false;
    }
  }
}
