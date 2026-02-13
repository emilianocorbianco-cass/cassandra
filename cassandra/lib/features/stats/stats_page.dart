import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../app/state/app_state.dart';
import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../group/models/group_member.dart';
import '../leaderboards/models/matchday_data.dart';
import '../leaderboards/models/member_matchday_score.dart';
import '../leaderboards/models/season_leaderboard_entry.dart';
import '../predictions/models/formatters.dart';
import '../scoring/models/score_breakdown.dart';
import 'models/player_season_stats.dart';
import 'stats_engine.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

enum GroupMetric { avgPoints, totalPoints, correctRate, perfectWeeks }

class _StatsPageState extends State<StatsPage> {
  int _segment = 0; // 0 = personali, 1 = gruppo
  GroupMetric _metric = GroupMetric.avgPoints;

  List<SeasonLeaderboardEntry> _entries = const [];
  List<PlayerSeasonStats> _stats = const [];

  String? _selectedMemberId;
  bool _loading = false;
  bool _loadRequested = false;
  String? _loadedGroupId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLoaded();
  }

  bool _canUseFirestoreStats(AppState app) =>
      app.firestoreService != null &&
      app.isAuthenticated &&
      app.activeGroupId != null;

  void _ensureLoaded() {
    final app = CassandraScope.of(context);
    final groupId = app.activeGroupId;
    final shouldReload = !_loadRequested || _loadedGroupId != groupId;
    if (!shouldReload) return;
    _loadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadStats();
    });
  }

  GroupMember _currentUserMember(AppState app) {
    return GroupMember(
      id: app.profile.id,
      displayName: app.profile.displayName,
      teamName: app.profile.teamName,
      avatarSeed: app.currentUserAvatarSeed,
      favoriteTeam: app.profile.favoriteTeam,
    );
  }

  SeasonLeaderboardEntry _emptyEntryFor(GroupMember member) {
    return SeasonLeaderboardEntry(
      member: member,
      matchdays: const [],
      totalPoints: 0,
      averagePerMatchday: 0,
      averageOddsPlayed: null,
    );
  }

  Future<List<SeasonLeaderboardEntry>> _loadEntriesFromFirestore(
    AppState app,
  ) async {
    final members = await app.fetchFirestoreGroupMembers();
    if (members.isEmpty) return const [];

    final entries = <SeasonLeaderboardEntry>[];
    for (final member in members) {
      final picksDocs = await app.fetchSeasonPicksForUser(member.id);
      picksDocs.sort((a, b) => a.dayNumber.compareTo(b.dayNumber));

      final perDay = <MemberMatchdayScore>[];
      for (final pd in picksDocs) {
        final score = pd.score;
        final day = DayScoreBreakdown(
          matchBreakdowns: const [],
          baseTotal: score?.baseTotal ?? 0,
          bonusPoints: score?.bonusPoints ?? 0,
          total: score?.total ?? 0,
          correctCount: score?.correctCount ?? 0,
          averageOddsPlayed: score?.averageOddsPlayed,
        );

        perDay.add(
          MemberMatchdayScore(
            matchday: MatchdayData(
              dayNumber: pd.dayNumber,
              matches: const [],
              outcomesByMatchId: const {},
            ),
            picksByMatchId: pd.picksByMatchId,
            day: day,
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

      entries.add(
        SeasonLeaderboardEntry(
          member: member,
          matchdays: perDay,
          totalPoints: total,
          averagePerMatchday: avg,
          averageOddsPlayed: avgOdds,
        ),
      );
    }

    return entries;
  }

  Future<void> _loadStats() async {
    final app = CassandraScope.of(context);
    setState(() => _loading = true);

    try {
      final currentUser = _currentUserMember(app);
      List<SeasonLeaderboardEntry> entries;
      if (_canUseFirestoreStats(app)) {
        entries = await _loadEntriesFromFirestore(app);
      } else {
        entries = [_emptyEntryFor(currentUser)];
      }

      if (entries.isEmpty) {
        entries = [_emptyEntryFor(currentUser)];
      } else if (!entries.any((e) => e.member.id == currentUser.id)) {
        entries = [...entries, _emptyEntryFor(currentUser)];
      }

      final stats = CassandraStatsEngine.computeForEntries(entries);
      final selectedId =
          (_selectedMemberId != null &&
              entries.any((e) => e.member.id == _selectedMemberId))
          ? _selectedMemberId
          : entries.first.member.id;

      if (!mounted) return;
      setState(() {
        _entries = entries;
        _stats = stats;
        _selectedMemberId = selectedId;
        _loading = false;
        _loadedGroupId = app.activeGroupId;
      });
    } catch (_) {
      if (!mounted) return;
      final fallback = _emptyEntryFor(_currentUserMember(app));
      setState(() {
        _entries = [fallback];
        _stats = CassandraStatsEngine.computeForEntries(_entries);
        _selectedMemberId = fallback.member.id;
        _loading = false;
        _loadedGroupId = app.activeGroupId;
      });
    }
  }

  SeasonLeaderboardEntry? get _selectedEntry {
    if (_entries.isEmpty || _selectedMemberId == null) return null;
    for (final entry in _entries) {
      if (entry.member.id == _selectedMemberId) return entry;
    }
    return _entries.first;
  }

  PlayerSeasonStats? get _selectedStats {
    final entry = _selectedEntry;
    if (entry == null) return null;
    return CassandraStatsEngine.computeForEntry(entry);
  }

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  String _formatPercent(double v) {
    return '${(v * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  List<PlayerSeasonStats> _sortedGroup() {
    final list = List<PlayerSeasonStats>.of(_stats);

    int cmp(PlayerSeasonStats a, PlayerSeasonStats b) {
      switch (_metric) {
        case GroupMetric.avgPoints:
          final t = b.averagePointsPerDay.compareTo(a.averagePointsPerDay);
          if (t != 0) return t;
          return b.totalPoints.compareTo(a.totalPoints);

        case GroupMetric.totalPoints:
          final t = b.totalPoints.compareTo(a.totalPoints);
          if (t != 0) return t;
          return b.averagePointsPerDay.compareTo(a.averagePointsPerDay);

        case GroupMetric.correctRate:
          final t = b.correctRate.compareTo(a.correctRate);
          if (t != 0) return t;
          return b.totalCorrect.compareTo(a.totalCorrect);

        case GroupMetric.perfectWeeks:
          final t = b.perfectWeeks.compareTo(a.perfectWeeks);
          if (t != 0) return t;
          return b.averagePointsPerDay.compareTo(a.averagePointsPerDay);
      }
    }

    list.sort(cmp);
    return list;
  }

  Widget _miniStat({required String label, required String value}) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: CassandraColors.slate,
                ),
              ),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoaded();
    final l10n = AppLocalizations.of(context)!;
    final s = _selectedStats;

    final totalLabel = s == null ? '0,00' : formatOdds(s.totalPoints);
    final avgLabel = s == null ? '0,00' : formatOdds(s.averagePointsPerDay);
    final oddsLabel = (s == null || s.averageOddsPlayed == null)
        ? '-'
        : formatOdds(s.averageOddsPlayed!);

    final bestLabel =
        (s == null || s.bestDayNumber == null || s.bestDayPoints == null)
        ? '-'
        : 'G${s.bestDayNumber}: ${formatOdds(s.bestDayPoints!)}';

    final worstLabel =
        (s == null || s.worstDayNumber == null || s.worstDayPoints == null)
        ? '-'
        : 'G${s.worstDayNumber}: ${formatOdds(s.worstDayPoints!)}';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 0,
                        label: Text(l10n.statsSegmentPersonal),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text(l10n.statsSegmentGroup),
                      ),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (s) =>
                        setState(() => _segment = s.first),
                  ),
                  const SizedBox(height: 10),
                  if (_segment == 0 && _entries.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedMemberId,
                            isExpanded: true,
                            items: _entries.map((e) {
                              return DropdownMenuItem(
                                value: e.member.id,
                                child: Text(e.member.uiName),
                              );
                            }).toList(),
                            onChanged: (v) =>
                                setState(() => _selectedMemberId = v),
                          ),
                        ),
                      ),
                    ),
                  if (_segment == 1) ...[
                    SegmentedButton<GroupMetric>(
                      segments: [
                        ButtonSegment(
                          value: GroupMetric.avgPoints,
                          label: Text(l10n.statsMetricAverage),
                        ),
                        ButtonSegment(
                          value: GroupMetric.totalPoints,
                          label: Text(l10n.statsMetricTotal),
                        ),
                        ButtonSegment(
                          value: GroupMetric.correctRate,
                          label: Text(l10n.statsMetricPercentCorrect),
                        ),
                        ButtonSegment(
                          value: GroupMetric.perfectWeeks,
                          label: const Text('10/10'),
                        ),
                      ],
                      selected: {_metric},
                      onSelectionChanged: (s) =>
                          setState(() => _metric = s.first),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading && _entries.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _entries.isEmpty
                  ? Center(child: Text(l10n.commonNoDataAvailable))
                  : _segment == 0
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      children: [
                        Row(
                          children: [
                            _miniStat(
                              label: l10n.statsTotal,
                              value: totalLabel,
                            ),
                            _miniStat(
                              label: l10n.statsAvgMatchday,
                              value: avgLabel,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            _miniStat(
                              label: l10n.statsMatchdaysPlayed,
                              value: '${s?.daysPlayed ?? 0}',
                            ),
                            _miniStat(
                              label: l10n.statsAvgOdds,
                              value: oddsLabel,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            _miniStat(
                              label: l10n.statsTotalCorrect,
                              value:
                                  '${s?.totalCorrect ?? 0}/${s?.totalMatches ?? 0}',
                            ),
                            _miniStat(
                              label: l10n.statsMetricPercentCorrect,
                              value: _formatPercent(s?.correctRate ?? 0),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            _miniStat(
                              label: l10n.statsMetricPerfectWeeks,
                              value: '${s?.perfectWeeks ?? 0}',
                            ),
                            _miniStat(
                              label: l10n.statsAvgBonus,
                              value: formatOdds(s?.averageBonusPerDay ?? 0),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  l10n.statsHighlights,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(l10n.statsBestMatchday(bestLabel)),
                                Text(l10n.statsWorstMatchday(worstLabel)),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.statsTotalBonus('${s?.totalBonus ?? 0}'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      itemCount: _sortedGroup().length,
                      itemBuilder: (context, i) {
                        final p = _sortedGroup()[i];

                        String valueLabel;
                        switch (_metric) {
                          case GroupMetric.avgPoints:
                            valueLabel = formatOdds(p.averagePointsPerDay);
                            break;
                          case GroupMetric.totalPoints:
                            valueLabel = formatOdds(p.totalPoints);
                            break;
                          case GroupMetric.correctRate:
                            valueLabel = _formatPercent(p.correctRate);
                            break;
                          case GroupMetric.perfectWeeks:
                            valueLabel = '${p.perfectWeeks}';
                            break;
                        }

                        return Card(
                          child: ListTile(
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
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: _avatarColorFromSeed(
                                      p.member.avatarSeed,
                                    ),
                                    child: Text(
                                      p.member.avatarInitial,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            title: Text(p.member.uiName),
                            subtitle: Text(
                              '${l10n.statsMatchdays}: ${p.daysPlayed} • '
                              '${l10n.statsCorrect}: ${p.totalCorrect}/${p.totalMatches}',
                            ),
                            trailing: Text(
                              valueLabel,
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
