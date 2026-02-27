import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  bool _submitted = false;

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

  void _setPick(String matchId, PickOption pick) {
    final l10n = AppLocalizations.of(context)!;
    if (_submitted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.predictionsAlreadySubmitted)),
      );
      return;
    }
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

    // Auto-show submit confirmation when all picks are made
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _submitted) return;
      if (_pickedCount == matches.length) {
        _showSubmitConfirmation();
      }
    });
  }

  Future<void> _showSubmitConfirmation() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: CassandraColors.brightSnow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Text(
            l10n.predictionsConfirmSubmit,
            style: const TextStyle(
              color: CassandraColors.inkBlackV2,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: CassandraColors.inkBlackV2,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: Text(
                l10n.predictionsConfirmNo,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: CassandraColors.inkBlackV2,
                foregroundColor: CassandraColors.brightSnow,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                l10n.predictionsConfirmYes,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (result == true) {
      await _submit(VisibilityChoice.public);
      if (mounted) {
        setState(() => _submitted = true);
      }
    }
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
        if (!progress.readyToAdvance) break;
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
        backgroundColor: Colors.transparent,
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

    // Hero card height: padding(4+4) + container padding(18+16)
    // + title(~24) + gap(10) + ring(140) ≈ 216
    const heroAreaHeight = 216.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Demo banner
            if (!usingRealFixturesNow)
              DemoBanner(label: l10n.predictionsSampleDataBanner),

            // ── Stack: hero card pinned on top, match cards scroll under ──
            Expanded(
              child: Stack(
                children: [
                  // Layer 1: scrollable match cards
                  CustomScrollView(
                    slivers: [
                      // Spacer so cards start below the hero card (+10 gap)
                      const SliverToBoxAdapter(
                        child: SizedBox(height: heroAreaHeight + 18),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((ctx, i) {
                            final match = matches[i];
                            final pick = _pickFor(match.id);
                            final outcome =
                                scoreOutcomesByMatchId[match.id];
                            final breakdown = dayScore.matchBreakdowns
                                .cast<MatchScoreBreakdown?>()
                                .firstWhere(
                                  (b) => b?.matchId == match.id,
                                  orElse: () => null,
                                );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _CompactMatchCard(
                                match: match,
                                pick: pick,
                                locked: _locked,
                                onPick: (p) => _setPick(match.id, p),
                                outcome: outcome,
                                matchBreakdown: breakdown,
                              ),
                            );
                          }, childCount: matches.length),
                        ),
                      ),
                      if (standings.isNotEmpty)
                        SliverToBoxAdapter(
                          child: SerieAStandingsTable(standings: standings),
                        ),
                      const SliverPadding(
                        padding: EdgeInsets.only(bottom: 16),
                      ),
                    ],
                  ),

                  // Layer 2: charcoal mask — hides cards at hero card center.
                  // Same colour as HomeShell bg so it's invisible.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: heroAreaHeight / 2,
                    child: const ColoredBox(
                      color: CassandraColors.charcoal,
                    ),
                  ),

                  // Layer 3: hero card pinned on top.
                  Positioned(
                    top: 0,
                    left: 12,
                    right: 12,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: _HeroScoreCard(
                        dayScore: dayScore,
                        matches: scoringMatches,
                        outcomesByMatchId: scoreOutcomesByMatchId,
                        pickFor: _pickFor,
                        isMatchdayFinalized: isMatchdayFinalized,
                        bonusSigned: bonusSigned,
                        isEnglish: isEnglish,
                        matchdayNumber: _effectiveMatchdayNumber,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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

/// Whether [pick] matches the live [outcome].
bool _isPickCorrect(PickOption pick, MatchOutcome outcome) {
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

class _HeroScoreCard extends StatelessWidget {
  const _HeroScoreCard({
    required this.dayScore,
    required this.matches,
    required this.outcomesByMatchId,
    required this.pickFor,
    required this.isMatchdayFinalized,
    required this.bonusSigned,
    required this.isEnglish,
    required this.matchdayNumber,
  });

  final DayScoreBreakdown dayScore;
  final List<PredictionMatch> matches;
  final Map<String, MatchOutcome> outcomesByMatchId;
  final PickOption Function(String) pickFor;
  final bool isMatchdayFinalized;
  final String bonusSigned;
  final bool isEnglish;
  final int matchdayNumber;

  static const _fg = CassandraColors.brightSnow;

  List<Color> _segmentColors() {
    return matches.map((m) {
      final outcome = outcomesByMatchId[m.id];
      final isPending = outcome == null || outcome.isPending;
      final isVoided = outcome?.isVoided ?? false;
      if (isVoided) return Colors.transparent;
      if (isPending) return CassandraColors.cardBg;
      final pick = pickFor(m.id);
      final correct = _isPickCorrect(pick, outcome);
      return correct ? CassandraColors.darkCyan : CassandraColors.primary;
    }).toList();
  }

  List<bool> _segmentVoided() {
    return matches.map((m) {
      final outcome = outcomesByMatchId[m.id];
      return outcome?.isVoided ?? false;
    }).toList();
  }

  /// Bonus value color: darkCyan if positive, cherry red if negative,
  /// white smoke if zero or not yet finalized.
  Color get _bonusColor {
    if (!isMatchdayFinalized) return _fg;
    if (dayScore.bonusPoints > 0) return CassandraColors.darkCyan;
    if (dayScore.bonusPoints < 0) return CassandraColors.primary;
    return _fg;
  }

  @override
  Widget build(BuildContext context) {
    final total = formatOdds(dayScore.total);
    final correctCount = dayScore.correctCount;
    final totalMatches = matches.length;
    final totalPoints = isMatchdayFinalized ? formatOdds(dayScore.total) : '-';

    final segColors = _segmentColors();
    final segVoided = _segmentVoided();

    final matchdayTitle = isEnglish
        ? 'Matchday $matchdayNumber'
        : 'Giornata $matchdayNumber';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: CassandraColors.inkBlackV2,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left: title + ring with score ──────────────────────────
          Expanded(
            flex: 50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  matchdayTitle,
                  style: const TextStyle(
                    color: _fg,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                // Ring with "punti live" + score in center
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(
                    painter: _RingPainter(
                      segmentColors: segColors,
                      segmentVoided: segVoided,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isEnglish ? 'Live points' : 'Punti live',
                            style: const TextStyle(
                              color: _fg,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            total,
                            style: const TextStyle(
                              color: _fg,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                              letterSpacing: -1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Right: 6-line breakdown — left-aligned with 8 px
          // padding from the invisible vertical center line ──────────
          Expanded(
            flex: 50,
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 4),
                  // 1. "Pronostici corretti"
                  Text(
                    isEnglish ? 'Correct picks' : 'Pronostici corretti',
                    style: const TextStyle(
                      color: _fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 2. X/10
                  Text(
                    '$correctCount/$totalMatches',
                    style: const TextStyle(
                      color: _fg,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 3. "Punti bonus"
                  Text(
                    isEnglish ? 'Bonus points' : 'Punti bonus',
                    style: const TextStyle(
                      color: _fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 4. Bonus value
                  Text(
                    isMatchdayFinalized ? bonusSigned : '-',
                    style: TextStyle(
                      color: _bonusColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 5. "Punti totali"
                  Text(
                    isEnglish ? 'Total points' : 'Punti totali',
                    style: const TextStyle(
                      color: _fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 6. Total value
                  Text(
                    totalPoints,
                    style: const TextStyle(
                      color: _fg,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flat 2D Ring Painter — two semicircles × 5 segments
// ─────────────────────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  _RingPainter({required this.segmentColors, required this.segmentVoided});

  final List<Color> segmentColors;
  final List<bool> segmentVoided;

  // Gap between each of the 10 segments (uniform).
  static const double _gapDeg = 3.5;
  static const double _gapRad = _gapDeg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final count = segmentColors.length;
    if (count == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    const thickness = 22.0;
    final outerR = size.width / 2 * 1.10;
    final innerR = outerR - thickness;

    // Single ring: 10 equal segments, 10 equal gaps.
    // Total gap = count * _gapRad. Remaining arc shared equally.
    final segSweep = (2 * math.pi - count * _gapRad) / count;

    // 12 o'clock = -π/2 in Flutter. The gap between segment 9 (last)
    // and segment 0 (first) is centred on 12 o'clock.
    // Segment 0 starts at: -π/2 + halfGap
    final startOffset = -math.pi / 2 + _gapRad / 2;

    for (var i = 0; i < count; i++) {
      final startA = startOffset + i * (segSweep + _gapRad);
      _drawSegment(canvas, center, innerR, outerR, startA, segSweep, i);
    }
  }

  void _drawSegment(
    Canvas canvas,
    Offset center,
    double innerR,
    double outerR,
    double startAngle,
    double sweepAngle,
    int index,
  ) {
    final path = _annularSector(center, innerR, outerR, startAngle, sweepAngle);
    final isVoided = index < segmentVoided.length && segmentVoided[index];

    if (isVoided) {
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = CassandraColors.cardBg.withValues(alpha: 0.30);
      canvas.drawPath(path, borderPaint);
      return;
    }

    final baseColor = index < segmentColors.length
        ? segmentColors[index]
        : CassandraColors.cardBg;
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = baseColor;
    canvas.drawPath(path, paint);
  }

  Path _annularSector(
    Offset center,
    double innerR,
    double outerR,
    double startAngle,
    double sweepAngle,
  ) {
    return Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: outerR),
        startAngle,
        sweepAngle,
      )
      ..arcTo(
        Rect.fromCircle(center: center, radius: innerR),
        startAngle + sweepAngle,
        -sweepAngle,
        false,
      )
      ..close();
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.segmentColors != segmentColors ||
        oldDelegate.segmentVoided != segmentVoided;
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
    this.outcome,
    this.matchBreakdown,
  });

  final PredictionMatch match;
  final PickOption pick;
  final bool locked;
  final ValueChanged<PickOption> onPick;
  final MatchOutcome? outcome;
  final MatchScoreBreakdown? matchBreakdown;

  bool get _isLive {
    final s = match.statusShort;
    return s != null &&
        const {'1H', 'HT', '2H', 'ET', 'BT', 'LIVE'}.contains(s);
  }

  bool get _isFT {
    final s = match.statusShort;
    return s == 'FT' || s == 'AET' || s == 'PEN';
  }

  /// Match has started or finished — show live layout.
  bool get _isStarted => _isLive || _isFT;

  String _centerText() {
    final hasGoals = match.homeGoals != null && match.awayGoals != null;
    if (hasGoals && _isStarted) {
      return '${match.homeGoals}-${match.awayGoals}';
    }
    final local = match.kickoff.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Determine live outcome from current score.
  MatchOutcome get _liveOutcome {
    if (outcome != null && outcome!.isGraded) return outcome!;
    final hg = match.homeGoals;
    final ag = match.awayGoals;
    if (hg == null || ag == null) return MatchOutcome.pending;
    if (hg > ag) return MatchOutcome.home;
    if (hg < ag) return MatchOutcome.away;
    return MatchOutcome.draw;
  }

  /// Is the current pick correct given the live outcome?
  bool get _isPickCorrectNow {
    final o = _liveOutcome;
    if (o.isPending || o.isVoided) return false;
    return _isPickCorrect(pick, o);
  }

  /// Win odds: what the user gains if correct.
  double get _winOdds {
    if (pick.isNone) return 0;
    switch (pick) {
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
      case PickOption.none:
        return 0;
    }
  }

  /// Lose odds: what the user loses if wrong.
  double get _loseOdds {
    if (pick.isNone) return 0;
    // Single: penalty = complementary double chance
    if (pick.isSingle) {
      switch (pick) {
        case PickOption.home:
          return match.odds.drawAway;
        case PickOption.draw:
          return match.odds.homeAway;
        case PickOption.away:
          return match.odds.homeDraw;
        default:
          return 0;
      }
    }
    // Double: penalty = complementary single × 2
    switch (pick) {
      case PickOption.homeDraw:
        return match.odds.away * 2;
      case PickOption.drawAway:
        return match.odds.home * 2;
      case PickOption.homeAway:
        return match.odds.draw * 2;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final centerText = _centerText();
    final homeInitial = match.homeTeam.isNotEmpty ? match.homeTeam[0] : '?';
    final awayInitial = match.awayTeam.isNotEmpty ? match.awayTeam[0] : '?';

    return Container(
      decoration: BoxDecoration(
        color: CassandraColors.inkBlackV2,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: CassandraColors.platinum,
          borderRadius: BorderRadius.circular(16),
        ),
        child: _isStarted
            ? _buildLiveLayout(centerText, homeInitial, awayInitial)
            : _buildPreMatchLayout(centerText, homeInitial, awayInitial),
      ),
    );
  }

  /// Pre-match: teams row + 6 odds buttons (2 rows of 3).
  Widget _buildPreMatchLayout(
    String centerText,
    String homeInitial,
    String awayInitial,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Logos + teams + kickoff ─────────────────────────────────
        Row(
          children: [
            _TeamLogo(
              url: match.homeTeamLogo,
              initial: homeInitial,
              teamName: match.homeTeam,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                match.homeTeam,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: CassandraColors.inkBlackV2,
                ),
              ),
            ),
            Text(
              formatKickoff(match.kickoff),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: CassandraColors.inkBlackV2,
              ),
            ),
            Expanded(
              child: Text(
                match.awayTeam,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: CassandraColors.inkBlackV2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _TeamLogo(
              url: match.awayTeamLogo,
              initial: awayInitial,
              teamName: match.awayTeam,
            ),
          ],
        ),

        const SizedBox(height: 8),

        // ── Charcoal divider ─────────────────────────────────────────
        Container(
          height: 1,
          color: CassandraColors.charcoal,
        ),

        const SizedBox(height: 8),

        // ── All 6 odds on one row ──────────────────────────────────
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
    );
  }

  /// Live/FT: compact single row with teams, score, and 2 result buttons.
  Widget _buildLiveLayout(
    String centerText,
    String homeInitial,
    String awayInitial,
  ) {
    final liveO = _liveOutcome;
    final isGraded = liveO.isGraded;
    final correct = isGraded ? _isPickCorrectNow : false;
    final hasPick = !pick.isNone;

    return Row(
      children: [
        // ── Left: logos + teams + score ─────────────────────────────
        _TeamLogo(
          url: match.homeTeamLogo,
          initial: homeInitial,
          teamName: match.homeTeam,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${match.homeTeam} – ${match.awayTeam}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: CassandraColors.inkBlackV2,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (_isLive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      margin: const EdgeInsets.only(right: 6),
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _isLive
                          ? CassandraColors.primary
                          : CassandraColors.inkBlackV2,
                    ),
                  ),
                  if (_isFT) ...[
                    const SizedBox(width: 4),
                    Text(
                      'FT',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: CassandraColors.slate.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _TeamLogo(
          url: match.awayTeamLogo,
          initial: awayInitial,
          teamName: match.awayTeam,
        ),

        // ── Right: 2 result buttons ────────────────────────────────
        if (hasPick) ...[
          const SizedBox(width: 10),
          _LiveResultButton(
            label: '+${formatOdds(_winOdds)}',
            isHighlighted: isGraded && correct,
            isWin: true,
          ),
          const SizedBox(width: 4),
          _LiveResultButton(
            label: '-${formatOdds(_loseOdds)}',
            isHighlighted: isGraded && !correct,
            isWin: false,
          ),
        ],
      ],
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
    final fg = selected
        ? CassandraColors.brightSnow
        : CassandraColors.inkBlackV2;
    final bg = selected
        ? CassandraColors.inkBlackV2
        : CassandraColors.brightSnow;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: OutlinedButton(
          onPressed: locked ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: fg,
            backgroundColor: bg,
            disabledForegroundColor: fg,
            disabledBackgroundColor: bg,
            side: BorderSide(
              color: CassandraColors.inkBlackV2,
              width: selected ? 1.5 : 0.8,
            ),
            padding: const EdgeInsets.symmetric(vertical: 3),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
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
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                formatOdds(odds),
                style: TextStyle(
                  color: fg,
                  fontSize: 9,
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
// Live Result Button (win/loss during live matches)
// ─────────────────────────────────────────────────────────────────────────────

class _LiveResultButton extends StatelessWidget {
  const _LiveResultButton({
    required this.label,
    required this.isHighlighted,
    required this.isWin,
  });

  final String label;
  final bool isHighlighted;

  /// true = win (darkCyan when highlighted), false = loss (cherryRed).
  final bool isWin;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;

    if (!isHighlighted) {
      bg = CassandraColors.platinum;
      fg = CassandraColors.inkBlackV2;
    } else if (isWin) {
      bg = CassandraColors.darkCyan;
      fg = CassandraColors.inkBlackV2;
    } else {
      bg = CassandraColors.primary; // cherry red
      fg = CassandraColors.brightSnow;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CassandraColors.inkBlackV2, width: 1.0),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Team Logo
// ─────────────────────────────────────────────────────────────────────────────

class _TeamLogo extends StatelessWidget {
  const _TeamLogo({required this.url, required this.initial, this.teamName});

  final String? url;
  final String initial;
  final String? teamName;

  /// Bundled logo override for teams whose API logo doesn't render well.
  static const Map<String, String> _bundledOverrides = {
    'juventus': 'assets/logos/juventus_mark.svg',
  };

  String? _bundledAssetFor(String? name) {
    if (name == null) return null;
    final key = name.trim().toLowerCase();
    for (final entry in _bundledOverrides.entries) {
      if (key.contains(entry.key)) return entry.value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const size = 30.0;

    // Check for bundled override first (e.g. Juventus black fill SVG).
    final bundled = _bundledAssetFor(teamName);
    if (bundled != null) {
      final widget = bundled.endsWith('.svg')
          ? SvgPicture.asset(
              bundled,
              width: size,
              height: size,
              fit: BoxFit.contain,
            )
          : Image.asset(
              bundled,
              width: size,
              height: size,
              fit: BoxFit.contain,
            );
      return SizedBox(width: size, height: size, child: widget);
    }

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
