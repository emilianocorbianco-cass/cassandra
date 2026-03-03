import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/state/app_state.dart';
import '../../app/widgets/team_name.dart';
import '../../app/theme/cassandra_colors.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/prediction_match.dart';
import '../predictions/widgets/serie_a_standings_table.dart';
import '../scoring/models/match_outcome.dart';
import '../../app/state/cassandra_scope.dart';
import '../../services/firestore/models/matchday_document.dart';
import 'live_match_details_page.dart';

class SerieAPage extends StatefulWidget {
  const SerieAPage({super.key});

  @override
  State<SerieAPage> createState() => _SerieAPageState();
}

class _SerieAPageState extends State<SerieAPage> {
  int _segment = 0; // 0 = risultati, 1 = classifica Serie A
  bool _didLoad = false;

  _SerieAData? _data;
  StreamSubscription<MatchdayDocument?>? _matchdaySub;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _bindStream();
  }

  @override
  void dispose() {
    _matchdaySub?.cancel();
    super.dispose();
  }

  void _bindStream() {
    _matchdaySub?.cancel();
    _matchdaySub = null;

    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final fs = app.firestoreService;

    // Show cache immediately if available — avoids empty flash on revisit.
    if (app.cachedPredictionMatches != null &&
        app.cachedPredictionMatches!.isNotEmpty &&
        app.cachedPredictionMatchesAreReal) {
      _data = _SerieAData(
        matches: app.cachedPredictionMatches!,
        outcomesByMatchId: {
          for (final m in app.cachedPredictionMatches!)
            if (app.effectivePredictionOutcomesByMatchId[m.id] != null)
              m.id: app.effectivePredictionOutcomesByMatchId[m.id]!,
        },
        fromBackend: true,
      );
    }

    if (fs == null) return;
    if (!app.isAuthenticated) {
      _data = _SerieAData(
        matches: const [],
        outcomesByMatchId: const {},
        fromBackend: false,
        errorMessage: l10n.serieASignInRequired,
      );
      return;
    }

    // Best-effort standings fetch (non-blocking).
    fs
        .getSeasonStandings(seasonKey: app.currentSeasonKey)
        .then((standings) {
          if (standings.isNotEmpty && mounted) {
            app.setCachedSeasonStandings(standings);
          }
        })
        .catchError((Object _) {});

    // Live stream for matchday fixtures + outcomes.
    _matchdaySub = fs
        .streamMatchdayData(
          seasonKey: app.currentSeasonKey,
          dayNumber: app.cassandraMatchdayCursor,
        )
        .listen(
          (doc) {
            if (!mounted) return;
            if (doc != null && doc.matches.isNotEmpty) {
              app.setCachedPredictionMatches(
                doc.matches,
                isReal: true,
                updatedAt: doc.updatedAt,
              );
              app.setCachedPredictionOutcomesByMatchId(doc.outcomesByMatchId);
            }
            setState(() {
              _data = doc == null || doc.matches.isEmpty
                  ? const _SerieAData(
                      matches: [],
                      outcomesByMatchId: {},
                      fromBackend: false,
                    )
                  : _SerieAData(
                      matches: doc.matches,
                      outcomesByMatchId: doc.outcomesByMatchId,
                      fromBackend: true,
                    );
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            final errApp = CassandraScope.of(context);
            final errL10n = AppLocalizations.of(context)!;
            setState(() {
              _data = _SerieAData(
                matches: const [],
                outcomesByMatchId: const {},
                fromBackend: false,
                errorMessage: _friendlyBackendError(error, errL10n, errApp),
              );
            });
          },
        );
  }

  String _friendlyBackendError(
    Object error,
    AppLocalizations l10n,
    AppState app,
  ) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return app.isAuthenticated
          ? l10n.backendPermissionDenied
          : l10n.serieASignInRequired;
    }
    final lower = error.toString().toLowerCase();
    if (lower.contains('permission-denied') ||
        lower.contains('permission denied')) {
      return app.isAuthenticated
          ? l10n.backendPermissionDenied
          : l10n.serieASignInRequired;
    }
    return error.toString();
  }

  Future<void> _reload() {
    if (!mounted) return Future.value();
    _bindStream();
    return Future.value();
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;

    final demoMatches = app.cachedPredictionMatches;
    final demoActive =
        demoMatches != null && !app.cachedPredictionMatchesAreReal;
    final hasLiveCache =
        demoMatches != null &&
        demoMatches.isNotEmpty &&
        app.cachedPredictionMatchesAreReal;
    final effectiveData = hasLiveCache
        ? _SerieAData(
            matches: demoMatches,
            outcomesByMatchId: app.cachedPredictionOutcomesByMatchId,
            fromBackend: true,
          )
        : (_data ??
              const _SerieAData(
                matches: [],
                outcomesByMatchId: {},
                fromBackend: false,
              ));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.tabLive,
          style: const TextStyle(fontWeight: FontWeight.w700),
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
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: 0,
                        label: Text(
                          l10n.serieASegmentResults,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text(
                          l10n.serieASegmentStandings,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
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
                  ? _buildSerieAStandings(context, app)
                  : RefreshIndicator(
                      onRefresh: demoActive ? () async {} : _reload,
                      child: demoActive
                          ? _buildDemoList(
                              context,
                              _segment,
                              demoMatches,
                              app.cachedPredictionOutcomesByMatchId,
                              l10n,
                            )
                          : _buildList(context, effectiveData),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSerieAStandings(BuildContext context, AppState appState) {
    final l10n = AppLocalizations.of(context)!;
    final standings = appState.cachedSeasonStandings;
    if (standings.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(child: Text(l10n.commonNoDataAvailable)),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [SerieAStandingsTable(standings: standings)],
      ),
    );
  }

  Widget _buildList(BuildContext context, _SerieAData data) {
    final l10n = AppLocalizations.of(context)!;
    final matches = List<PredictionMatch>.of(data.matches)
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    if (matches.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(child: Text(l10n.serieANoMatchesToShow)),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: matches.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = matches[i];
        final liveScore = _liveScoreLabel(m);
        final liveStatus = _statusLabelForCard(m.statusShort, l10n);
        final kickoff = formatKickoff(m.kickoff);

        const liveSet = {'1H', 'HT', '2H', 'ET', 'BT', 'LIVE', 'P'};
        final rawStatus = (m.statusShort ?? '').trim().toUpperCase();
        final isMatchLive = liveSet.contains(rawStatus);

        return Material(
          color: CassandraColors.platinum,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => LiveMatchDetailsPage(match: m),
                ),
              );
            },
            child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TeamName(
                              name: m.homeTeam,
                              logoUrl: m.homeTeamLogo,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: CassandraColors.inkBlackV2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 118,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // LIVE badge
                              if (isMatchLive) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 2),
                                  decoration: BoxDecoration(
                                    color: CassandraColors.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    m.statusShort!,
                                    style: const TextStyle(
                                      color: CassandraColors.onPrimary,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ] else ...[
                                // Orario pre-partita
                                Text(
                                  kickoff,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: CassandraColors.inkBlackV2.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              // Score — ink black bold
                              Text(
                                liveScore,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: CassandraColors.inkBlackV2,
                                  letterSpacing: -0.5,
                                  height: 1.1,
                                ),
                              ),
                              // Status (FT, 1T, ecc.)
                              if (liveStatus.isNotEmpty) ...[
                                const SizedBox(height: 1),
                                Text(
                                  liveStatus,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: CassandraColors.inkBlackV2.withValues(
                                      alpha: 0.55,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TeamName(
                              name: m.awayTeam,
                              logoUrl: m.awayTeamLogo,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: CassandraColors.inkBlackV2,
                              ),
                              reversed: true,
                            ),
                          ),
                        ),
                      ],
                    ),
            ), // inner Container
          ), // InkWell
        ); // Material
      },
    );
  }

  String _liveScoreLabel(PredictionMatch match) {
    if (_isNotStarted(match.statusShort)) return '–';
    final homeGoals = match.homeGoals;
    final awayGoals = match.awayGoals;
    if (homeGoals == null || awayGoals == null) return '- – -';
    return '$homeGoals – $awayGoals';
  }

  bool _isNotStarted(String? rawStatus) {
    final status = (rawStatus ?? '').trim().toUpperCase();
    return status.isEmpty ||
        status == 'NS' ||
        status == 'TBD' ||
        status == 'PST';
  }

  String _statusLabelForCard(String? rawStatus, AppLocalizations l10n) {
    if (_isNotStarted(rawStatus)) return '';
    final status = (rawStatus ?? '').trim().toUpperCase();
    if (status == '1H') return l10n.liveStatusFirstHalf;
    if (status == 'HT') return l10n.liveStatusHalftime;
    if (status == '2H' || status == 'ET' || status == 'BT' || status == 'P') {
      return l10n.liveStatusSecondHalf;
    }
    if (status == 'FT' ||
        status == 'AET' ||
        status == 'PEN' ||
        status == 'WO' ||
        status == 'AWD' ||
        status == 'CANC') {
      return l10n.liveStatusFinal;
    }
    return status;
  }
}

class _SerieAData {
  final List<PredictionMatch> matches;
  final Map<String, MatchOutcome> outcomesByMatchId;
  final bool fromBackend;
  final String? errorMessage;

  const _SerieAData({
    required this.matches,
    required this.outcomesByMatchId,
    required this.fromBackend,
    this.errorMessage,
  });
}

Widget _buildDemoList(
  BuildContext context,
  int segment,
  List<PredictionMatch> all,
  Map<String, MatchOutcome> outcomes,
  AppLocalizations l10n,
) {
  final matches = all.where((m) {
    final o = outcomes[m.id] ?? MatchOutcome.pending;
    return segment == 0 ? !o.isPending : o.isPending;
  }).toList()..sort((a, b) => a.kickoff.compareTo(b.kickoff));

  if (matches.isEmpty) {
    return Center(
      child: Text(
        segment == 0 ? l10n.serieANoResults : l10n.serieANoUpcomingMatches,
      ),
    );
  }

  return ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    itemCount: matches.length,
    separatorBuilder: (context, index) => const SizedBox(height: 12),
    itemBuilder: (context, i) {
      final m = matches[i];
      final o = outcomes[m.id] ?? MatchOutcome.pending;
      final kickoff = formatKickoff(m.kickoff);
      final score = _demoScoreLabel(m, o: o);
      final status = _demoStatusLabel(m.statusShort, l10n, o);

      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => LiveMatchDetailsPage(match: m)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TeamName(
                      name: m.homeTeam,
                      logoUrl: m.homeTeamLogo,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 118,
                  child: Column(
                    children: [
                      Text(
                        kickoff,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: CassandraColors.slate,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        score,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 18,
                        child: Text(
                          status,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: CassandraColors.slate,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TeamName(
                      name: m.awayTeam,
                      logoUrl: m.awayTeamLogo,
                      style: Theme.of(context).textTheme.titleMedium,
                      reversed: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _demoScoreLabel(PredictionMatch m, {required MatchOutcome o}) {
  if (o == MatchOutcome.pending) return '–';
  if (m.homeGoals != null && m.awayGoals != null) {
    return '${m.homeGoals} – ${m.awayGoals}';
  }
  return '- – -';
}

String _demoStatusLabel(
  String? rawStatus,
  AppLocalizations l10n,
  MatchOutcome o,
) {
  final status = (rawStatus ?? '').trim().toUpperCase();
  if (status == '1H') return l10n.liveStatusFirstHalf;
  if (status == 'HT') return l10n.liveStatusHalftime;
  if (status == '2H' || status == 'ET' || status == 'BT' || status == 'P') {
    return l10n.liveStatusSecondHalf;
  }
  if (status == 'FT' || o != MatchOutcome.pending) return l10n.liveStatusFinal;
  return '';
}
