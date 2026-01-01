import '../../group/models/group_member.dart';
import 'member_matchday_score.dart';

class SeasonLeaderboardEntry {
  final GroupMember member;
  final List<MemberMatchdayScore> matchdays;

  final double totalPoints;
  final double averagePerMatchday;
  final double? averageOddsPlayed;

  const SeasonLeaderboardEntry({
    required this.member,
    required this.matchdays,
    required this.totalPoints,
    required this.averagePerMatchday,
    required this.averageOddsPlayed,
  });

  int get daysPlayed => matchdays.length;
}
