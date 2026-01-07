import 'package:flutter/material.dart';

import '../../app/state/cassandra_scope.dart';
import '../badges/models/badge_counts.dart';
import '../badges/trophy_engine.dart';
import '../group/mock_group_data.dart';
import '../group/models/group_member.dart';
import '../leaderboards/mock_season_data.dart';
import '../leaderboards/models/matchday_data.dart';
import '../leaderboards/models/season_leaderboard_entry.dart';
import '../predictions/models/pick_option.dart';

import 'widgets/user_picks_view.dart';
import 'widgets/user_stats_view.dart';
import 'widgets/user_trophies_view.dart';
import 'package:cassandra/features/predictions/models/formatters.dart';

class UserHubPage extends StatefulWidget {
  final GroupMember member;

  /// Giornata “corrente” da mostrare nel tab Pronostici.
  final MatchdayData matchday;

  /// Pronostici del membro per quella giornata.
  final Map<String, PickOption> picksByMatchId;

  /// 0=Pronostici, 1=Stats, 2=Trofei
  final int initialTabIndex;

  const UserHubPage({
    super.key,
    required this.member,
    required this.matchday,
    required this.picksByMatchId,
    this.initialTabIndex = 0,
  });

  @override
  State<UserHubPage> createState() => _UserHubPageState();
}

class _UserHubPageState extends State<UserHubPage> {
  late final List<SeasonLeaderboardEntry> _seasonEntries;
  late final SeasonLeaderboardEntry _seasonEntry;
  late final BadgeCounts _trophies;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    // Coerente con Classifiche/Stats: stagione demo 16–20
    final matchdays = mockSeasonMatchdays(startDay: 16, count: 5);

    // Leggiamo il profilo (nome squadra + squadra del cuore) dai Settings
    final appState = CassandraScope.of(context);

    final overrideMember = GroupMember(
      id: appState.profile.id,
      displayName: appState.profile.displayName,
      teamName: appState.profile.teamName,
      avatarSeed: appState.currentUserAvatarSeed,
      favoriteTeam: appState.profile.favoriteTeam,
    );

    final members = mockGroupMembers(overrideMember: overrideMember);

    _seasonEntries = buildMockSeasonLeaderboardEntries(
      matchdays: matchdays,
      members: members,
    );

    _seasonEntry = _seasonEntries.firstWhere(
      (e) => e.member.id == widget.member.id,
      orElse: () => SeasonLeaderboardEntry(
        member: widget.member,
        matchdays: const [],
        totalPoints: 0,
        averagePerMatchday: 0,
        averageOddsPlayed: null,
      ),
    );

    _trophies = CassandraTrophyEngine.countForMember(
      memberId: widget.member.id,
      seasonEntries: _seasonEntries,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final dataLabel = app.cachedPredictionMatchesAreReal
        ? 'dati: reali (API)'
        : 'dati: demo';
    final updatedLabel =
        (app.cachedPredictionMatchesAreReal &&
            app.cachedPredictionMatchesUpdatedAt != null)
        ? ' • agg. ${formatKickoff(app.cachedPredictionMatchesUpdatedAt!)}'
        : '';

    final initial = widget.initialTabIndex.clamp(0, 2);

    return DefaultTabController(
      length: 3,
      initialIndex: initial,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.member.teamName),
              Text(
                widget.member.displayName,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(kTextTabBarHeight + 24),
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Pronostici'),
                    Tab(text: 'Stats'),
                    Tab(text: 'Trofei'),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$dataLabel$updatedLabel',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            UserPicksView(
              member: widget.member,
              matchday: widget.matchday,
              picksByMatchId: widget.picksByMatchId,
            ),
            UserStatsView(entry: _seasonEntry, trophies: _trophies),
            UserTrophiesView(member: widget.member, trophies: _trophies),
          ],
        ),
      ),
    );
  }
}
