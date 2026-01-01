import '../../predictions/models/pick_option.dart';
import '../../scoring/models/score_breakdown.dart';
import 'matchday_data.dart';

class MemberMatchdayScore {
  final MatchdayData matchday;
  final Map<String, PickOption> picksByMatchId;
  final DayScoreBreakdown day;

  const MemberMatchdayScore({
    required this.matchday,
    required this.picksByMatchId,
    required this.day,
  });
}
