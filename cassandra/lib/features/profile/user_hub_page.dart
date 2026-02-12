import 'package:flutter/material.dart';

import '../../app/state/app_settings.dart';
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

  bool _isEnglish() {
    final app = CassandraScope.of(context);
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  String _t(String it, String en) => _isEnglish() ? en : it;

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

  @override
  Widget build(BuildContext context) {
    final totalMatches = widget.matchday.matches.length;
    final gradedCount = widget.matchday.matches.where((m) {
      final o = widget.matchday.outcomesByMatchId[m.id] ?? MatchOutcome.pending;
      return !o.isPending;
    }).length;

    final resultsLabel = (gradedCount == totalMatches)
        ? '${_t('risultati', 'results')}: $gradedCount/$totalMatches'
        : '${_t('risultati', 'results')}: $gradedCount/$totalMatches (${_t('parziale', 'partial')})';

    final app = CassandraScope.of(context);
    final dataLabel = app.cachedPredictionMatchesAreReal
        ? _t('dati: reali (API)', 'data: real (API)')
        : _t('dati: demo', 'data: demo');
    final updatedLabel =
        (app.cachedPredictionMatchesAreReal &&
            app.cachedPredictionMatchesUpdatedAt != null)
        ? ' \u2022 ${_t('agg.', 'upd.')} ${formatKickoff(app.cachedPredictionMatchesUpdatedAt!)}'
        : '';

    final initial = widget.initialTabIndex.clamp(0, 2);

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
                  TabBar(
                    tabs: [
                      Tab(text: _t('Pronostici', 'Predictions')),
                      const Tab(text: 'Stats'),
                      Tab(text: _t('Trofei', 'Trophies')),
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
