import '../badges/badge_engine.dart';
import '../badges/widgets/avatar_with_badges.dart';

import 'package:flutter/material.dart';

import '../../app/theme/cassandra_colors.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/mock_prediction_data.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';

import 'mock_group_data.dart';
import '../leaderboards/models/matchday_data.dart';
import '../profile/user_hub_page.dart';
import '../../app/state/cassandra_scope.dart';
import 'models/group_member.dart';

class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  static const int _matchdayNumber = 20;
  static const String _groupName = 'Cassandra Crew';

  late final List<PredictionMatch> _matches;
  late final Map<String, MatchOutcome> _outcomes;

  int _segment = 0; // 0 = classifica, 1 = giornate (placeholder)

  @override
  void initState() {
    super.initState();
    _matches = mockPredictionMatches();
    _outcomes = mockOutcomesForMatches(_matches);
  }

  String get _matchdayLabel {
    final days = formatMatchdayDaysItalian(_matches.map((m) => m.kickoff));
    return 'giornata $_matchdayNumber - $days';
  }

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final appState = CassandraScope.of(context);

    final dataLabel = appState.cachedPredictionMatchesAreReal
        ? 'dati: reali (API)'
        : 'dati: demo';
    final updatedLabel =
        (appState.cachedPredictionMatchesAreReal &&
            appState.cachedPredictionMatchesUpdatedAt != null)
        ? ' • agg. ${formatKickoff(appState.cachedPredictionMatchesUpdatedAt!)}'
        : '';

    final overrideMember = GroupMember(
      id: appState.profile.id,
      displayName: appState.profile.displayName,
      teamName: appState.profile.teamName,
      avatarSeed: appState.currentUserAvatarSeed,
      favoriteTeam: appState.profile.favoriteTeam,
    );

    final members = mockGroupMembers(overrideMember: overrideMember);

    final entries = buildSortedMockGroupLeaderboard(
      matches: _matches,
      outcomesByMatchId: _outcomes,
      members: members,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Il mio gruppo'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$dataLabel$updatedLabel',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _groupName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _matchdayLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('classifica')),
                      ButtonSegment(value: 1, label: Text('giornate')),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (s) =>
                        setState(() => _segment = s.first),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _segment == 1
                  ? const Center(child: Text('Storico giornate (in arrivo)'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        final badges =
                            CassandraBadgeEngine.badgesForGroupMatchday(
                              member: e.member,
                              rank: i + 1,
                              totalPlayers: entries.length,
                              matches: _matches,
                              picksByMatchId: e.picksByMatchId,
                              outcomesByMatchId: _outcomes,
                              day: e.day,
                            );

                        final pts = formatOdds(e.day.total);

                        return Card(
                          child: ListTile(
                            onTap: () {
                              final md = MatchdayData(
                                dayNumber: _matchdayNumber,
                                matches: _matches,
                                outcomesByMatchId: _outcomes,
                              );

                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => UserHubPage(
                                    member: e.member,
                                    matchday: md,
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
