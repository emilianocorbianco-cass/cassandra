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
import 'live_standings_overlay.dart';

class SerieAPage extends StatefulWidget {
  const SerieAPage({super.key});

  @override
  State<SerieAPage> createState() => _SerieAPageState();
}

class _SerieAPageState extends State<SerieAPage> {
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
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: demoActive ? () async {} : _reload,
          child: _buildUnifiedList(context, app, effectiveData, demoActive, l10n),
        ),
      ),
    );
  }

  Widget _buildUnifiedList(
    BuildContext context,
    AppState app,
    _SerieAData effectiveData,
    bool demoActive,
    AppLocalizations l10n,
  ) {
    // Build match cards.
    final matches = List<PredictionMatch>.of(effectiveData.matches)
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));

    // Build standings widget (if available).
    final baseStandings = app.cachedSeasonStandings;
    final liveMatches = app.cachedPredictionMatches ?? const [];
    final standings = baseStandings.isNotEmpty
        ? computeLiveStandings(baseStandings, liveMatches)
        : null;

    if (matches.isEmpty && standings == null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(child: Text(l10n.serieANoMatchesToShow)),
        ],
      );
    }

    final isEnglish = l10n.localeName.startsWith('en');
    final matchdayTitle = isEnglish
        ? 'Matchday ${app.cassandraMatchdayCursor}'
        : 'Giornata ${app.cassandraMatchdayCursor}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 90),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            matchdayTitle,
            style: const TextStyle(
              color: CassandraColors.brightSnow,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        for (int i = 0; i < matches.length; i++) ...[
          if (i > 0) const SizedBox(height: 18),
          _buildMatchCard(context, matches[i], l10n),
        ],
        if (matches.isNotEmpty && standings != null) ...[
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 18),
        ],
        if (standings != null)
          SerieAStandingsTable(standings: standings),
      ],
    );
  }

  Widget _buildMatchCard(
    BuildContext context,
    PredictionMatch m,
    AppLocalizations l10n,
  ) {
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
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: CassandraColors.inkBlackV2,
                    ),
                    reversed: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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

