import 'package:flutter/material.dart';
import '../../app/theme/cassandra_colors.dart';
import '../../app/widgets/demo_banner.dart';
import 'models/mock_prediction_data.dart';
import 'models/pick_option.dart';
import 'models/prediction_match.dart';
import 'models/formatters.dart';
import 'widgets/prediction_match_card.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/scoring_engine.dart';
import '../../app/state/cassandra_scope.dart';
import '../../l10n/app_localizations.dart';
import '../../domain/matchday/matchday_recovery_rules.dart'
    show MatchdayProgress, computeMatchdayProgress;
import '../leaderboards/mock_season_data.dart';
import '../leaderboards/models/matchday_data.dart';
import 'predictions_matchday_page.dart';
import 'predictions_history_page.dart';
import '../scoring/models/score_breakdown.dart';
import '../../services/api_football/models/api_football_standing.dart';
import '../../services/firestore/models/matchday_document.dart';
import 'widgets/serie_a_standings_table.dart';

enum VisibilityChoice { private, public }

class PredictionsPage extends StatefulWidget {
  const PredictionsPage({super.key});
  @override
  State<PredictionsPage> createState() => _PredictionsPageState();
}

class _PredictionsPageState extends State<PredictionsPage>
    with AutomaticKeepAliveClientMixin {
  bool _isLoadingRealFixtures = false;

  @override
  bool get wantKeepAlive => true;

  bool _didLoadRealFixtures = false;

  bool get demoActive {
    final appState = CassandraScope.of(context);
    return appState.cachedPredictionMatches != null &&
        !appState.cachedPredictionMatchesAreReal;
  }

  List<PredictionMatch> get matches {
    final appState = CassandraScope.of(context);
    final cached = appState.cachedPredictionMatches;
    if (cached != null && !appState.cachedPredictionMatchesAreReal) {
      return cached;
    }
    if (_matches.isNotEmpty) return _matches;
    return cached ?? _matches;
  }

  String get matchdayLabel {
    final appState = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isEnglish = l10n.localeName.startsWith('en');
    if (demoActive) {
      return l10n.groupMatchdayLabel(
        appState.uiMatchdayNumber,
        formatMatchdayDays(matches.map((m) => m.kickoff), english: isEnglish),
      );
    }
    return _matchdayLabel;
  }

  int get _matchdayNumber => CassandraScope.of(context).cassandraMatchdayCursor;
  int? _shownMatchdayNumber;
  int get _effectiveMatchdayNumber {
    if (demoActive) return CassandraScope.of(context).uiMatchdayNumber;
    return _shownMatchdayNumber ?? _matchdayNumber;
  }

  late List<PredictionMatch> _matches;
  bool _usingRealFixtures = false;
  bool _loadingFixtures = false;
  bool _didLoadFixtures = false;
  List<ApiFootballStanding>? _standings;
  final Map<String, PickOption> _picks = {};
  int _segment = 0; // 0 = futuri, 1 = passati
  VisibilityChoice? _submittedVisibility;
  DateTime? _submittedAt;
  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('[predictions] initState ${identityHashCode(this)}');
    }
    _matches = mockPredictionMatches();
  }

  @override
  void dispose() {
    if (kDebugMode) {
      debugPrint('[predictions] dispose ${identityHashCode(this)}');
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadRealFixtures) return;
    _didLoadRealFixtures = true;

    // Se home_shell ha già caricato dati reali in cache, sincronizziamo subito
    // lo stato locale così il badge "dati: reali" appare immediatamente.
    final scope = CassandraScope.of(context);
    final cached = scope.cachedPredictionMatches;
    if (cached != null &&
        cached.isNotEmpty &&
        scope.cachedPredictionMatchesAreReal) {
      _usingRealFixtures = true;
    }

    if (_didLoadFixtures) return;
    _tryLoadRealFixturesOnce();
  }

  PickOption _pickFor(String matchId) {
    final appState = CassandraScope.of(context);
    appState.cachedPredictionMatches != null &&
        !appState.cachedPredictionMatchesAreReal;

    appState.ensureCurrentUserPicksLoaded();
    return appState.currentUserPicksByMatchId[matchId] ?? PickOption.none;
  }

  int get _pickedCount => matches.where((m) => !_pickFor(m.id).isNone).length;
  int get _missingCount => matches.length - _pickedCount;
  DateTime? get _firstKickoff => matches.isEmpty
      ? null
      : matches.map((m) => m.kickoff).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get _lockTime =>
      _firstKickoff?.subtract(const Duration(minutes: 30));
  bool get _locked => _lockTime != null && DateTime.now().isAfter(_lockTime!);
  String get _matchdayLabel {
    final l10n = AppLocalizations.of(context)!;
    final daysLabel = formatMatchdayDays(
      matches.map((m) => m.kickoff),
      english: l10n.localeName.startsWith('en'),
    );
    return l10n.groupMatchdayLabel(_effectiveMatchdayNumber, daysLabel);
  }

  double? _oddsForPick(PredictionMatch match, PickOption pick) {
    switch (pick) {
      case PickOption.none:
        return null;
      case PickOption.home:
        return match.odds.home;
      case PickOption.draw:
        return match.odds.draw;
      case PickOption.away:
        return match.odds.away;
      case PickOption.homeDraw:
        return match.odds.homeDraw;
      case PickOption.drawAway:
        return match.odds.drawAway;
      case PickOption.homeAway:
        return match.odds.homeAway;
    }
  }

  double? get _averageOddsPlayed {
    final values = <double>[];
    for (final match in _matches) {
      final pick = _pickFor(match.id);
      final odds = _oddsForPick(match, pick);
      if (odds != null) values.add(odds);
    }
    if (values.isEmpty) return null;
    final sum = values.reduce((a, b) => a + b);
    return sum / values.length;
  }

  void _setPick(String matchId, PickOption pick) {
    final l10n = AppLocalizations.of(context)!;
    // Lock: non permettere modifiche ai pick se la partita è già iniziata.
    final PredictionMatch? match = matches.cast<PredictionMatch?>().firstWhere(
      (m) => m?.id == matchId,
      orElse: () => null,
    );
    if (match != null && DateTime.now().isAfter(match.kickoff)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.predictionsPickLockedSnack)));
      return;
    }
    setState(() => _picks[matchId] = pick);
    CassandraScope.of(context).setCurrentUserPick(matchId, pick);
  }

  Future<bool> _confirmSubmitIfMissing(int missing) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text(l10n.predictionsMissingConfirm(missing)),
          actions: [
            IconButton(
              tooltip: l10n.predHistoryTitle,
              icon: const Icon(Icons.history),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PredictionsHistoryPage(),
                  ),
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.settingsCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.predictionsSubmitAnyway),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _submit(VisibilityChoice visibility) async {
    final l10n = AppLocalizations.of(context)!;
    if (_locked) return;
    final missing = _missingCount;
    if (missing > 0) {
      final ok = await _confirmSubmitIfMissing(missing);
      if (!ok) return;
      if (!mounted) return; // dopo await
    }
    if (!mounted) return;
    setState(() {
      _submittedVisibility = visibility;
      _submittedAt = DateTime.now();
    });
    final label = visibility == VisibilityChoice.public
        ? l10n.predictionsVisibilityPublic
        : l10n.predictionsVisibilityPrivate;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.predictionsSlipSubmitted(label))),
    );
    // Snapshot storico: salva i pick per questa giornata (così "passati" diventa vero)
    final appState = CassandraScope.of(context);
    appState.ensureCurrentUserPicksHistoryLoaded();
    appState.ensureMatchdayMatchesLoaded();
    appState.ensureOutcomesHistoryLoaded();
    appState.saveCurrentUserPicksHistory(
      dayNumber: _effectiveMatchdayNumber,
      picksByMatchId: _picks,
    );
    await appState.saveMatchdayMatchesSnapshot(
      matchdayNumber: _effectiveMatchdayNumber,
      matches: matches,
    );
    appState.ensureMatchesHistoryLoaded();
    appState.saveMatchesHistory(
      matchdayNumber: _effectiveMatchdayNumber,
      matches: matches,
    );
    // Se abbiamo outcomes disponibili, salvali anche nello storico (per punteggi stabili)
    final outcomesNow = <String, MatchOutcome>{
      for (final e in appState.effectivePredictionOutcomesByMatchId.entries)
        e.key: e.value,
    };
    if (outcomesNow.isNotEmpty) {
      appState.ensureOutcomesHistoryLoaded();
      appState.saveOutcomesHistory(
        dayNumber: _effectiveMatchdayNumber,
        outcomesByMatchId: outcomesNow,
      );
    }

    // Firestore sync (fire-and-forget)
    DayScoreBreakdown? scoreCache;
    if (outcomesNow.isNotEmpty) {
      scoreCache = CassandraScoringEngine.computeDayScore(
        matches: matches,
        picksByMatchId: _picks,
        outcomesByMatchId: outcomesNow,
      );
    }
    final visLabel = visibility == VisibilityChoice.public
        ? 'public'
        : 'private';
    appState.submitPicksToFirestore(
      dayNumber: _effectiveMatchdayNumber,
      picksByMatchId: _picks,
      visibility: visLabel,
      score: scoreCache,
    );
  }

  Future<void> _tryLoadRealFixtures({bool showLoader = false}) async {
    final appState = CassandraScope.of(context);
    final fs = appState.firestoreService;

    if (showLoader && mounted) {
      setState(() => _loadingFixtures = true);
    }

    try {
      final scope = appState;
      // DEV: se abbiamo cache DEMO (isReal=false), non sovrascrivere con backend cache
      final cached = scope.cachedPredictionMatches;
      if (cached != null && !scope.cachedPredictionMatchesAreReal) {
        if (mounted) {
          setState(() {
            _shownMatchdayNumber = scope.uiMatchdayNumber;
            _matches = cached;
            _usingRealFixtures = false;
          });
        }
        // Compute MatchdayProgress for demo fixtures
        final demoNow = DateTime.now();
        final demoAppState = scope;
        demoAppState.ensureOriginKickoffsLoaded();
        final demoOutcomes = demoAppState.effectivePredictionOutcomesByMatchId;
        String demoStatusFor(PredictionMatch m) =>
            (demoOutcomes[m.id] ?? MatchOutcome.pending).isGraded ? 'FT' : 'NS';
        final demoProgress = computeMatchdayProgress<PredictionMatch>(
          cached,
          now: demoNow,
          kickoff: (m) => m.kickoff,
          originKickoff: (m) => demoAppState.originKickoffFor(
            matchId: m.id,
            fallbackKickoff: m.kickoff,
          ),
          statusShort: (m) => demoStatusFor(m),
        );
        demoAppState.setMatchdayProgress(
          matchdayNumber: demoAppState.uiMatchdayNumber,
          progress: demoProgress,
        );
        if (kDebugMode) {
          debugPrint(
            '[fixtures/demo] progress day=${demoAppState.uiMatchdayNumber} '
            'played=${demoProgress.playedFixtures} void=${demoProgress.voidFixtures}',
          );
        }
        return;
      }

      if (fs == null) {
        if (kDebugMode) {
          debugPrint('[fixtures] firestore unavailable -> using local/demo');
        }
        return;
      }
      if (!appState.isAuthenticated) {
        if (kDebugMode) {
          debugPrint('[fixtures] unauthenticated -> using local/demo');
        }
        return;
      }

      final standings = await fs.getSeasonStandings(
        seasonKey: appState.currentSeasonKey,
      );
      final now = DateTime.now();
      var dayNumber = appState.cassandraMatchdayCursor;
      appState.ensureOriginKickoffsLoaded();

      MatchdayDocument? resolvedDoc;
      MatchdayProgress? resolvedProgress;

      // Catch-up automatico: salta le giornate già "primaryDone" in un unico load.
      const maxLookAheadDays = 12;
      for (var i = 0; i <= maxLookAheadDays; i++) {
        final candidate = await fs.getMatchdayData(
          seasonKey: appState.currentSeasonKey,
          dayNumber: dayNumber,
        );
        if (candidate == null || candidate.matches.isEmpty) {
          if (kDebugMode) {
            debugPrint('[fixtures] no firestore data for day=$dayNumber');
          }
          dayNumber += 1;
          continue;
        }

        final matches = candidate.matches;
        final outcomes = candidate.outcomesByMatchId;
        for (final m in matches) {
          appState.registerOriginKickoff(matchId: m.id, kickoff: m.kickoff);
        }

        String statusFor(PredictionMatch m) =>
            (outcomes[m.id] ?? MatchOutcome.pending).isGraded ? 'FT' : 'NS';
        final progress = computeMatchdayProgress<PredictionMatch>(
          matches,
          now: now,
          kickoff: (m) => m.kickoff,
          originKickoff: (m) => appState.originKickoffFor(
            matchId: m.id,
            fallbackKickoff: m.kickoff,
          ),
          statusShort: (m) => statusFor(m),
        );

        if (kDebugMode) {
          debugPrint(
            '[fixtures] progress day=${candidate.dayNumber} '
            'primaryDone=${progress.primaryDone} finalDone=${progress.finalDone} '
            'played=${progress.playedFixtures} void=${progress.voidFixtures}',
          );
        }

        resolvedDoc = candidate;
        resolvedProgress = progress;

        if (!progress.primaryDone) break;
        dayNumber += 1;
      }

      await appState.persistOriginKickoffs();

      if (resolvedDoc == null) {
        if (mounted && standings.isNotEmpty) {
          setState(() => _standings = standings);
        }
        return;
      }

      if (resolvedDoc.dayNumber != appState.cassandraMatchdayCursor) {
        await appState.setCassandraMatchdayCursor(resolvedDoc.dayNumber);
      }

      final matches = resolvedDoc.matches;
      final outcomes = resolvedDoc.outcomesByMatchId;
      appState.setMatchdayProgress(
        matchdayNumber: resolvedDoc.dayNumber,
        progress: resolvedProgress!,
        allowAutoAdvance: false,
      );

      if (!mounted) return;
      setState(() {
        _shownMatchdayNumber = resolvedDoc!.dayNumber;
        _matches = matches;
        _usingRealFixtures = true;
        _standings = standings.isEmpty ? null : standings;
      });
      scope.setCachedPredictionMatches(
        matches,
        isReal: true,
        updatedAt: resolvedDoc.updatedAt,
      );
      scope.setCachedPredictionOutcomesByMatchId(outcomes);
      appState.setRecentMatchdayDataBulk(
        matchesByMatchday: {resolvedDoc.dayNumber: matches},
        outcomesByMatchday: {resolvedDoc.dayNumber: outcomes},
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[fixtures] load failed: $e');
        debugPrint('$st');
      }
    } finally {
      if (showLoader && mounted) {
        setState(() => _loadingFixtures = false);
      }
    }
  }

  Map<String, PickOption> _demoPicksForMatchday(
    String seed,
    List<PredictionMatch> matches,
  ) {
    final rnd = Random(seed.hashCode);
    PickOption randomPick() {
      final x = rnd.nextDouble();
      if (x < 0.10) return PickOption.none;
      if (x < 0.75) {
        const singles = [PickOption.home, PickOption.draw, PickOption.away];
        return singles[rnd.nextInt(singles.length)];
      }
      const doubles = [
        PickOption.homeDraw,
        PickOption.drawAway,
        PickOption.homeAway,
      ];
      return doubles[rnd.nextInt(doubles.length)];
    }

    final picks = <String, PickOption>{};
    for (final m in matches) {
      picks[m.id] = randomPick();
    }
    return picks;
  }

  Widget _buildHistory(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEnglish = l10n.localeName.startsWith('en');
    final appState = CassandraScope.of(context);
    appState.ensureCurrentUserPicksLoaded();
    final uid = appState.profile.id;
    final liveMatches = appState.cachedPredictionMatches ?? _matches;
    final liveOutcomes =
        appState.hasSavedOutcomesForMatchday(_effectiveMatchdayNumber)
        ? appState.outcomesForMatchday(_effectiveMatchdayNumber)
        : <String, MatchOutcome>{
            for (final m in liveMatches)
              if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
                m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
          };
    final livePicks = appState.currentUserPicksByMatchId.isNotEmpty
        ? appState.currentUserPicksByMatchId
        : _picks;
    final liveMatchday = MatchdayData(
      dayNumber: _effectiveMatchdayNumber,
      matches: liveMatches,
      outcomesByMatchId: liveOutcomes,
    );
    final historyDays = appState.recentMatchesByMatchday.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final demoHistory = mockSeasonMatchdays(
      startDay: 16,
      count: 4,
      demoSeed: appState.demoSeed,
    )..sort((a, b) => b.dayNumber.compareTo(a.dayNumber));
    Widget tileFor(
      MatchdayData md,
      Map<String, PickOption> picks, {
      String? tag,
    }) {
      final daysLabel = formatMatchdayDays(
        md.matches.map((m) => m.kickoff),
        english: isEnglish,
      );
      final total = md.matches.length;
      final graded = md.matches.where((m) {
        final o = md.outcomesByMatchId[m.id] ?? MatchOutcome.pending;
        return !o.isPending;
      }).length;
      final resultsLabel = graded == total
          ? l10n.groupResultsLabel(graded, total)
          : l10n.groupResultsLabelPartial(graded, total);
      final title = tag == null
          ? l10n.groupMatchdayTitle(md.dayNumber)
          : '${l10n.groupMatchdayTitle(md.dayNumber)} ($tag)';
      final appState = CassandraScope.of(context);
      final savedMatches = appState.matchesByMatchday[md.dayNumber];
      final matchesEffective = (savedMatches != null && savedMatches.isNotEmpty)
          ? savedMatches
          : md.matches;
      final savedOutcomes = appState.outcomesByMatchday[md.dayNumber];
      final outcomesEffective =
          (savedOutcomes != null && savedOutcomes.isNotEmpty)
          ? savedOutcomes
          : md.outcomesByMatchId;
      final picksEffective = appState.picksForCurrentUserForMatchday(
        md.dayNumber,
      );
      return Card(
        child: ListTile(
          title: Text(title),
          subtitle: Text('$daysLabel\n$resultsLabel'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PredictionsMatchdayPage(
                  matchdayNumber: md.dayNumber,
                  matches: matchesEffective,
                  outcomesByMatchId: outcomesEffective,
                  picksByMatchId: picksEffective,
                ),
              ),
            );
          },
        ),
      );
    }

    final liveTag = appState.cachedPredictionMatchesAreReal
        ? l10n.predictionsTagLive
        : l10n.predictionsTagDemo;
    appState.ensureCurrentUserPicksHistoryLoaded();
    final hasSavedLive = appState.hasSavedPicksForMatchday(
      _effectiveMatchdayNumber,
    );
    final livePicksEffective = hasSavedLive
        ? appState.currentUserPicksForMatchday(_effectiveMatchdayNumber)
        : livePicks;
    final liveTagEffective = hasSavedLive ? l10n.predictionsTagSaved : liveTag;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              l10n.predictionsHistoryDemoInfo,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: 8),
        tileFor(liveMatchday, livePicksEffective, tag: liveTagEffective),
        const SizedBox(height: 12),
        if (historyDays.isNotEmpty)
          for (final day in historyDays)
            if (day != _matchdayNumber)
              Builder(
                builder: (context) {
                  final savedMatches = appState.matchesByMatchday[day];
                  final recentMatches = appState.recentMatchesByMatchday[day];
                  final matchesEffective =
                      (savedMatches != null && savedMatches.isNotEmpty)
                      ? savedMatches
                      : (recentMatches ?? const <PredictionMatch>[]);
                  if (matchesEffective.isEmpty) return const SizedBox.shrink();
                  final savedOutcomes = appState.outcomesByMatchday[day];
                  final recentOutcomes = appState.recentOutcomesByMatchday[day];
                  final outcomesEffective =
                      (savedOutcomes != null && savedOutcomes.isNotEmpty)
                      ? savedOutcomes
                      : (recentOutcomes ?? const <String, MatchOutcome>{});
                  final picksEffective = appState.hasSavedPicksForMatchday(day)
                      ? appState.currentUserPicksForMatchday(day)
                      : _demoPicksForMatchday(
                          '${uid}_${day}_${appState.demoSeed}',
                          matchesEffective,
                        );
                  final prog = appState.matchdayProgressFor(day);
                  final tag =
                      (prog != null && prog.primaryDone && !prog.finalDone)
                      ? l10n.predictionsTagRecoveries
                      : (appState.hasSavedPicksForMatchday(day)
                            ? l10n.predictionsTagSaved
                            : l10n.predictionsTagLive);
                  final md = MatchdayData(
                    dayNumber: day,
                    matches: matchesEffective,
                    outcomesByMatchId: outcomesEffective,
                  );
                  return tileFor(md, picksEffective, tag: tag);
                },
              ),
        if (historyDays.isEmpty)
          for (final md in demoHistory)
            tileFor(
              appState.hasSavedOutcomesForMatchday(md.dayNumber)
                  ? MatchdayData(
                      dayNumber: md.dayNumber,
                      matches: md.matches,
                      outcomesByMatchId: appState.outcomesForMatchday(
                        md.dayNumber,
                      ),
                    )
                  : md,
              appState.hasSavedPicksForMatchday(md.dayNumber)
                  ? appState.currentUserPicksForMatchday(md.dayNumber)
                  : _demoPicksForMatchday(
                      '${uid}_${md.dayNumber}_${appState.demoSeed}',
                      md.matches,
                    ),
              tag: appState.hasSavedPicksForMatchday(md.dayNumber)
                  ? l10n.predictionsTagSaved
                  : l10n.predictionsTagDemo,
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final appState = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;

    // Mentre i dati reali si caricano, mostra spinner
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(centerTitle: true, title: Text(l10n.tabPredictions)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final voidedByPostponement = <String>{};
    for (final m in matches) {
      final origin = appState.originKickoffFor(
        matchId: m.id,
        fallbackKickoff: m.kickoff,
      );
      final diff = m.kickoff.difference(origin);
      if (diff > const Duration(hours: 48)) {
        voidedByPostponement.add(m.id);
      }
    }
    final scoringMatches = matches
        .where((m) => !voidedByPostponement.contains(m.id))
        .toList(growable: false);
    final pickedCountForScoring = scoringMatches
        .where((m) => !_pickFor(m.id).isNone)
        .length;
    final lockLabel = _locked
        ? l10n.predictionsPicksLocked
        : _lockTime != null
        ? l10n.predictionsEditableUntil(formatKickoff(_lockTime!))
        : '';
    final scoreOutcomesByMatchId = <String, MatchOutcome>{
      for (final m in scoringMatches)
        if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
          m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
    };
    final DayScoreBreakdown dayScore = CassandraScoringEngine.computeDayScore(
      matches: scoringMatches,
      picksByMatchId: {for (final m in scoringMatches) m.id: _pickFor(m.id)},
      outcomesByMatchId: scoreOutcomesByMatchId,
    );
    final bonusSigned = dayScore.bonusPoints == 0
        ? '0'
        : (dayScore.bonusPoints > 0
              ? '+${dayScore.bonusPoints}'
              : '${dayScore.bonusPoints}');
    final scoreAvgLabel = dayScore.averageOddsPlayed == null
        ? '—'
        : formatOdds(dayScore.averageOddsPlayed!);
    final scoreLabel = l10n.predictionsScoreSummary(
      formatOdds(dayScore.total),
      formatOdds(dayScore.baseTotal),
      bonusSigned,
      dayScore.correctCount,
      dayScore.matchBreakdowns.length,
      scoreAvgLabel,
    );
    final avg = _averageOddsPlayed;
    final avgLabel = avg == null ? '-' : formatOdds(avg);
    final isOffline = !_usingRealFixtures;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(l10n.tabPredictions),
        actions: [
          IconButton(
            tooltip: l10n.predictionsRefreshMatches,
            onPressed: (_loadingFixtures || demoActive)
                ? null
                : () => _tryLoadRealFixturesOnce(showLoader: true, force: true),
            icon: _loadingFixtures
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_usingRealFixtures)
              DemoBanner(label: l10n.predictionsSampleDataBanner),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 1,
                        label: Text(l10n.predictionsPastSegment),
                      ),
                      ButtonSegment(
                        value: 0,
                        label: Text(l10n.predictionsUpcomingSegment),
                      ),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (newSelection) {
                      setState(() => _segment = newSelection.first);
                    },
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: CassandraColors.primary.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            matchdayLabel,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (lockLabel.isNotEmpty)
                                Expanded(
                                  child: _buildMetaChip(
                                    icon: _locked
                                        ? Icons.lock_outline
                                        : Icons.schedule_outlined,
                                    label: lockLabel,
                                    backgroundColor: _locked
                                        ? CassandraColors.primary.withValues(
                                            alpha: 0.13,
                                          )
                                        : CassandraColors.bg,
                                    borderColor: _locked
                                        ? CassandraColors.primary.withValues(
                                            alpha: 0.35,
                                          )
                                        : CassandraColors.primary.withValues(
                                            alpha: 0.22,
                                          ),
                                  ),
                                ),
                              if (isOffline && lockLabel.isNotEmpty)
                                const SizedBox(width: 8),
                              if (isOffline)
                                Flexible(
                                  child: _buildMetaChip(
                                    icon: Icons.wifi_off_outlined,
                                    label: l10n.predictionsOfflineStatus,
                                    backgroundColor: isOffline
                                        ? CassandraColors.primary.withValues(
                                            alpha: 0.12,
                                          )
                                        : CassandraColors.bg,
                                    borderColor: isOffline
                                        ? CassandraColors.primary.withValues(
                                            alpha: 0.35,
                                          )
                                        : CassandraColors.primary.withValues(
                                            alpha: 0.22,
                                          ),
                                  ),
                                ),
                            ],
                          ),
                          if (lockLabel.isNotEmpty || isOffline)
                            const SizedBox(height: 10),
                          Text(
                            scoreLabel,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.predictionsPicksSummary(
                              pickedCountForScoring,
                              scoringMatches.length,
                              avgLabel,
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: CassandraColors.slate),
                          ),
                          if (_submittedVisibility != null &&
                              _submittedAt != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              l10n.predictionsLastSubmit(
                                formatKickoff(_submittedAt!),
                                _submittedVisibility == VisibilityChoice.public
                                    ? l10n.predictionsVisibilityPublic
                                    : l10n.predictionsVisibilityPrivate,
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: CassandraColors.slate),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _segment == 1
                  ? _buildHistory(context)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: matches.length + (_standings != null ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i < matches.length) {
                          final match = matches[i];
                          final pick = _pickFor(match.id);
                          return PredictionMatchCard(
                            match: match,
                            pick: pick,
                            locked: _locked,
                            onPick: (p) => _setPick(match.id, p),
                          );
                        }
                        return SerieAStandingsTable(standings: _standings!);
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _segment == 1
          ? null
          : SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: CassandraColors.bg.withValues(alpha: 0.96),
                  border: Border(
                    top: BorderSide(
                      color: CassandraColors.primary.withValues(alpha: 0.14),
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: CassandraColors.primary.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _locked
                              ? null
                              : () => _submit(VisibilityChoice.private),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: CassandraColors.primary.withValues(
                                alpha: 0.65,
                              ),
                            ),
                            foregroundColor: CassandraColors.primary,
                            backgroundColor: CassandraColors.bg,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          child: Text(
                            l10n.predictionsSubmitWithoutShowing,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _locked
                              ? null
                              : () => _submit(VisibilityChoice.public),
                          style: FilledButton.styleFrom(
                            backgroundColor: CassandraColors.primary,
                            foregroundColor: CassandraColors.bg,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: Text(
                            l10n.predictionsSubmitAndShow,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
    Color? backgroundColor,
    Color? borderColor,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor ?? CassandraColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                borderColor ?? CassandraColors.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: CassandraColors.primary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: CassandraColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _tryLoadRealFixturesOnce({
    bool showLoader = false,
    bool force = false,
  }) async {
    if (_isLoadingRealFixtures) {
      return;
    }
    if (_didLoadFixtures && !force) {
      return;
    }
    _isLoadingRealFixtures = true;
    try {
      await _tryLoadRealFixtures(showLoader: showLoader);
      _didLoadFixtures = true;
    } finally {
      _isLoadingRealFixtures = false;
    }
  }
}
