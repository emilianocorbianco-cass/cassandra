import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../../app/widgets/demo_banner.dart';
import '../../domain/matchday/matchday_recovery_rules.dart'
    show MatchdayProgress, computeMatchdayProgress;
import '../../l10n/app_localizations.dart';
import '../../services/firestore/models/matchday_document.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/models/score_breakdown.dart';
import '../scoring/scoring_engine.dart';
import 'models/formatters.dart';
import 'models/mock_prediction_data.dart';
import 'models/pick_option.dart';
import 'models/prediction_match.dart';
import 'predictions_history_page.dart';
import 'widgets/serie_a_standings_table.dart';

enum VisibilityChoice { private, public }

// ─────────────────────────────────────────────────────────────────────────────
// Main widget
// ─────────────────────────────────────────────────────────────────────────────

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
  bool _didLoadFixtures = false;

  bool get demoActive {
    final appState = CassandraScope.of(context);
    return appState.cachedPredictionMatches != null &&
        !appState.cachedPredictionMatchesAreReal;
  }

  List<PredictionMatch> get matches {
    final appState = CassandraScope.of(context);
    final cached = appState.cachedPredictionMatches;
    if (cached != null && cached.isNotEmpty) return cached;
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
  Timer? _lockRefreshTimer;
  DateTime? _lockRefreshTarget;
  final Map<String, PickOption> _picks = {};
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
    final delay = lockTime.difference(DateTime.now());
    if (delay <= Duration.zero) return;
    _lockRefreshTimer = Timer(delay + const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {});
      _lockRefreshTimer = null;
      _lockRefreshTarget = null;
    });
  }

  /// Returns "20 Febbraio → 23 Febbraio" (no weekday, full month name).
  String _matchdayDateRangeShort({required bool english}) {
    if (matches.isEmpty) return '';
    final days =
        matches
            .map((m) => m.kickoff.toLocal())
            .map((dt) => DateTime(dt.year, dt.month, dt.day))
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    if (days.isEmpty) return '';
    String fmt(DateTime d) {
      final month = english
          ? englishMonthName(d.month)
          : italianMonthName(d.month);
      return '${d.day} $month';
    }

    if (days.length == 1) return fmt(days.first);
    return '${fmt(days.first)} → ${fmt(days.last)}';
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

        final mList = candidate.matches;
        final outcomes = candidate.outcomesByMatchId;
        for (final m in mList) {
          appState.registerOriginKickoff(matchId: m.id, kickoff: m.kickoff);
        }

        String statusFor(PredictionMatch m) =>
            (outcomes[m.id] ?? MatchOutcome.pending).isGraded ? 'FT' : 'NS';
        final progress = computeMatchdayProgress<PredictionMatch>(
          mList,
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

      if (resolvedDoc == null) return;

      if (resolvedDoc.dayNumber != appState.cassandraMatchdayCursor) {
        await appState.setCassandraMatchdayCursor(resolvedDoc.dayNumber);
      }

      final resolvedDayNumber = resolvedDoc.dayNumber;
      final mList = resolvedDoc.matches;
      final outcomes = resolvedDoc.outcomesByMatchId;
      appState.setMatchdayProgress(
        matchdayNumber: resolvedDayNumber,
        progress: resolvedProgress!,
        allowAutoAdvance: false,
      );

      if (!mounted) return;
      setState(() {
        _shownMatchdayNumber = resolvedDayNumber;
        _matches = mList;
        _usingRealFixtures = true;
      });
      scope.setCachedPredictionMatches(
        mList,
        isReal: true,
        updatedAt: resolvedDoc.updatedAt,
      );
      scope.setCachedPredictionOutcomesByMatchId(outcomes);
      appState.setRecentMatchdayDataBulk(
        matchesByMatchday: {resolvedDoc.dayNumber: mList},
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
    _scheduleLockRefreshIfNeeded();

    final appState = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isEnglish = l10n.localeName.startsWith('en');
    final usingRealFixturesNow =
        _usingRealFixtures || appState.cachedPredictionMatchesAreReal;
    final standings = appState.cachedSeasonStandings;

    // Loading guard
    if (matches.isEmpty) {
      return Scaffold(
        backgroundColor: CassandraColors.bg,
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
    final matchdayDateShort = _matchdayDateRangeShort(english: isEnglish);

    return Scaffold(
      backgroundColor: CassandraColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Demo banner
            if (!usingRealFixturesNow)
              DemoBanner(label: l10n.predictionsSampleDataBanner),

            // ── Inline page header ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    matchdayTitle,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: CassandraColors.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (matchdayDateShort.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      matchdayDateShort,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CassandraColors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // ── Hero score card ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _HeroScoreCard(
                dayScore: dayScore,
                matches: scoringMatches,
                outcomesByMatchId: scoreOutcomesByMatchId,
                pickFor: _pickFor,
                locked: _locked,
                lockLabel: lockLabel,
                isMatchdayFinalized: isMatchdayFinalized,
                bonusSigned: bonusSigned,
                isEnglish: isEnglish,
                submittedAt: _submittedAt,
                submittedVisibility: _submittedVisibility,
                l10n: l10n,
              ),
            ),

            // ── Match grid + classifica ────────────────────────────────────
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisExtent: 180,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      delegate: SliverChildBuilderDelegate((ctx, i) {
                        final match = matches[i];
                        final pick = _pickFor(match.id);
                        return _CompactMatchCard(
                          match: match,
                          pick: pick,
                          locked: _locked,
                          onPick: (p) => _setPick(match.id, p),
                        );
                      }, childCount: matches.length),
                    ),
                  ),
                  if (standings.isNotEmpty)
                    SliverToBoxAdapter(
                      child: SerieAStandingsTable(standings: standings),
                    ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
                ],
              ),
            ),
          ],
        ),
      ),

      // ── Bottom save bar ────────────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
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
                        color: CassandraColors.primary.withValues(alpha: 0.65),
                      ),
                      foregroundColor: CassandraColors.primary,
                      backgroundColor: CassandraColors.bg,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    icon: const Icon(Icons.visibility_off_outlined, size: 18),
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

  Future<void> _tryLoadRealFixturesOnce({bool force = false}) async {
    if (_isLoadingRealFixtures) return;
    if (_didLoadFixtures && !force) return;
    _isLoadingRealFixtures = true;
    try {
      await _tryLoadRealFixtures();
      _didLoadFixtures = true;
    } finally {
      _isLoadingRealFixtures = false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Score Card
// ─────────────────────────────────────────────────────────────────────────────

class _HeroScoreCard extends StatelessWidget {
  const _HeroScoreCard({
    required this.dayScore,
    required this.matches,
    required this.outcomesByMatchId,
    required this.pickFor,
    required this.locked,
    required this.lockLabel,
    required this.isMatchdayFinalized,
    required this.bonusSigned,
    required this.isEnglish,
    required this.submittedAt,
    required this.submittedVisibility,
    required this.l10n,
  });

  final DayScoreBreakdown dayScore;
  final List<PredictionMatch> matches;
  final Map<String, MatchOutcome> outcomesByMatchId;
  final PickOption Function(String) pickFor;
  final bool locked;
  final String lockLabel;
  final bool isMatchdayFinalized;
  final String bonusSigned;
  final bool isEnglish;
  final DateTime? submittedAt;
  final VisibilityChoice? submittedVisibility;
  final AppLocalizations l10n;

  static const _fg = CassandraColors.navBarFg;

  @override
  Widget build(BuildContext context) {
    final total = formatOdds(dayScore.total);
    final base = formatOdds(dayScore.baseTotal);
    final correctCount = dayScore.correctCount;
    final totalMatches = matches.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: CassandraColors.navBarBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top row: big score + breakdown ──────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: total points (big)
              Expanded(
                flex: 55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEnglish ? 'Matchday points' : 'Punti giornata',
                      style: TextStyle(
                        color: _fg.withValues(alpha: 0.60),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total,
                      style: const TextStyle(
                        color: _fg,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                        letterSpacing: -1.5,
                      ),
                    ),
                  ],
                ),
              ),
              // Right: compact breakdown
              Expanded(
                flex: 45,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _BreakdownLine(
                      label: isEnglish
                          ? 'Correct: $correctCount/$totalMatches'
                          : 'Corretti: $correctCount/$totalMatches',
                      color: _fg.withValues(alpha: 0.90),
                      bold: true,
                    ),
                    const SizedBox(height: 3),
                    _BreakdownLine(
                      label: isEnglish ? 'Points: $base' : 'Punti: $base',
                      color: _fg.withValues(alpha: 0.65),
                    ),
                    const SizedBox(height: 2),
                    _BreakdownLine(
                      label: 'Bonus: $bonusSigned',
                      color: dayScore.bonusPoints > 0
                          ? const Color(0xFF6EE7A0)
                          : _fg.withValues(alpha: 0.55),
                      bold: dayScore.bonusPoints != 0,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Correctness bar ──────────────────────────────────────────────
          _CorrectnessDots(
            matches: matches,
            outcomesByMatchId: outcomesByMatchId,
            pickFor: pickFor,
          ),

          // ── Lock / submitted label ───────────────────────────────────────
          if (lockLabel.isNotEmpty) ...[
            const SizedBox(height: 10),
            if (locked)
              // Locked: riquadro con bordo rosso arrotondato
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: CassandraColors.primary,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 11, color: _fg),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        lockLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _fg,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              // Unlocked: stile sbiadito invariato
              Row(
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 11,
                    color: _fg.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      lockLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _fg.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
          ],

          if (submittedVisibility != null && submittedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              l10n.predictionsLastSubmit(
                formatKickoff(submittedAt!),
                submittedVisibility == VisibilityChoice.public
                    ? l10n.predictionsVisibilityPublic
                    : l10n.predictionsVisibilityPrivate,
              ),
              style: TextStyle(
                color: _fg.withValues(alpha: 0.45),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BreakdownLine extends StatelessWidget {
  const _BreakdownLine({
    required this.label,
    required this.color,
    this.bold = false,
  });

  final String label;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.end,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Correctness dots (bar style, fills full width)
// ─────────────────────────────────────────────────────────────────────────────

class _CorrectnessDots extends StatelessWidget {
  const _CorrectnessDots({
    required this.matches,
    required this.outcomesByMatchId,
    required this.pickFor,
  });

  final List<PredictionMatch> matches;
  final Map<String, MatchOutcome> outcomesByMatchId;
  final PickOption Function(String) pickFor;

  static bool _isPickCorrect(PickOption pick, MatchOutcome outcome) {
    switch (pick) {
      case PickOption.home:
        return outcome == MatchOutcome.home;
      case PickOption.draw:
        return outcome == MatchOutcome.draw;
      case PickOption.away:
        return outcome == MatchOutcome.away;
      case PickOption.homeDraw:
        return outcome == MatchOutcome.home || outcome == MatchOutcome.draw;
      case PickOption.drawAway:
        return outcome == MatchOutcome.draw || outcome == MatchOutcome.away;
      case PickOption.homeAway:
        return outcome == MatchOutcome.home || outcome == MatchOutcome.away;
      case PickOption.none:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (int i = 0; i < matches.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(child: _segment(matches[i])),
        ],
      ],
    );
  }

  Widget _segment(PredictionMatch m) {
    final outcome = outcomesByMatchId[m.id];
    final isPending = outcome == null || outcome.isPending;
    final isVoided = outcome?.isVoided ?? false;

    Color fill;
    Color border;

    if (isVoided) {
      fill = Colors.transparent;
      border = CassandraColors.navBarFg.withValues(alpha: 0.15);
    } else if (isPending) {
      fill = Colors.transparent;
      border = CassandraColors.navBarFg.withValues(alpha: 0.30);
    } else {
      final pick = pickFor(m.id);
      final correct = _isPickCorrect(pick, outcome);
      fill = correct ? CassandraColors.primary : CassandraColors.slate;
      border = fill;
    }

    return Container(
      height: 7,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border, width: 1.5),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact Match Card (2-column grid)
// ─────────────────────────────────────────────────────────────────────────────

class _CompactMatchCard extends StatelessWidget {
  const _CompactMatchCard({
    required this.match,
    required this.pick,
    required this.locked,
    required this.onPick,
  });

  final PredictionMatch match;
  final PickOption pick;
  final bool locked;
  final ValueChanged<PickOption> onPick;

  bool get _isLive {
    final s = match.statusShort;
    return s != null &&
        const {'1H', 'HT', '2H', 'ET', 'BT', 'LIVE'}.contains(s);
  }

  bool get _isFT {
    final s = match.statusShort;
    return s == 'FT' || s == 'AET' || s == 'PEN';
  }

  String _centerText() {
    final hasGoals = match.homeGoals != null && match.awayGoals != null;
    if (hasGoals && (_isLive || _isFT)) {
      return '${match.homeGoals}-${match.awayGoals}';
    }
    final local = match.kickoff.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final centerText = _centerText();
    final homeInitial = match.homeTeam.isNotEmpty ? match.homeTeam[0] : '?';
    final awayInitial = match.awayTeam.isNotEmpty ? match.awayTeam[0] : '?';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Logos + center ─────────────────────────────────────────
          Row(
            children: [
              _TeamLogo(url: match.homeTeamLogo, initial: homeInitial),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isLive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        margin: const EdgeInsets.only(bottom: 2),
                        decoration: BoxDecoration(
                          color: CassandraColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          match.statusShort!,
                          style: const TextStyle(
                            color: CassandraColors.onPrimary,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    Text(
                      centerText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: _isLive || _isFT ? 14 : 12,
                        fontWeight: FontWeight.w700,
                        color: _isLive
                            ? CassandraColors.primary
                            : CassandraColors.slate,
                      ),
                    ),
                    if (_isFT)
                      Text(
                        'FT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: CassandraColors.slate.withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
              ),
              _TeamLogo(url: match.awayTeamLogo, initial: awayInitial),
            ],
          ),

          const SizedBox(height: 4),

          // ── Team names ─────────────────────────────────────────────
          Text(
            '${match.homeTeam} – ${match.awayTeam}',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: CassandraColors.slate,
            ),
          ),

          // ── Kickoff date (only pre-match) ──────────────────────────
          if (!_isLive && !_isFT) ...[
            const SizedBox(height: 1),
            Text(
              formatKickoff(match.kickoff),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                color: CassandraColors.slate.withValues(alpha: 0.60),
              ),
            ),
          ],

          // ── Spacer ─────────────────────────────────────────────────
          const SizedBox(height: 6),

          // ── Singles row (1/X/2) ────────────────────────────────────
          Row(
            children: [
              _CompactOddsButton(
                label: '1',
                odds: match.odds.home,
                selected: pick == PickOption.home,
                locked: locked,
                onPressed: () => onPick(PickOption.home),
              ),
              _CompactOddsButton(
                label: 'X',
                odds: match.odds.draw,
                selected: pick == PickOption.draw,
                locked: locked,
                onPressed: () => onPick(PickOption.draw),
              ),
              _CompactOddsButton(
                label: '2',
                odds: match.odds.away,
                selected: pick == PickOption.away,
                locked: locked,
                onPressed: () => onPick(PickOption.away),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // ── Doubles row (1X/X2/12) ─────────────────────────────────
          Row(
            children: [
              _CompactOddsButton(
                label: '1X',
                odds: match.odds.homeDraw,
                selected: pick == PickOption.homeDraw,
                locked: locked,
                onPressed: () => onPick(PickOption.homeDraw),
              ),
              _CompactOddsButton(
                label: 'X2',
                odds: match.odds.drawAway,
                selected: pick == PickOption.drawAway,
                locked: locked,
                onPressed: () => onPick(PickOption.drawAway),
              ),
              _CompactOddsButton(
                label: '12',
                odds: match.odds.homeAway,
                selected: pick == PickOption.homeAway,
                locked: locked,
                onPressed: () => onPick(PickOption.homeAway),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact Odds Button
// ─────────────────────────────────────────────────────────────────────────────

class _CompactOddsButton extends StatelessWidget {
  const _CompactOddsButton({
    required this.label,
    required this.odds,
    required this.selected,
    required this.locked,
    required this.onPressed,
  });

  final String label;
  final double odds;
  final bool selected;
  final bool locked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? CassandraColors.onPrimary : CassandraColors.slate;
    final bg = selected ? CassandraColors.primary : Colors.transparent;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: OutlinedButton(
          onPressed: locked ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: fg,
            backgroundColor: bg,
            disabledForegroundColor: fg,
            disabledBackgroundColor: bg,
            side: BorderSide(
              color: CassandraColors.primary,
              width: selected ? 1.8 : 1.0,
            ),
            padding: const EdgeInsets.symmetric(vertical: 5),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                formatOdds(odds),
                style: TextStyle(
                  color: fg,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Team Logo
// ─────────────────────────────────────────────────────────────────────────────

class _TeamLogo extends StatelessWidget {
  const _TeamLogo({required this.url, required this.initial});

  final String? url;
  final String initial;

  @override
  Widget build(BuildContext context) {
    const size = 30.0;
    if (url != null && url!.isNotEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipOval(
          child: Image.network(
            url!,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _fallback(size),
          ),
        ),
      );
    }
    return _fallback(size);
  }

  Widget _fallback(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: CassandraColors.cardBg,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: CassandraColors.slate,
          ),
        ),
      ),
    );
  }
}
