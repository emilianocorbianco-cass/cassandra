import 'package:flutter/foundation.dart';

import '../../../app/state/app_state.dart';
import '../../group/models/group_member.dart';
import '../../leaderboards/models/matchday_data.dart';
import '../../leaderboards/models/member_matchday_score.dart';
import '../../leaderboards/models/season_leaderboard_entry.dart';
import '../../scoring/models/score_breakdown.dart';
import '../../scoring/scoring_engine.dart';

class StatsEntriesLoader {
  const StatsEntriesLoader._();

  static GroupMember currentUserMember(AppState app) {
    return GroupMember(
      id: app.profile.id,
      displayName: app.profile.displayName,
      teamName: app.profile.teamName,
      avatarSeed: app.currentUserAvatarSeed,
      favoriteTeam: app.profile.favoriteTeam,
    );
  }

  static SeasonLeaderboardEntry emptyEntryFor(GroupMember member) {
    return SeasonLeaderboardEntry(
      member: member,
      matchdays: const [],
      totalPoints: 0,
      averagePerMatchday: 0,
      averageOddsPlayed: null,
    );
  }

  static Future<List<SeasonLeaderboardEntry>> loadEntriesFromFirestore(
    AppState app,
  ) async {
    final members = await app.fetchFirestoreGroupMembers();
    if (members.isEmpty) return const [];

    final memberUids = members.map((m) => m.id).toList(growable: false);
    final picksByMember = await app.fetchSeasonPicksByMemberForActiveGroup(
      memberUids,
    );

    final daysNeedingFallbackScore = <int>{};
    for (final picksDocs in picksByMember.values) {
      for (final pd in picksDocs) {
        if (pd.score == null && pd.dayNumber > 0) {
          daysNeedingFallbackScore.add(pd.dayNumber);
        }
      }
    }

    final matchdayByDay = <int, MatchdayData>{};
    final fs = app.firestoreService;
    if (fs != null && daysNeedingFallbackScore.isNotEmpty) {
      for (final day in daysNeedingFallbackScore) {
        try {
          final md = await fs.getMatchdayData(
            seasonKey: app.currentSeasonKey,
            dayNumber: day,
          );
          if (md == null || md.matches.isEmpty) continue;
          matchdayByDay[day] = MatchdayData(
            dayNumber: day,
            matches: md.matches,
            outcomesByMatchId: md.outcomesByMatchId,
          );
        } catch (error) {
          if (kDebugMode) {
            debugPrint('[stats-loader] day $day failed: $error');
          }
        }
      }
    }

    final entries = <SeasonLeaderboardEntry>[];
    for (final member in members) {
      final picksDocs = picksByMember[member.id] ?? const [];
      final perDay = <MemberMatchdayScore>[];

      for (final pd in picksDocs) {
        final score = pd.score;
        late final DayScoreBreakdown day;

        if (score != null) {
          day = DayScoreBreakdown(
            matchBreakdowns: const [],
            baseTotal: score.baseTotal,
            bonusPoints: score.bonusPoints,
            oddsBonusPoints: score.oddsBonusPoints,
            correctBonusPoints: score.correctBonusPoints,
            total: score.total,
            correctCount: score.correctCount,
            averageOddsPlayed: score.averageOddsPlayed,
          );
        } else {
          final md = matchdayByDay[pd.dayNumber];
          if (md == null || md.matches.isEmpty) {
            day = const DayScoreBreakdown(
              matchBreakdowns: [],
              baseTotal: 0,
              bonusPoints: 0,
              oddsBonusPoints: 0,
              correctBonusPoints: 0,
              total: 0,
              correctCount: 0,
              averageOddsPlayed: null,
            );
          } else {
            day = CassandraScoringEngine.computeDayScore(
              matches: md.matches,
              picksByMatchId: pd.picksByMatchId,
              outcomesByMatchId: md.outcomesByMatchId,
            );
          }
        }

        perDay.add(
          MemberMatchdayScore(
            matchday: MatchdayData(
              dayNumber: pd.dayNumber,
              matches: const [],
              outcomesByMatchId: const {},
            ),
            picksByMatchId: pd.picksByMatchId,
            day: day,
          ),
        );
      }

      final total = perDay.fold<double>(0, (sum, d) => sum + d.day.total);
      final avg = perDay.isEmpty ? 0.0 : total / perDay.length;
      final avgOddsValues = perDay
          .map((d) => d.day.averageOddsPlayed)
          .whereType<double>()
          .toList();
      final avgOdds = avgOddsValues.isEmpty
          ? null
          : avgOddsValues.reduce((a, b) => a + b) / avgOddsValues.length;

      entries.add(
        SeasonLeaderboardEntry(
          member: member,
          matchdays: perDay,
          totalPoints: total,
          averagePerMatchday: avg,
          averageOddsPlayed: avgOdds,
        ),
      );
    }

    return entries;
  }
}
