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
import '../predictions/models/prediction_match.dart';

import 'widgets/user_picks_view.dart';
import 'widgets/user_stats_view.dart';
import 'widgets/user_trophies_view.dart';
import 'package:cassandra/features/predictions/models/formatters.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';
import '../dev/dev_debug_page.dart';

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

    final demo = matchdays.last;

    app.setUiMatchdayNumber(demo.dayNumber);
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

  Future<void> _devAddPostponedMatch(
    dynamic app, {
    required bool within48,
  }) async {
    final matchdays = mockSeasonMatchdays(
      startDay: 16,
      count: 5,
      demoSeed: app.demoSeed,
    );
    final demo = matchdays.last;

    // Origini stabili da calendario demo (kickoff previsto)
    final originById = <String, DateTime>{
      for (final m in demo.matches) m.id: m.kickoff,
    };

    // Usa la cache demo se già attiva, altrimenti la demo pulita
    final cached = app.cachedPredictionMatches;
    final usingDemoCache =
        cached != null && !app.cachedPredictionMatchesAreReal;
    final baseMatches = usingDemoCache ? cached : demo.matches;

    // Registra le origini in AppState (serve per originKickoffFor)
    final dyn = app as dynamic;
    try {
      dyn.registerOriginKickoffs(demo.matches);
    } catch (_) {
      try {
        dyn.registerOriginKickoff(demo.matches);
      } catch (_) {}
    }

    // Prendi il prossimo match "non ancora toccato" (kickoff == origin)
    PredictionMatch? target;
    DateTime? targetOrigin;

    for (final m in baseMatches) {
      final origin = originById[m.id] ?? m.kickoff;
      final untouched = m.kickoff.isAtSameMomentAs(origin);
      if (!untouched) continue;

      if (target == null || origin.isBefore(targetOrigin!)) {
        target = m;
        targetOrigin = origin;
      }
    }

    if (target == null || targetOrigin == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessun altro match da modificare')),
      );
      return;
    }

    final o = targetOrigin;

    final shift = within48
        ? const Duration(hours: 24)
        : const Duration(hours: 72);
    final newKickoff = o.add(shift);

    final updatedMatches = baseMatches.map((m) {
      if (m.id != target!.id) return m;
      return PredictionMatch(
        id: m.id,
        homeTeam: m.homeTeam,
        awayTeam: m.awayTeam,
        kickoff: newKickoff,
        odds: m.odds,
      );
    }).toList()..sort((a, b) => a.kickoff.compareTo(b.kickoff));

    // Outcomes: mantieni quelli già presenti (cache o demo)
    final cachedOutcomes = app.cachedPredictionOutcomesByMatchId;
    final outcomes = (cachedOutcomes is Map && cachedOutcomes.isNotEmpty)
        ? cachedOutcomes
        : demo.outcomesByMatchId;

    app.setUiMatchdayNumber(demo.dayNumber);
    app.setCachedPredictionMatches(
      updatedMatches,
      isReal: false,
      updatedAt: DateTime.now(),
    );
    app.setCachedPredictionOutcomesByMatchId(outcomes);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          within48
              ? 'Aggiunto 1 recupero <48h'
              : 'Aggiunto 1 partita nulla >48h',
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _applyDemoScenario(
    dynamic app, {
    required int hoursAgo,
    required int voidCount,
  }) async {
    final matchdays = mockSeasonMatchdays(
      startDay: 16,
      count: 5,
      demoSeed: app.demoSeed,
    );
    final demo = matchdays.last;

    final now = DateTime.now();
    final shiftedKickoff = now.subtract(Duration(hours: hoursAgo));

    final sorted = [...demo.matches]
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    final target = sorted.take(voidCount).toList();
    final targetIds = {for (final m in target) m.id};

    final matchesOverride = demo.matches.map((m) {
      if (!targetIds.contains(m.id)) return m;
      return PredictionMatch(
        id: m.id,
        homeTeam: m.homeTeam,
        awayTeam: m.awayTeam,
        kickoff: shiftedKickoff,
        odds: m.odds,
      );
    }).toList();

    final outcomesOverride = Map<String, MatchOutcome>.from(
      demo.outcomesByMatchId,
    );
    for (final id in targetIds) {
      outcomesOverride[id] = MatchOutcome.pending;
    }

    app.setUiMatchdayNumber(demo.dayNumber);
    app.setCachedPredictionMatches(
      matchesOverride,
      isReal: false,
      updatedAt: DateTime.now(),
    );
    app.setCachedPredictionOutcomesByMatchId(outcomesOverride);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Scenario DEMO: $voidCount match pending con kickoff ${hoursAgo}h fa',
        ),
      ),
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
            actions: [
              if (kDebugMode)
                IconButton(
                  tooltip: 'Debug',
                  icon: const Icon(Icons.bug_report_outlined),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DevDebugPage(
                          onResetHistory: () => _resetHistory(app),
                          onRegenDemo: () => _regenDemo(app),
                          onAddRecovered: () async {
                            _devAddPostponedMatch(app, within48: true);
                          },
                          onAddVoid: () async {
                            _devAddPostponedMatch(app, within48: false);
                          },
                        ),
                      ),
                    );
                  },
                ),
            ],

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
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        'demo seed: $seed',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
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

                                      OutlinedButton(
                                        onPressed: () => _devAddPostponedMatch(
                                          app,
                                          within48: true,
                                        ),
                                        child: const Text('+ recuperata <48h'),
                                      ),
                                      OutlinedButton(
                                        onPressed: () => _devAddPostponedMatch(
                                          app,
                                          within48: false,
                                        ),
                                        child: const Text('+ nulla >48h'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
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
