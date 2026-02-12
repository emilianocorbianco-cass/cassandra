import 'package:flutter/material.dart';

import '../../app/state/app_settings.dart';
import '../../app/state/app_state.dart';
import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../../app/widgets/demo_banner.dart';
import '../badges/season_badge_engine.dart';
import '../badges/widgets/avatar_with_badges.dart';
import '../group/mock_group_data.dart';
import '../group/models/group_member.dart';
import '../predictions/models/formatters.dart';
import '../scoring/models/score_breakdown.dart';
import 'matchday_leaderboard_page.dart';
import 'member_season_page.dart';
import 'mock_season_data.dart';
import 'models/matchday_data.dart';
import 'models/member_matchday_score.dart';
import 'models/season_leaderboard_entry.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';

class LeaderboardsPage extends StatefulWidget {
  const LeaderboardsPage({super.key});

  @override
  State<LeaderboardsPage> createState() => _LeaderboardsPageState();
}

enum _GeneralMode { points, average }

class _LeaderboardsPageState extends State<LeaderboardsPage> {
  int _segment = 0; // 0=generale, 1=giornate
  _GeneralMode _generalMode = _GeneralMode.points;

  // Firestore-based season data
  List<SeasonLeaderboardEntry>? _firestoreSeasonEntries;
  bool _firestoreLoading = false;

  bool _isEnglish(AppState app) {
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  String _t(AppState app, String it, String en) => _isEnglish(app) ? en : it;

  late final List<MatchdayData> _matchdays;

  @override
  void initState() {
    super.initState();
    _matchdays = mockSeasonMatchdays(startDay: 16, count: 5);
  }

  Future<void> _refreshSeasonFromFirestore() async {
    final app = CassandraScope.of(context);
    if (app.activeGroupId == null) return;

    setState(() => _firestoreLoading = true);
    try {
      final members = await app.fetchFirestoreGroupMembers();
      if (members.isEmpty) {
        setState(() => _firestoreLoading = false);
        return;
      }

      // Fetch all season picks for all members
      final entries = <SeasonLeaderboardEntry>[];
      for (final member in members) {
        final picksDocs = await app.fetchSeasonPicksForUser(member.id);
        if (picksDocs.isEmpty) {
          entries.add(
            SeasonLeaderboardEntry(
              member: member,
              matchdays: [],
              totalPoints: 0,
              averagePerMatchday: 0,
              averageOddsPlayed: null,
            ),
          );
          continue;
        }

        final perDay = <MemberMatchdayScore>[];
        double total = 0;

        for (final pd in picksDocs) {
          // Use cached score from picks doc if available
          if (pd.score != null) {
            total += pd.score!.total;
            // We don't have full breakdown, but we can build a summary entry
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
                  baseTotal: pd.score!.baseTotal,
                  bonusPoints: pd.score!.bonusPoints,
                  total: pd.score!.total,
                  correctCount: pd.score!.correctCount,
                  averageOddsPlayed: pd.score!.averageOddsPlayed,
                ),
              ),
            );
          }
        }

        final avg = perDay.isEmpty ? 0.0 : total / perDay.length;
        final oddsValues = perDay
            .map((d) => d.day.averageOddsPlayed)
            .whereType<double>()
            .toList();
        final avgOdds = oddsValues.isEmpty
            ? null
            : oddsValues.reduce((a, b) => a + b) / oddsValues.length;

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

      if (!mounted) return;
      setState(() {
        _firestoreSeasonEntries = entries;
        _firestoreLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _firestoreLoading = false);
    }
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
    final app = CassandraScope.of(context);

    app.ensureOutcomesHistoryLoaded();

    final cachedMatches = app.cachedPredictionMatches;
    final liveDayNumber = app.uiMatchdayNumber;
    final useLive =
        app.cachedPredictionMatchesAreReal &&
        cachedMatches != null &&
        cachedMatches.isNotEmpty;

    final liveOutcomes = <String, MatchOutcome>{};
    if (cachedMatches != null) {
      for (final m in cachedMatches) {
        liveOutcomes[m.id] =
            app.effectivePredictionOutcomesByMatchId[m.id] ??
            MatchOutcome.pending;
      }
    }

    MatchdayData effectiveMatchday(MatchdayData md) {
      final savedMatches = app.savedMatchesForMatchday(md.dayNumber);
      final matchesEffective = (savedMatches != null && savedMatches.isNotEmpty)
          ? savedMatches
          : md.matches;

      final outcomesEffective = app.hasSavedOutcomesForMatchday(md.dayNumber)
          ? app.outcomesForMatchday(md.dayNumber)
          : md.outcomesByMatchId;

      return MatchdayData(
        dayNumber: md.dayNumber,
        matches: matchesEffective,
        outcomesByMatchId: outcomesEffective,
      );
    }

    final base = <MatchdayData>[..._matchdays];
    final hasLiveInList = base.any((m) => m.dayNumber == liveDayNumber);

    if (useLive && !hasLiveInList) {
      base.add(
        MatchdayData(
          dayNumber: liveDayNumber,
          matches: cachedMatches,
          outcomesByMatchId: liveOutcomes,
        ),
      );
    }

    final matchdays = <MatchdayData>[];
    for (final md in base) {
      final isLive = useLive && md.dayNumber == liveDayNumber;

      if (isLive) {
        final savedMatches = app.savedMatchesForMatchday(liveDayNumber);
        final hasSavedMatches = savedMatches != null && savedMatches.isNotEmpty;
        final hasSavedOutcomes = app.hasSavedOutcomesForMatchday(liveDayNumber);

        // Preferisci sempre gli snapshot finalizzati (stabili).
        if (hasSavedMatches || hasSavedOutcomes) {
          matchdays.add(effectiveMatchday(md));
        } else {
          matchdays.add(
            MatchdayData(
              dayNumber: liveDayNumber,
              matches: cachedMatches,
              outcomesByMatchId: liveOutcomes,
            ),
          );
        }
      } else {
        matchdays.add(effectiveMatchday(md));
      }
    }

    final overrideMember = GroupMember(
      id: app.profile.id,
      displayName: app.profile.displayName,
      teamName: app.profile.teamName,
      avatarSeed: app.currentUserAvatarSeed,
      favoriteTeam: app.profile.favoriteTeam,
    );

    final members = mockGroupMembers(overrideMember: overrideMember);

    final entries = buildMockSeasonLeaderboardEntries(
      matchdays: matchdays,
      members: members,
    );

    // Override: l'utente corrente usa i pick reali persistiti (quando presenti).
    app.ensureCurrentUserPicksLoaded();
    final currentUserEntry = buildSeasonEntryForMemberFromPicks(
      member: overrideMember,
      matchdays: matchdays,
      picksByMatchId: app.currentUserPicksByMatchId,
    );
    final entriesWithCurrent = [
      for (final e in entries)
        if (e.member.id != overrideMember.id) e,
      currentUserEntry,
    ];

    app.ensureMemberPicksLoaded();
    final entriesWithOverrides = entriesWithCurrent.map((e) {
      final override = app.memberPicksByMemberId[e.member.id];
      if (override != null && override.isNotEmpty) {
        return buildSeasonEntryForMemberFromPicks(
          member: e.member,
          matchdays: matchdays,
          picksByMatchId: override,
        );
      }
      return e;
    }).toList();

    final sorted = _sortedGeneral(
      _firestoreSeasonEntries ?? entriesWithOverrides,
    );

    return Scaffold(
      appBar: AppBar(title: Text(_t(app, 'Classifiche', 'Standings'))),
      body: SafeArea(
        child: Column(
          children: [
            if (_firestoreSeasonEntries == null)
              DemoBanner(
                label: _t(
                  app,
                  'Dati di esempio \u2014 i dati reali appariranno dopo il primo invio',
                  'Sample data \u2014 real data will appear after first submission',
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Builder(
                  builder: (context) {
                    // Debug: dati/pronostici cache (coerente con Gruppo/Utente)
                    final app = CassandraScope.of(context);
                    final matches = app.cachedPredictionMatches;
                    final total = matches?.length ?? 0;
                    final outcomes = app.effectivePredictionOutcomesByMatchId;
                    final graded = (matches == null)
                        ? 0
                        : matches.where((m) {
                            final o = outcomes[m.id] ?? MatchOutcome.pending;
                            return !o.isPending;
                          }).length;

                    final kind = _firestoreLoading
                        ? _t(app, 'aggiornamento...', 'refreshing...')
                        : app.cachedPredictionMatchesAreReal
                        ? _t(app, 'reali (API)', 'real (API)')
                        : (total > 0 ? 'demo' : _t(app, 'vuota', 'empty'));

                    final updated = app.cachedPredictionMatchesUpdatedAt;
                    String fmt(DateTime dt) {
                      final dd = dt.day.toString().padLeft(2, '0');
                      final mm = dt.month.toString().padLeft(2, '0');
                      final hh = dt.hour.toString().padLeft(2, '0');
                      final mi = dt.minute.toString().padLeft(2, '0');
                      return '$dd/$mm $hh:$mi';
                    }

                    final updatedLabel = (updated == null)
                        ? _t(app, 'mai', 'never')
                        : fmt(updated);

                    final resultsLabel = (total == 0)
                        ? null
                        : (graded == total
                              ? '${_t(app, 'risultati', 'results')}: $graded/$total'
                              : '${_t(app, 'risultati', 'results')}: $graded/$total (${_t(app, 'parziale', 'partial')})');

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${_t(app, 'dati', 'data')}: $kind • ${_t(app, 'agg.', 'upd.')} $updatedLabel',
                            ),
                          ],
                        ),
                        if (resultsLabel != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            resultsLabel,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 0,
                        label: Text(_t(app, 'generale', 'overall')),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text(_t(app, 'giornate', 'matchdays')),
                      ),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (s) =>
                        setState(() => _segment = s.first),
                  ),
                  const SizedBox(height: 10),
                  if (_segment == 0)
                    SegmentedButton<_GeneralMode>(
                      segments: [
                        ButtonSegment(
                          value: _GeneralMode.points,
                          label: Text(_t(app, 'punti', 'points')),
                        ),
                        ButtonSegment(
                          value: _GeneralMode.average,
                          label: Text(_t(app, 'media', 'average')),
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
                      itemCount: matchdays.length,
                      itemBuilder: (context, i) {
                        final md = matchdays[matchdays.length - 1 - i];
                        final isLive = useLive && md.dayNumber == liveDayNumber;
                        final daysLabel = formatMatchdayDays(
                          md.matches.map((m) => m.kickoff),
                          english: _isEnglish(app),
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
                            title: Text(
                              isLive
                                  ? '${_t(app, 'Giornata', 'Matchday')} ${md.dayNumber} (LIVE)'
                                  : '${_t(app, 'Giornata', 'Matchday')} ${md.dayNumber}',
                            ),
                            subtitle: Text(() {
                              final total = md.matches.length;
                              final graded = md.matches.where((m) {
                                final o =
                                    md.outcomesByMatchId[m.id] ??
                                    MatchOutcome.pending;
                                return !o.isPending;
                              }).length;
                              final rl = (graded == total)
                                  ? '${_t(app, 'risultati', 'results')}: $graded/$total'
                                  : '${_t(app, 'risultati', 'results')}: $graded/$total (${_t(app, 'parziale', 'partial')})';
                              return '$daysLabel\n$rl';
                            }()),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MatchdayLeaderboardPage(
                                    matchday: md,
                                    seasonEntries: entriesWithOverrides,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    )
                  : RefreshIndicator(
                      onRefresh: _refreshSeasonFromFirestore,
                      child: ListView.builder(
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

                          final metricLabel =
                              _generalMode == _GeneralMode.points
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
            ),
          ],
        ),
      ),
    );
  }
}
