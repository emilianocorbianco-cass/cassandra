import '../../predictions/models/pick_option.dart';
import '../../scoring/models/score_breakdown.dart';
import 'group_member.dart';

class GeneralLeaderboardEntry {
  GeneralLeaderboardEntry({
    required this.member,
    required this.currentDay,
    required this.currentDayPicksByMatchId,
    required this.totalPoints,
    required this.averageOddsPlayed,
  });

  final GroupMember member;
  final DayScoreBreakdown currentDay;
  final Map<String, PickOption> currentDayPicksByMatchId;
  final double totalPoints;
  final double? averageOddsPlayed;
}
