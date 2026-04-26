import '../../features/predictions/models/pick_option.dart';
import '../../features/predictions/models/prediction_match.dart';
import '../../features/scoring/models/match_outcome.dart';
import 'pick_strategy.dart';

/// Serie A pick strategy: 6 options (1/X/2 + double chance 1X/X2/12).
class SerieAPickStrategy implements PickStrategy {
  const SerieAPickStrategy();

  @override
  List<PickOption> availableOptions(PredictionMatch match) => const [
    PickOption.home,
    PickOption.draw,
    PickOption.away,
    PickOption.homeDraw,
    PickOption.drawAway,
    PickOption.homeAway,
  ];

  @override
  bool isCorrect(PickOption pick, MatchOutcome outcome) {
    if (outcome.isPending || outcome.isVoided) return false;
    if (pick.isSingle) {
      return (pick == PickOption.home && outcome == MatchOutcome.home) ||
          (pick == PickOption.draw && outcome == MatchOutcome.draw) ||
          (pick == PickOption.away && outcome == MatchOutcome.away);
    }
    if (pick.isDouble) {
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
    return false;
  }
}
