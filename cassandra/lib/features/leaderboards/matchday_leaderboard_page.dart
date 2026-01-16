import 'package:flutter/material.dart';

import '../../app/theme/cassandra_colors.dart';
import '../predictions/models/formatters.dart';
import 'models/matchday_data.dart';
import 'models/season_leaderboard_entry.dart';
import 'models/member_matchday_score.dart';
import '../badges/badge_engine.dart';
import '../badges/widgets/avatar_with_badges.dart';
import '../profile/user_hub_page.dart';

class MatchdayLeaderboardPage extends StatelessWidget {
  final MatchdayData matchday;
  final List<SeasonLeaderboardEntry> seasonEntries;

  const MatchdayLeaderboardPage({
    super.key,
    required this.matchday,
    required this.seasonEntries,
  });

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  MemberMatchdayScore? _findDay(SeasonLeaderboardEntry e) {
    for (final d in e.matchdays) {
      if (d.matchday.dayNumber == matchday.dayNumber) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final rows =
        <({SeasonLeaderboardEntry entry, MemberMatchdayScore score})>[];

    for (final e in seasonEntries) {
      final d = _findDay(e);
      if (d != null) {
        rows.add((entry: e, score: d));
      }
    }

    rows.sort((a, b) {
      final t = b.score.day.total.compareTo(a.score.day.total);
      if (t != 0) return t;

      final aAvg = a.score.day.averageOddsPlayed ?? -1;
      final bAvg = b.score.day.averageOddsPlayed ?? -1;
      final avgCmp = bAvg.compareTo(aAvg);
      if (avgCmp != 0) return avgCmp;

      return a.entry.member.teamName.compareTo(b.entry.member.teamName);
    });

    final daysLabel = formatMatchdayDaysItalian(
      matchday.matches.map((m) => m.kickoff),
    );

    return Scaffold(
      appBar: AppBar(title: Text('Giornata ${matchday.dayNumber}')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(daysLabel, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Text(
                    'Giocatori: ${rows.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final e = rows[i].entry;
                  final s = rows[i].score;
                  final badges = CassandraBadgeEngine.badgesForGroupMatchday(
                    member: e.member,
                    rank: i + 1,
                    totalPlayers: rows.length,
                    matches: matchday.matches,
                    picksByMatchId: s.picksByMatchId,
                    outcomesByMatchId: matchday.outcomesByMatchId,
                    day: s.day,
                  );

                  final pts = s.day.total;
                  final ptsLabel = formatOdds(pts);
                  final sign = pts >= 0 ? '+' : '';

                  return Card(
                    child: ListTile(
                      onTap: () {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => UserHubPage(
                              member: e.member,
                              matchday: matchday,
                              picksByMatchId: s.picksByMatchId,
                              initialTabIndex: 0,
                            ),
                          ),
                        );
                      },
                      leading: SizedBox(
                        width: 64,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 22,
                              child: Text(
                                '${i + 1}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: CassandraColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            AvatarWithBadges(
                              radius: 18,
                              backgroundColor: _avatarColorFromSeed(
                                e.member.avatarSeed,
                              ),
                              text: e.member.displayName
                                  .substring(0, 1)
                                  .toUpperCase(),
                              badges: badges,
                            ),
                          ],
                        ),
                      ),
                      title: Text(e.member.displayName),
                      subtitle: Text(e.member.teamName),
                      trailing: Text(
                        '$sign$ptsLabel',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
