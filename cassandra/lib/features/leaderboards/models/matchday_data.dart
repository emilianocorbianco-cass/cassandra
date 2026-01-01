import '../../predictions/models/prediction_match.dart';
import '../../scoring/models/match_outcome.dart';

class MatchdayData {
  final int dayNumber;
  final List<PredictionMatch> matches;
  final Map<String, MatchOutcome> outcomesByMatchId;

  const MatchdayData({
    required this.dayNumber,
    required this.matches,
    required this.outcomesByMatchId,
  });
}
