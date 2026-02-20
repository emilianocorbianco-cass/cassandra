import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../app/state/cassandra_scope.dart';
import '../badges/models/badge_counts.dart';
import '../badges/trophy_engine.dart';
import '../group/models/group_member.dart';
import '../leaderboards/models/member_matchday_score.dart';
import '../leaderboards/models/matchday_data.dart';
import '../leaderboards/models/season_leaderboard_entry.dart';
import '../predictions/models/pick_option.dart';
import 'widgets/user_picks_view.dart';
import 'widgets/user_stats_view.dart';
import 'widgets/user_trophies_view.dart';
import 'package:cassandra/features/predictions/models/formatters.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';
import '../scoring/models/score_breakdown.dart';

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

  bool _loading = false;
  String? _loadedKey;

  @override
  void initState() {
    super.initState();
    _seasonEntries = const [];
    _seasonEntry = SeasonLeaderboardEntry(
      member: widget.member,
      matchdays: const [],
      totalPoints: 0,
      averagePerMatchday: 0,
      averageOddsPlayed: null,
    );
    _trophies = CassandraTrophyEngine.countForMember(
      memberId: widget.member.id,
      seasonEntries: _seasonEntries,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = CassandraScope.of(context);
    final key = '${app.activeGroupId ?? 'none'}:${widget.member.id}';
    if (_loadedKey == key) return;
    _loadedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadSeasonData();
    });
  }

  Future<void> _loadSeasonData() async {
    final app = CassandraScope.of(context);
    final canUseFirestore =
        app.firestoreService != null &&
        app.isAuthenticated &&
        app.activeGroupId != null;

    setState(() => _loading = true);
    try {
      List<SeasonLeaderboardEntry> entries;
      if (canUseFirestore) {
        final members = await app.fetchFirestoreGroupMembers();
        final picksByMember = await app.fetchSeasonPicksByMemberForActiveGroup(
          members.map((m) => m.id).toList(growable: false),
        );
        final loaded = <SeasonLeaderboardEntry>[];
        for (final member in members) {
          final picksDocs = picksByMember[member.id] ?? const [];

          final perDay = <MemberMatchdayScore>[];
          for (final pd in picksDocs) {
            final score = pd.score;
            perDay.add(
              MemberMatchdayScore(
                matchday: MatchdayData(
                  dayNumber: pd.dayNumber,
                  matches: const [],
                  outcomesByMatchId: const {},
                ),
                picksByMatchId: pd.picksByMatchId,
                day: DayScoreBreakdown(
                  matchBreakdowns: const [],
                  baseTotal: score?.baseTotal ?? 0,
                  bonusPoints: score?.bonusPoints ?? 0,
                  total: score?.total ?? 0,
                  correctCount: score?.correctCount ?? 0,
                  averageOddsPlayed: score?.averageOddsPlayed,
                ),
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

          loaded.add(
            SeasonLeaderboardEntry(
              member: member,
              matchdays: perDay,
              totalPoints: total,
              averagePerMatchday: avg,
              averageOddsPlayed: avgOdds,
            ),
          );
        }
        entries = loaded;
      } else {
        entries = const [];
      }

      if (!entries.any((e) => e.member.id == widget.member.id)) {
        entries = [
          ...entries,
          SeasonLeaderboardEntry(
            member: widget.member,
            matchdays: const [],
            totalPoints: 0,
            averagePerMatchday: 0,
            averageOddsPlayed: null,
          ),
        ];
      }

      final selected = entries.firstWhere(
        (e) => e.member.id == widget.member.id,
        orElse: () => SeasonLeaderboardEntry(
          member: widget.member,
          matchdays: const [],
          totalPoints: 0,
          averagePerMatchday: 0,
          averageOddsPlayed: null,
        ),
      );

      if (!mounted) return;
      setState(() {
        _seasonEntries = entries;
        _seasonEntry = selected;
        _trophies = CassandraTrophyEngine.countForMember(
          memberId: widget.member.id,
          seasonEntries: entries,
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _seasonEntries = const [];
        _seasonEntry = SeasonLeaderboardEntry(
          member: widget.member,
          matchdays: const [],
          totalPoints: 0,
          averagePerMatchday: 0,
          averageOddsPlayed: null,
        );
        _trophies = CassandraTrophyEngine.countForMember(
          memberId: widget.member.id,
          seasonEntries: _seasonEntries,
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final totalMatches = widget.matchday.matches.length;
    final gradedCount = widget.matchday.matches.where((m) {
      final o = widget.matchday.outcomesByMatchId[m.id] ?? MatchOutcome.pending;
      return !o.isPending;
    }).length;

    final resultsLabel = (gradedCount == totalMatches)
        ? l10n.groupResultsLabel(gradedCount, totalMatches)
        : l10n.groupResultsLabelPartial(gradedCount, totalMatches);

    final app = CassandraScope.of(context);
    final dataLabel = app.cachedPredictionMatchesAreReal
        ? l10n.groupDataRealApi
        : l10n.groupDataDemo;
    final updatedLabel =
        (app.cachedPredictionMatchesAreReal &&
            app.cachedPredictionMatchesUpdatedAt != null)
        ? ' \u2022 ${l10n.shortUpdated} ${formatKickoff(app.cachedPredictionMatchesUpdatedAt!)}'
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
                  widget.member.uiName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(kTextTabBarHeight + 112),
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(text: l10n.tabPredictions),
                      Tab(text: l10n.tabStats),
                      Tab(text: l10n.tabTrophies),
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
          bottomNavigationBar: _loading
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
      ),
    );
  }
}
