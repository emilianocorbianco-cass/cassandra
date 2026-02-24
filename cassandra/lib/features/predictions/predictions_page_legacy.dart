import 'dart:async';

import 'package:flutter/material.dart';
import '../../app/theme/cassandra_colors.dart';
import '../../app/widgets/demo_banner.dart';
import 'models/mock_prediction_data.dart';
import 'models/pick_option.dart';
import 'models/prediction_match.dart';
import 'models/formatters.dart';
import 'widgets/prediction_match_card.dart';
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

class PredictionsPageLegacy extends StatefulWidget {
  const PredictionsPageLegacy({super.key});
  @override
  State<PredictionsPageLegacy> createState() => _PredictionsPageLegacyState();
}

class _PredictionsPageLegacyState extends State<PredictionsPageLegacy>
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
    if (cached != null && cached.isNotEmpty) return cached;
    if (_matches.isNotEmpty) return _matches;
    return _matches;
  }

  int get _matchdayNumber => CassandraScope.of(context).cassandraMatchdayCursor;
  int? _shownMatchdayNumber;
  int get _effectiveMatchdayNumber {
    if (demoActive) return CassandraScope.of(context).uiMatchdayNumber;
    return _shownMatchdayNumber ?? _matchdayNumber;
  }

  late List<PredictionMatch> _matches;
  bool _usingRealFixtures = false;
  bool _didLoadFixtures = false;
  Timer? _lockRefreshTimer;
  DateTime? _lockRefreshTarget;
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
    _lockRefreshTimer?.cancel();
    _lockRefreshTimer = null;
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

  void _scheduleLockRefreshIfNeeded() {
    final lockTime = _lockTime;
    if (lockTime == null) {
      _lockRefreshTimer?.cancel();
      _lockRefreshTimer = null;
      _lockRefreshTarget = null;
      return;
    }

    if (_lockRefreshTarget == lockTime && _lockRefreshTimer != null) return;

    _lockRefreshTimer?.cancel();
    _lockRefreshTarget = lockTime;
    final now = DateTime.now();
    final delay = lockTime.difference(now);
    if (delay <= Duration.zero) return;

    _lockRefreshTimer = Timer(delay + const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {});
      _lockRefreshTimer = null;
      _lockRefreshTarget = null;
    });
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _formattedDayMonth(DateTime date, {required bool english}) {
    final local = date.toLocal();
    final weekday = english
        ? englishWeekdayName(local.weekday)
        : italianWeekdayName(local.weekday);
    final month = english
        ? englishMonthName(local.month)
        : italianMonthName(local.month);
    return '${_capitalize(weekday)} ${local.day} ${_capitalize(month)}';
  }

  String _matchdayDateRangeLabel({required bool english}) {
    if (matches.isEmpty) return '';
    final days =
        matches
            .map((m) => m.kickoff.toLocal())
            .map((dt) => DateTime(dt.year, dt.month, dt.day))
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    if (days.isEmpty) return '';
    final start = _formattedDayMonth(days.first, english: english);
    final end = _formattedDayMonth(days.last, english: english);
    return start == end ? start : '$start → $end';
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

  Future<void> _tryLoadRealFixtures() async {
    final appState = CassandraScope.of(context);
    final fs = appState.firestoreService;

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

        if (!progress.readyToAdvance) break;
        dayNumber += 1;
      }

      await appState.persistOriginKickoffs();

      if (resolvedDoc == null) {
        if (mounted && standings.isNotEmpty) {
          appState.setCachedSeasonStandings(standings);
          setState(() => _standings = standings);
        }
        return;
      }

      if (resolvedDoc.dayNumber != appState.cassandraMatchdayCursor) {
        await appState.setCassandraMatchdayCursor(resolvedDoc.dayNumber);
      }

      final resolvedDayNumber = resolvedDoc.dayNumber;
      final matches = resolvedDoc.matches;
      final outcomes = resolvedDoc.outcomesByMatchId;
      appState.setMatchdayProgress(
        matchdayNumber: resolvedDayNumber,
        progress: resolvedProgress!,
        allowAutoAdvance: false,
      );

      if (!mounted) return;
      setState(() {
        _shownMatchdayNumber = resolvedDayNumber;
        _matches = matches;
        _usingRealFixtures = true;
        _standings = standings.isEmpty ? null : standings;
      });
      appState.setCachedSeasonStandings(
        standings,
        updatedAt: resolvedDoc.updatedAt,
      );
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
    }
  }

  Widget _buildHistory(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEnglish = l10n.localeName.startsWith('en');
    final appState = CassandraScope.of(context);
    appState.ensureCurrentUserPicksLoaded();
    final liveMatches = appState.cachedPredictionMatches ?? _matches;
    final liveOutcomes =
        appState.hasSavedOutcomesForMatchday(_effectiveMatchdayNumber)
        ? appState.outcomesForMatchday(_effectiveMatchdayNumber)
        : <String, MatchOutcome>{
            for (final m in liveMatches)
              if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
                m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
          };
    final liveMatchday = MatchdayData(
      dayNumber: _effectiveMatchdayNumber,
      matches: liveMatches,
      outcomesByMatchId: liveOutcomes,
    );
    final historyDaySet = <int>{
      ...appState.recentMatchesByMatchday.keys,
      ...appState.currentUserPicksByMatchday.keys,
      ...appState.matchesByMatchday.keys,
      ...appState.outcomesByMatchday.keys,
    };
    final historyDays = historyDaySet.toList()..sort((a, b) => b.compareTo(a));
    final nonCurrentHistoryDays = historyDays
        .where((day) => day != _effectiveMatchdayNumber)
        .toList(growable: false);
    final demoHistory = mockSeasonMatchdays(
      startDay: 16,
      count: 4,
      demoSeed: appState.demoSeed,
    )..sort((a, b) => b.dayNumber.compareTo(a.dayNumber));
    Widget tileFor(MatchdayData md, {String? tag}) {
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
        tileFor(liveMatchday, tag: liveTagEffective),
        const SizedBox(height: 12),
        if (nonCurrentHistoryDays.isNotEmpty)
          for (final day in nonCurrentHistoryDays)
            Builder(
              builder: (context) {
                final savedMatches = appState.matchesByMatchday[day];
                final recentMatches = appState.recentMatchesByMatchday[day];
                final matchesEffective =
                    (savedMatches != null && savedMatches.isNotEmpty)
                    ? savedMatches
                    : (recentMatches ?? const <PredictionMatch>[]);
                final savedOutcomes = appState.outcomesByMatchday[day];
                final recentOutcomes = appState.recentOutcomesByMatchday[day];
                final outcomesEffective =
                    (savedOutcomes != null && savedOutcomes.isNotEmpty)
                    ? savedOutcomes
                    : (recentOutcomes ?? const <String, MatchOutcome>{});
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
                return tileFor(md, tag: tag);
              },
            ),
        if (nonCurrentHistoryDays.isEmpty)
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
    _scheduleLockRefreshIfNeeded();

    final appState = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final usingRealFixturesNow =
        _usingRealFixtures || appState.cachedPredictionMatchesAreReal;
    final standingsEffective = appState.cachedSeasonStandings.isNotEmpty
        ? appState.cachedSeasonStandings
        : _standings;

    // Mentre i dati reali si caricano, mostra spinner
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            l10n.tabPredictions,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
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
    final isMatchdayFinalized =
        scoringMatches.isNotEmpty &&
        scoringMatches.every((m) {
          final outcome = scoreOutcomesByMatchId[m.id];
          return outcome != null && outcome.isGraded;
        });
    final bonusSigned = dayScore.bonusPoints == 0
        ? '0'
        : (dayScore.bonusPoints > 0
              ? '+${dayScore.bonusPoints}'
              : '${dayScore.bonusPoints}');
    final matchdayTitle = l10n.groupMatchdayTitle(_effectiveMatchdayNumber);
    final matchdayRange = _matchdayDateRangeLabel(
      english: l10n.localeName.startsWith('en'),
    );
    final correctLine = l10n.predictionsCorrectLine(
      dayScore.correctCount,
      matches.length,
    );
    final basePoints = formatOdds(dayScore.baseTotal);
    final pointsLine = isMatchdayFinalized
        ? (l10n.localeName.startsWith('it')
              ? 'Punti: $basePoints (Bonus $bonusSigned)'
              : 'Points: $basePoints (Bonus $bonusSigned)')
        : (l10n.localeName.startsWith('it')
              ? 'Punti: $basePoints'
              : 'Points: $basePoints');
    final matchdayHeaderStyle = Theme.of(context).textTheme.titleMedium
        ?.copyWith(
          fontWeight: FontWeight.w700,
          color: CassandraColors.slate,
          fontSize:
              (Theme.of(context).textTheme.titleMedium?.fontSize ?? 16) + 2,
        );
    final summaryLineStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: CassandraColors.slate,
    );
    final isOffline = !usingRealFixturesNow;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          l10n.tabPredictions,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!usingRealFixturesNow)
              DemoBanner(label: l10n.predictionsSampleDataBanner),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: 1,
                        label: Text(
                          l10n.predictionsPastSegment,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ButtonSegment(
                        value: 0,
                        label: Text(
                          l10n.predictionsUpcomingSegment,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
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
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(matchdayTitle, style: matchdayHeaderStyle),
                          if (matchdayRange.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            SizedBox(
                              width: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  matchdayRange,
                                  maxLines: 1,
                                  style: matchdayHeaderStyle,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
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
                            const SizedBox(height: 8),
                          Text(correctLine, style: summaryLineStyle),
                          const SizedBox(height: 4),
                          Text(pointsLine, style: summaryLineStyle),
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
                      itemCount:
                          matches.length + (standingsEffective != null ? 1 : 0),
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
                        return SerieAStandingsTable(
                          standings: standingsEffective!,
                        );
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
                        child: OutlinedButton.icon(
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
                          icon: const Icon(
                            Icons.visibility_off_outlined,
                            size: 18,
                          ),
                          label: Text(
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
                            foregroundColor: CassandraColors.onPrimary,
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

  Future<void> _tryLoadRealFixturesOnce({bool force = false}) async {
    if (_isLoadingRealFixtures) {
      return;
    }
    if (_didLoadFixtures && !force) {
      return;
    }
    _isLoadingRealFixtures = true;
    try {
      await _tryLoadRealFixtures();
      _didLoadFixtures = true;
    } finally {
      _isLoadingRealFixtures = false;
    }
  }
}
