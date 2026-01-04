import 'package:flutter/material.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../badges/season_badge_engine.dart';
import '../badges/widgets/avatar_with_badges.dart';
import '../group/mock_group_data.dart';
import '../group/models/group_member.dart';
import '../predictions/models/formatters.dart';
import 'matchday_leaderboard_page.dart';
import 'member_season_page.dart';
import 'mock_season_data.dart';
import 'models/matchday_data.dart';
import 'models/season_leaderboard_entry.dart';

class LeaderboardsPage extends StatefulWidget {
  const LeaderboardsPage({super.key});

  @override
  State<LeaderboardsPage> createState() => _LeaderboardsPageState();
}

enum _GeneralMode { points, average }

class _LeaderboardsPageState extends State<LeaderboardsPage> {
  int _segment = 0; // 0=generale, 1=giornate
  _GeneralMode _generalMode = _GeneralMode.points;

  late final List<MatchdayData> _matchdays;

  @override
  void initState() {
    super.initState();
    _matchdays = mockSeasonMatchdays(startDay: 16, count: 5);
  }

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  List<SeasonLeaderboardEntry> _sortedGeneral(
    List<SeasonLeaderboardEntry> input,
  ) {
    final list = List<SeasonLeaderboardEntry>.of(input);

    list.sort((a, b) {
      if (_generalMode == _GeneralMode.points) {
        final t = b.totalPoints.compareTo(a.totalPoints);
        if (t != 0) return t;

        final ao = a.averageOddsPlayed ?? -1;
        final bo = b.averageOddsPlayed ?? -1;
        final o = bo.compareTo(ao);
        if (o != 0) return o;

        return a.member.teamName.compareTo(b.member.teamName);
      } else {
        final t = b.averagePerMatchday.compareTo(a.averagePerMatchday);
        if (t != 0) return t;

        final p = b.totalPoints.compareTo(a.totalPoints);
        if (p != 0) return p;

        return a.member.teamName.compareTo(b.member.teamName);
      }
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final appState = CassandraScope.of(context);

    final overrideMember = GroupMember(
      id: appState.profile.id,
      displayName: appState.profile.displayName,
      teamName: appState.profile.teamName,
      avatarSeed: appState.currentUserAvatarSeed,
      favoriteTeam: appState.profile.favoriteTeam,
    );

    final members = mockGroupMembers(overrideMember: overrideMember);

    final entries = buildMockSeasonLeaderboardEntries(
      matchdays: _matchdays,
      members: members,
    );

    final sorted = _sortedGeneral(entries);

    return Scaffold(
      appBar: AppBar(title: const Text('Classifiche')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('generale')),
                      ButtonSegment(value: 1, label: Text('giornate')),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (s) =>
                        setState(() => _segment = s.first),
                  ),
                  const SizedBox(height: 10),
                  if (_segment == 0)
                    SegmentedButton<_GeneralMode>(
                      segments: const [
                        ButtonSegment(
                          value: _GeneralMode.points,
                          label: Text('punti'),
                        ),
                        ButtonSegment(
                          value: _GeneralMode.average,
                          label: Text('media'),
                        ),
                      ],
                      selected: {_generalMode},
                      onSelectionChanged: (s) =>
                          setState(() => _generalMode = s.first),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _segment == 1
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      itemCount: _matchdays.length,
                      itemBuilder: (context, i) {
                        final md = _matchdays[_matchdays.length - 1 - i];
                        final daysLabel = formatMatchdayDaysItalian(
                          md.matches.map((m) => m.kickoff),
                        );

                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: CassandraColors.primary
                                  .withAlpha(31),
                              child: Text(
                                '${md.dayNumber}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: CassandraColors.primary,
                                ),
                              ),
                            ),
                            title: Text('Giornata ${md.dayNumber}'),
                            subtitle: Text(daysLabel),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MatchdayLeaderboardPage(
                                    matchday: md,
                                    seasonEntries: entries,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      itemCount: sorted.length,
                      itemBuilder: (context, i) {
                        final e = sorted[i];

                        final badges =
                            CassandraSeasonBadgeEngine.badgesForSeason(
                              entry: e,
                              rank: i + 1,
                              totalPlayers: sorted.length,
                            );

                        final metricLabel = _generalMode == _GeneralMode.points
                            ? formatOdds(e.totalPoints)
                            : formatOdds(e.averagePerMatchday);

                        return Card(
                          child: ListTile(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MemberSeasonPage(entry: e),
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
                              metricLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
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
