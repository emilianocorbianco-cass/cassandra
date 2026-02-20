import 'package:flutter/material.dart';
import '../../app/widgets/demo_banner.dart';
import 'models/mock_prediction_data.dart';
import 'models/pick_option.dart';
import 'models/prediction_match.dart';
import 'models/formatters.dart';
import 'widgets/prediction_match_card.dart';
import 'widgets/predictions_matchday_summary.dart';
import 'widgets/predictions_submit_bar.dart';
import 'widgets/predictions_history_list.dart';
import 'package:flutter/foundation.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/scoring_engine.dart';
import '../../app/state/cassandra_scope.dart';
import '../../l10n/app_localizations.dart';
import '../../domain/matchday/matchday_recovery_rules.dart'
    show MatchdayProgress, computeMatchdayProgress;
import '../scoring/models/score_breakdown.dart';
import '../../services/api_football/models/api_football_standing.dart';
import '../../services/firestore/models/matchday_document.dart';
import 'widgets/serie_a_standings_table.dart';
import 'predictions_history_page.dart';

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
      if (!mounted) return;
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
      final cached = scope.cachedPredictionMatches;
      if (cached != null && !scope.cachedPredictionMatchesAreReal) {
        if (mounted) {
          setState(() {
            _shownMatchdayNumber = scope.uiMatchdayNumber;
            _matches = cached;
            _usingRealFixtures = false;
          });
        }
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
          appState.setCachedSeasonStandings(standings);
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final appState = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final usingRealFixturesNow =
        _usingRealFixtures || appState.cachedPredictionMatchesAreReal;
    final standingsEffective = appState.cachedSeasonStandings.isNotEmpty
        ? appState.cachedSeasonStandings
        : _standings;

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
    final isOffline = !usingRealFixturesNow;

    // Compute live outcomes for history
    final liveOutcomes =
        appState.hasSavedOutcomesForMatchday(_effectiveMatchdayNumber)
        ? appState.outcomesForMatchday(_effectiveMatchdayNumber)
        : <String, MatchOutcome>{
            for (final m in matches)
              if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
                m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
          };

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
                  PredictionsMatchdaySummary(
                    matchdayTitle: matchdayTitle,
                    matchdayRange: matchdayRange,
                    lockLabel: lockLabel,
                    locked: _locked,
                    isOffline: isOffline,
                    correctLine: correctLine,
                    pointsLine: pointsLine,
                    submittedVisibility: _submittedVisibility,
                    submittedAt: _submittedAt,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _segment == 1
                  ? PredictionsHistoryList(
                      effectiveMatchdayNumber: _effectiveMatchdayNumber,
                      liveMatches: appState.cachedPredictionMatches ?? _matches,
                      liveOutcomes: liveOutcomes,
                    )
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
          : PredictionsSubmitBar(
              locked: _locked,
              onSubmitPrivate: () => _submit(VisibilityChoice.private),
              onSubmitPublic: () => _submit(VisibilityChoice.public),
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
