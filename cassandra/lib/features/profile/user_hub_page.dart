import 'package:flutter/foundation.dart';
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
import 'package:cassandra/features/scoring/models/match_outcome.dart';

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
  late List<SeasonLeaderboardEntry> _seasonEntries;
  late SeasonLeaderboardEntry _seasonEntry;
  late BadgeCounts _trophies;

  bool _initialized = false;
  int? _lastDemoSeed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = CassandraScope.of(context);
    final seed = appState.demoSeed;
    if (_initialized && _lastDemoSeed == seed) return;
    _initialized = true;
    _lastDemoSeed = seed;

    // Coerente con Classifiche/Stats: stagione demo 16–20
    final matchdays = mockSeasonMatchdays(
      startDay: 16,
      count: 5,
      demoSeed: seed,
    );

    // Leggiamo il profilo (nome squadra + squadra del cuore) dai Settings

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

  Future<void> _resetHistory(dynamic app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset storico'),
        content: const Text(
          'Cancella i pick salvati e i risultati salvati (outcomes).\n\n'
          'Utile per testare da zero.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    app.clearAllHistory();
    app.clearCachedPredictionMatches();
    app.setUiMatchdayNumber(null);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Storico resettato')));
  }

  Future<void> _regenDemo(dynamic app) async {
    await app.bumpDemoSeed();

    final matchdays = mockSeasonMatchdays(
      startDay: 16,
      count: 5,
      demoSeed: app.demoSeed,
    );

    final demo = matchdays.last; // coerente con stagione demo 16–20 (day 20)

    app.setUiMatchdayNumber(20);
    app.setCachedPredictionMatches(
      demo.matches,
      isReal: false,
      updatedAt: DateTime.now(),
    );
    app.setCachedPredictionOutcomesByMatchId(demo.outcomesByMatchId);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Demo caricata (seed: ${app.demoSeed})')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalMatches = widget.matchday.matches.length;
    final gradedCount = widget.matchday.matches.where((m) {
      final o = widget.matchday.outcomesByMatchId[m.id] ?? MatchOutcome.pending;
      return !o.isPending;
    }).length;

    final resultsLabel = (gradedCount == totalMatches)
        ? 'risultati: $gradedCount/$totalMatches'
        : 'risultati: $gradedCount/$totalMatches (parziale)';

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
    final isMe = widget.member.id == app.profile.id;
    final seed = app.demoSeed;

    return MediaQuery(
      data: MediaQueryData.fromView(View.of(context)),
      child: DefaultTabController(
        length: 3,
        initialIndex: initial,
        child: Scaffold(
          appBar: AppBar(
            primary: true,
            centerTitle: true,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  widget.member.teamName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.member.displayName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(kTextTabBarHeight + 112),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$dataLabel$updatedLabel\n$resultsLabel',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          if (kDebugMode)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'demo seed: $seed',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                OutlinedButton(
                                  onPressed: isMe
                                      ? () async => _resetHistory(app)
                                      : null,
                                  child: const Text('Reset'),
                                ),
                                OutlinedButton(
                                  onPressed: () async => _regenDemo(app),
                                  child: const Text('Demo'),
                                ),
                              ],
                            ),
                        ],
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
      ),
    );
  }
}
