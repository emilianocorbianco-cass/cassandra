import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/features/group/models/group_member.dart';
import 'package:cassandra/features/leaderboards/models/matchday_data.dart';
import 'package:cassandra/features/leaderboards/models/member_matchday_score.dart';
import 'package:cassandra/features/leaderboards/models/season_leaderboard_entry.dart';
import 'package:cassandra/features/scoring/models/score_breakdown.dart';
import 'package:cassandra/features/stats/stats_engine.dart';

void main() {
  MatchScoreBreakdown b(double? playedOdds) => MatchScoreBreakdown(
    matchId: 'm',
    basePoints: 0,
    correct: false,
    playedOdds: playedOdds,
    note: '',
  );

  DayScoreBreakdown day({
    required double total,
    required int bonus,
    required int correctCount,
  }) {
    // 10 partite “giocate” con quota 2.00 (solo per far calcolare quota media)
    final mb = List.generate(10, (_) => b(2.0));

    return DayScoreBreakdown(
      matchBreakdowns: mb,
      baseTotal: total - bonus,
      bonusPoints: bonus,
      total: total,
      correctCount: correctCount,
      averageOddsPlayed: 2.0,
    );
  }

  test('compute stats from matchdays', () {
    const member = GroupMember(
      id: 'u1',
      displayName: 'Test',
      teamName: 'FC Test',
      avatarSeed: 1,
    );

    const md1 = MatchdayData(dayNumber: 1, matches: [], outcomesByMatchId: {});
    const md2 = MatchdayData(dayNumber: 2, matches: [], outcomesByMatchId: {});

    final d1 = MemberMatchdayScore(
      matchday: md1,
      picksByMatchId: const {},
      day: day(total: 6.0, bonus: 1, correctCount: 7),
    );
    final d2 = MemberMatchdayScore(
      matchday: md2,
      picksByMatchId: const {},
      day: day(total: -2.0, bonus: -5, correctCount: 3),
    );

    final entry = SeasonLeaderboardEntry(
      member: member,
      matchdays: [d1, d2],
      totalPoints: 0, // non usato direttamente dallo stats engine
      averagePerMatchday: 0,
      averageOddsPlayed: null,
    );

    final s = CassandraStatsEngine.computeForEntry(entry);

    expect(s.daysPlayed, 2);
    expect(s.totalPoints, closeTo(4.0, 0.0001));
    expect(s.averagePointsPerDay, closeTo(2.0, 0.0001));
    expect(s.totalCorrect, 10);
    expect(s.totalMatches, 20);
    expect(s.correctRate, closeTo(0.5, 0.0001));
    expect(s.perfectWeeks, 0);
    expect(s.totalBonus, -4);
    expect(s.averageBonusPerDay, closeTo(-2.0, 0.0001));
    expect(s.averageOddsPlayed, closeTo(2.0, 0.0001));
    expect(s.bestDayNumber, 1);
    expect(s.worstDayNumber, 2);
  });
}
