import '../leaderboards/models/season_leaderboard_entry.dart';
import 'models/player_season_stats.dart';

class CassandraStatsEngine {
  static PlayerSeasonStats computeForEntry(SeasonLeaderboardEntry entry) {
    final days = entry.matchdays;
    final daysPlayed = days.length;

    if (daysPlayed == 0) {
      return PlayerSeasonStats(
        member: entry.member,
        daysPlayed: 0,
        totalPoints: 0.0,
        averagePointsPerDay: 0.0,
        totalCorrect: 0,
        totalMatches: 0,
        correctRate: 0.0,
        perfectWeeks: 0,
        totalBonus: 0,
        averageBonusPerDay: 0.0,
        averageOddsPlayed: null,
        bestDayNumber: null,
        bestDayPoints: null,
        worstDayNumber: null,
        worstDayPoints: null,
      );
    }

    final totalPoints = days.fold<double>(0, (sum, d) => sum + d.day.total);
    final avgPoints = totalPoints / daysPlayed;

    final totalCorrect = days.fold<int>(
      0,
      (sum, d) => sum + d.day.correctCount,
    );
    final totalMatches = days.fold<int>(
      0,
      (sum, d) => sum + d.day.matchBreakdowns.length,
    );
    final double correctRate = totalMatches == 0
        ? 0.0
        : (totalCorrect / totalMatches);

    final perfectWeeks = days.where((d) => d.day.correctCount == 10).length;

    final totalBonus = days.fold<int>(0, (sum, d) => sum + d.day.bonusPoints);
    final avgBonus = totalBonus / daysPlayed;

    // Quota media “stagionale” calcolata sulle quote giocate in tutte le partite
    final oddsValues = days
        .expand((d) => d.day.matchBreakdowns)
        .map((b) => b.playedOdds)
        .whereType<double>()
        .toList();

    final avgOdds = oddsValues.isEmpty
        ? null
        : oddsValues.reduce((a, b) => a + b) / oddsValues.length;

    // Best / worst day
    final best = days.reduce((a, b) => a.day.total >= b.day.total ? a : b);
    final worst = days.reduce((a, b) => a.day.total <= b.day.total ? a : b);

    return PlayerSeasonStats(
      member: entry.member,
      daysPlayed: daysPlayed,
      totalPoints: totalPoints,
      averagePointsPerDay: avgPoints,
      totalCorrect: totalCorrect,
      totalMatches: totalMatches,
      correctRate: correctRate,
      perfectWeeks: perfectWeeks,
      totalBonus: totalBonus,
      averageBonusPerDay: avgBonus,
      averageOddsPlayed: avgOdds,
      bestDayNumber: best.matchday.dayNumber,
      bestDayPoints: best.day.total,
      worstDayNumber: worst.matchday.dayNumber,
      worstDayPoints: worst.day.total,
    );
  }

  static List<PlayerSeasonStats> computeForEntries(
    List<SeasonLeaderboardEntry> entries,
  ) {
    return entries.map(computeForEntry).toList();
  }
}
