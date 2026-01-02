import '../leaderboards/models/member_matchday_score.dart';
import '../leaderboards/models/season_leaderboard_entry.dart';
import 'badge_engine.dart';
import 'models/badge_counts.dart';

class CassandraTrophyEngine {
  static BadgeCounts countForMember({
    required String memberId,
    required List<SeasonLeaderboardEntry> seasonEntries,
  }) {
    final all = countForAll(seasonEntries: seasonEntries);
    return all[memberId] ?? BadgeCounts.empty();
  }

  static Map<String, BadgeCounts> countForAll({
    required List<SeasonLeaderboardEntry> seasonEntries,
  }) {
    final result = <String, BadgeCounts>{
      for (final e in seasonEntries) e.member.id: BadgeCounts.empty(),
    };

    // Giorni presenti (unione di tutte le giornate giocate dai vari utenti)
    final dayNumbers = <int>{};
    for (final e in seasonEntries) {
      for (final d in e.matchdays) {
        dayNumbers.add(d.matchday.dayNumber);
      }
    }

    final sortedDays = dayNumbers.toList()..sort();

    for (final dayNumber in sortedDays) {
      final participants =
          <({SeasonLeaderboardEntry entry, MemberMatchdayScore score})>[];

      for (final e in seasonEntries) {
        final dayScores = e.matchdays
            .where((d) => d.matchday.dayNumber == dayNumber)
            .toList();
        if (dayScores.isNotEmpty) {
          participants.add((entry: e, score: dayScores.first));
        }
      }

      if (participants.isEmpty) continue;

      // Ranking della giornata: totale desc, poi quota media desc, poi teamName
      participants.sort((a, b) {
        final t = b.score.day.total.compareTo(a.score.day.total);
        if (t != 0) return t;

        final aOdds = a.score.day.averageOddsPlayed ?? -1;
        final bOdds = b.score.day.averageOddsPlayed ?? -1;
        final oddsCmp = bOdds.compareTo(aOdds);
        if (oddsCmp != 0) return oddsCmp;

        return a.entry.member.teamName.compareTo(b.entry.member.teamName);
      });

      // Matchday (uguale per tutti i partecipanti)
      final md = participants.first.score.matchday;

      for (int i = 0; i < participants.length; i++) {
        final p = participants[i];

        final badges = CassandraBadgeEngine.badgesForGroupMatchday(
          member: p.entry.member,
          rank: i + 1,
          totalPlayers: participants.length,
          matches: md.matches,
          picksByMatchId: p.score.picksByMatchId,
          outcomesByMatchId: md.outcomesByMatchId,
          day: p.score.day,
        );

        final counts = result[p.entry.member.id] ?? BadgeCounts.empty();
        for (final b in badges) {
          counts.add(b);
        }
        result[p.entry.member.id] = counts;
      }
    }

    return result;
  }
}
