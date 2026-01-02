import '../../group/models/group_member.dart';

class PlayerSeasonStats {
  final GroupMember member;

  final int daysPlayed;

  final double totalPoints;
  final double averagePointsPerDay;

  final int totalCorrect;
  final int totalMatches;
  final double correctRate; // 0..1

  final int perfectWeeks;

  final int totalBonus;
  final double averageBonusPerDay;

  final double? averageOddsPlayed;

  final int? bestDayNumber;
  final double? bestDayPoints;

  final int? worstDayNumber;
  final double? worstDayPoints;

  const PlayerSeasonStats({
    required this.member,
    required this.daysPlayed,
    required this.totalPoints,
    required this.averagePointsPerDay,
    required this.totalCorrect,
    required this.totalMatches,
    required this.correctRate,
    required this.perfectWeeks,
    required this.totalBonus,
    required this.averageBonusPerDay,
    required this.averageOddsPlayed,
    required this.bestDayNumber,
    required this.bestDayPoints,
    required this.worstDayNumber,
    required this.worstDayPoints,
  });
}
