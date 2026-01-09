import 'package:flutter/material.dart';

import '../../app/theme/cassandra_colors.dart';
import '../badges/badge_engine.dart';
import '../badges/widgets/avatar_with_badges.dart';
import '../leaderboards/models/matchday_data.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/pick_option.dart';
import '../profile/user_hub_page.dart';
import '../scoring/models/match_outcome.dart';

import 'mock_group_data.dart';
import 'models/group_member.dart';

class GroupMatchdayPage extends StatelessWidget {
  final String groupName;
  final MatchdayData matchday;
  final List<GroupMember> members;

  /// Override opzionale: memberId -> (matchId -> pick)
  final Map<String, Map<String, PickOption>>? picksOverridesByMemberId;

  const GroupMatchdayPage({
    super.key,
    required this.groupName,
    required this.matchday,
    required this.members,
    this.picksOverridesByMemberId,
  });

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final total = matchday.matches.length;
    final graded = matchday.matches.where((m) {
      final o = matchday.outcomesByMatchId[m.id] ?? MatchOutcome.pending;
      return !o.isPending;
    }).length;

    final resultsLabel = (graded == total)
        ? 'risultati: $graded/$total'
        : 'risultati: $graded/$total (parziale)';

    final daysLabel = formatMatchdayDaysItalian(
      matchday.matches.map((m) => m.kickoff),
    );

    final entries = buildSortedMockGroupLeaderboard(
      matches: matchday.matches,
      outcomesByMatchId: matchday.outcomesByMatchId,
      members: members,
      overridePicksByMemberId: picksOverridesByMemberId,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('$groupName • Giornata ${matchday.dayNumber}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(daysLabel, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    resultsLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final e = entries[i];

                  final badges = CassandraBadgeEngine.badgesForGroupMatchday(
                    member: e.member,
                    rank: i + 1,
                    totalPlayers: entries.length,
                    matches: matchday.matches,
                    picksByMatchId: e.picksByMatchId,
                    outcomesByMatchId: matchday.outcomesByMatchId,
                    day: e.day,
                  );

                  final pts = formatOdds(e.day.total);

                  return Card(
                    child: ListTile(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => UserHubPage(
                              member: e.member,
                              matchday: matchday,
                              picksByMatchId: e.picksByMatchId,
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
                        pts,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: e.day.total >= 0
                              ? CassandraColors.primary
                              : CassandraColors.slate,
                        ),
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
