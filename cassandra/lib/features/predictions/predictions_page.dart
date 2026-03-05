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
import '../group/models/group_member.dart';
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

  // ── Member picks overlay state ──
  String? _expandedMatchId;
  List<GroupMember>? _cachedGroupMembers;
  bool _memberPicksFetched = false;

  bool get demoActive {
    final appState = CassandraScope.of(context);
    return appState.cachedPredictionMatches != null &&
        !appState.cachedPredictionMatchesAreReal;
  }

  List<PredictionMatch> get matches {
    final appState = CassandraScope.of(context);
    final cached = appState.cachedPredictionMatches;
    final source = (cached != null && cached.isNotEmpty) ? cached : _matches;
    return List<PredictionMatch>.of(source)
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
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

    // Restore submitted state from persisted picks history.
    if (!_submitted) {
      scope.ensureCurrentUserPicksHistoryLoaded();
      if (scope.hasSavedPicksForMatchday(_effectiveMatchdayNumber)) {
        _submitted = true;
      }
    }

    if (_didLoadFixtures) return;
    _tryLoadRealFixturesOnce();
  }

  PickOption _pickFor(String matchId) {
    final appState = CassandraScope.of(context);
    appState.ensureCurrentUserPicksLoaded();
    appState.ensureCurrentUserPicksHistoryLoaded();
    final dayPicks = appState.picksForCurrentUserForMatchday(
      _effectiveMatchdayNumber,
    );
    return dayPicks[matchId] ?? PickOption.none;
  }

  int get _pickedCount => matches.where((m) => !_pickFor(m.id).isNone).length;
  int get _missingCount => matches.length - _pickedCount;
  DateTime? get _firstKickoff => matches.isEmpty
      ? null
      : matches.map((m) => m.kickoff).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get _lockTime =>
      _firstKickoff?.subtract(const Duration(minutes: 30));
  bool get _locked {
    final override = CassandraScope.of(context).debugLockOverride;
    if (override != null) return override;
    return _lockTime != null && DateTime.now().isAfter(_lockTime!);
  }

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.predictionsAlreadySubmitted)));
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
  }

  void _onHeroSubmit() {
    if (_submitted) return;
    if (_pickedCount < matches.length) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.predictionsMissingConfirm(
            matches.length - _pickedCount,
          )),
        ),
      );
      return;
    }
    _submit(VisibilityChoice.public).then((ok) {
      if (mounted && ok) setState(() => _submitted = true);
    });
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

  Future<bool> _submit(VisibilityChoice visibility) async {
    final l10n = AppLocalizations.of(context)!;
    if (_locked) return false;
    final missing = _missingCount;
    if (missing > 0) {
      final ok = await _confirmSubmitIfMissing(missing);
      if (!ok) return false;
      if (!mounted) return false;
    }
    if (!mounted) return false;
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
    final submitted = await appState.submitPicksToFirestore(
      dayNumber: _effectiveMatchdayNumber,
      picksByMatchId: _picks,
      visibility: visLabel,
      score: scoreCache,
    );
    if (!mounted) return submitted;
    if (submitted) {
      final label = visibility == VisibilityChoice.public
          ? l10n.predictionsVisibilityPublic
          : l10n.predictionsVisibilityPrivate;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.predictionsSlipSubmitted(label))),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.predictionsSlipSubmitFailed)));
    }
    return submitted;
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

  void _onToggleMatchExpand(String matchId) {
    if (_expandedMatchId == matchId) {
      setState(() => _expandedMatchId = null);
      return;
    }
    setState(() => _expandedMatchId = matchId);
    if (_memberPicksFetched) return;
    _memberPicksFetched = true;
    final appState = CassandraScope.of(context);
    appState.fetchFirestoreGroupMembers().then((members) {
      if (!mounted) return;
      _cachedGroupMembers = members;
      final uids = members.map((m) => m.id).toList();
      if (uids.isEmpty) return;
      appState
          .fetchFirestorePicksForMatchday(
            dayNumber: _effectiveMatchdayNumber,
            uids: uids,
          )
          .then((picksByUid) {
        if (!mounted) return;
        appState.setMemberPicksBulk(picksByUid);
        setState(() {});
      });
    });
  }

  List<_MemberPickData> _buildMemberRows(PredictionMatch match) {
    final appState = CassandraScope.of(context);
    final members = _cachedGroupMembers;
    if (members == null) return [];
    final allPicks = appState.memberPicksByMemberId;
    final currentUid = appState.profile.id;
    final rows = <_MemberPickData>[];
    for (final member in members) {
      if (member.id == currentUid) continue;
      final memberPicks = allPicks[member.id];
      final pick = memberPicks?[match.id] ?? PickOption.none;
      if (pick.isNone) continue;
      final odds = CassandraScoringEngine.oddsForPick(match, pick);
      final isStarted = _isMatchStarted(match);
      final isCorrect = isStarted && isPickCorrectForMatch(match, pick);
      rows.add(_MemberPickData(
        name: member.uiName,
        pick: pick,
        odds: odds,
        isCorrect: isCorrect,
        isStarted: isStarted,
      ));
    }
    return rows;
  }

  static bool _isMatchStarted(PredictionMatch match) {
    final s = match.statusShort;
    return s != null &&
        const {'1H', 'HT', '2H', 'ET', 'BT', 'LIVE', 'FT', 'AET', 'PEN'}
            .contains(s);
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
        bottom: false,
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
                            final outcome = scoreOutcomesByMatchId[match.id];
                            final breakdown = dayScore.matchBreakdowns
                                .cast<MatchScoreBreakdown?>()
                                .firstWhere(
                                  (b) => b?.matchId == match.id,
                                  orElse: () => null,
                                );
                            final expanded =
                                _locked && _expandedMatchId == match.id;
                            final memberRows =
                                expanded ? _buildMemberRows(match) : null;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _CompactMatchCard(
                                match: match,
                                pick: pick,
                                locked: _locked,
                                submitted: _submitted,
                                onPick: (p) => _setPick(match.id, p),
                                outcome: outcome,
                                matchBreakdown: breakdown,
                                expanded: expanded,
                                onToggleExpand: _locked
                                    ? () => _onToggleMatchExpand(match.id)
                                    : null,
                                memberRows: memberRows,
                              ),
                            );
                          }, childCount: matches.length),
                        ),
                      ),
                      if (standings.isNotEmpty)
                        SliverToBoxAdapter(
                          child: SerieAStandingsTable(standings: standings),
                        ),
                      const SliverPadding(padding: EdgeInsets.only(bottom: 90)),
                    ],
                  ),

                  // Layer 2: charcoal mask — hides cards at hero card center.
                  // Same colour as HomeShell bg so it's invisible.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: heroAreaHeight / 2,
                    child: const ColoredBox(color: CassandraColors.charcoal),
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
                        locked: _locked,
                        submitted: _submitted,
                        pickedCount: _pickedCount,
                        totalMatches: matches.length,
                        onSubmit: _onHeroSubmit,
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

/// Whether [pick] matches the current scoreline of [match].
bool isPickCorrectForMatch(PredictionMatch match, PickOption pick) {
  final h = match.homeGoals ?? 0;
  final a = match.awayGoals ?? 0;
  switch (pick) {
    case PickOption.home:
      return h > a;
    case PickOption.draw:
      return h == a;
    case PickOption.away:
      return a > h;
    case PickOption.homeDraw:
      return h >= a;
    case PickOption.drawAway:
      return a >= h;
    case PickOption.homeAway:
      return h != a;
    case PickOption.none:
      return false;
  }
}

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
    required this.locked,
    required this.submitted,
    required this.pickedCount,
    required this.totalMatches,
    this.onSubmit,
  });

  final DayScoreBreakdown dayScore;
  final List<PredictionMatch> matches;
  final Map<String, MatchOutcome> outcomesByMatchId;
  final PickOption Function(String) pickFor;
  final bool isMatchdayFinalized;
  final String bonusSigned;
  final bool isEnglish;
  final int matchdayNumber;
  final bool locked;
  final bool submitted;
  final int pickedCount;
  final int totalMatches;
  final VoidCallback? onSubmit;

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

  /// Max score: all picks correct + bonus(pickedCount).
  /// After submission, unpicked matches are locked as -max(1/X/2).
  /// Before submission, unpicked matches assume best possible pick.
  double _computeMaxScore() {
    double base = 0;
    int maxCorrect = 0;
    for (final m in matches) {
      final pick = pickFor(m.id);
      if (pick.isNone) {
        if (submitted) {
          // Submitted without pick → penalty is locked in.
          base -= _max1X2(m.odds);
        } else {
          // Not yet submitted → optimistic: could still pick correctly.
          base += _max1X2(m.odds);
          maxCorrect++;
        }
      } else {
        base += CassandraScoringEngine.oddsForPick(m, pick);
        maxCorrect++;
      }
    }
    return base + CassandraScoringEngine.bonusForCorrectCount(maxCorrect);
  }

  /// Min score: all picks wrong + bonus(0).
  /// After submission, unpicked matches are locked as -max(1/X/2).
  double _computeMinScore() {
    double base = 0;
    for (final m in matches) {
      final pick = pickFor(m.id);
      if (pick.isNone) {
        base -= _max1X2(m.odds);
      } else if (pick.isSingle) {
        base -= CassandraScoringEngine.oddsForPick(m, pick);
      } else {
        // Double chance wrong: lose sum of two component singles
        base -= CassandraScoringEngine.wrongDoublePenalty(m, pick);
      }
    }
    return base + CassandraScoringEngine.bonusForCorrectCount(0);
  }

  static double _max1X2(Odds o) {
    var m = o.home;
    if (o.draw > m) m = o.draw;
    if (o.away > m) m = o.away;
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final correctCount = dayScore.correctCount;
    final matchCount = matches.length;
    final totalPoints = isMatchdayFinalized ? formatOdds(dayScore.total) : '-';

    final segColors = _segmentColors();
    final segVoided = _segmentVoided();

    final matchdayTitle = isEnglish
        ? 'Matchday $matchdayNumber'
        : 'Giornata $matchdayNumber';

    // Pre-lock submit button state
    final bool allPicked = pickedCount >= totalMatches && totalMatches > 0;

    // Button colors
    const charcoalBg = Color(0xFF344A54);
    const mintLeaf = Color(0xFF00B884);
    const amaranth = Color(0xFFE01E48);

    Color submitBg;
    String submitLabel;
    if (submitted) {
      submitBg = amaranth;
      submitLabel = l10n.predictionsSubmittedButton;
    } else if (allPicked) {
      submitBg = mintLeaf;
      submitLabel = l10n.predictionsSubmitButton;
    } else {
      submitBg = charcoalBg;
      submitLabel = l10n.predictionsSubmitButton;
    }

    // ── Ring center widget ──────────────────────────────────────────
    Widget ringCenter;
    bool useSolidRing;

    if (locked) {
      // Post-lock: segmented ring + live points score
      useSolidRing = false;
      ringCenter = Center(
        child: Text(
          '$correctCount/$matchCount',
          style: const TextStyle(
            color: _fg,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    } else {
      // Pre-lock: solid ring + tappable submit button
      useSolidRing = true;
      ringCenter = Center(
        child: GestureDetector(
          onTap: submitted ? null : onSubmit,
          child: Container(
            width: 114,
            height: 114,
            decoration: BoxDecoration(
              color: submitBg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: CassandraColors.inkBlackV2.withValues(alpha: 0.50),
                  blurRadius: 6,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              submitLabel,
              style: const TextStyle(
                color: CassandraColors.brightSnow,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),
      );
    }

    // Both pre-lock and post-lock use same ring size and position.
    const ringSize = 126.0;

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
          // ── Left: title + ring with score/submit ──────────────────
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
                const SizedBox(height: 21),
                SizedBox(
                  width: ringSize,
                  height: ringSize,
                  child: CustomPaint(
                    painter: _RingPainter(
                      segmentColors: segColors,
                      segmentVoided: segVoided,
                      solid: useSolidRing,
                    ),
                    child: ringCenter,
                  ),
                ),
              ],
            ),
          ),

          // ── Right: breakdown (different pre-lock vs post-lock) ────
          Expanded(
            flex: 50,
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: locked
                  ? _buildPostLockBreakdown(
                      l10n, correctCount, matchCount, totalPoints,
                    )
                  : _buildPreLockBreakdown(l10n),
            ),
          ),
        ],
      ),
    );
  }

  static Color _valueColor(double value) {
    if (value > 0) return const Color(0xFF00B884); // mint leaf
    if (value < 0) return const Color(0xFFE01E48); // amaranth
    return _fg;
  }

  Widget _buildPostLockBreakdown(
    AppLocalizations l10n,
    int correctCount,
    int matchCount,
    String totalPoints,
  ) {
    final basePoints = dayScore.baseTotal;
    final bonusVal = dayScore.bonusPoints.toDouble();
    final totalVal = dayScore.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 4),
        // 1. "Punti" — live base score
        Text(
          isEnglish ? 'Points' : 'Punti',
          style: const TextStyle(
            color: _fg,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatOdds(basePoints),
          style: TextStyle(
            color: _valueColor(basePoints),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        // 2. "Punti bonus"
        Text(
          isEnglish ? 'Bonus points' : 'Punti bonus',
          style: const TextStyle(
            color: _fg,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          isMatchdayFinalized ? bonusSigned : '-',
          style: TextStyle(
            color: isMatchdayFinalized ? _valueColor(bonusVal) : _fg,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        // 3. "Punti totali"
        Text(
          isEnglish ? 'Total points' : 'Punti totali',
          style: const TextStyle(
            color: _fg,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          totalPoints,
          style: TextStyle(
            color: isMatchdayFinalized ? _valueColor(totalVal) : _fg,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildPreLockBreakdown(AppLocalizations l10n) {
    final maxScore = _computeMaxScore();
    final minScore = _computeMinScore();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 4),
        // 1. Picks made
        Text(
          l10n.predictionsPicksMade,
          style: const TextStyle(
            color: _fg,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$pickedCount/$totalMatches',
          style: const TextStyle(
            color: _fg,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        // 2. Max Points
        Text(
          l10n.predictionsMaxPoints,
          style: const TextStyle(
            color: _fg,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatOdds(maxScore),
          style: const TextStyle(
            color: _fg,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        // 3. Min Points
        Text(
          l10n.predictionsMinPoints,
          style: const TextStyle(
            color: _fg,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatOdds(minScore),
          style: const TextStyle(
            color: _fg,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flat 2D Ring Painter — two semicircles × 5 segments
// ─────────────────────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.segmentColors,
    required this.segmentVoided,
    this.solid = false,
  });

  final List<Color> segmentColors;
  final List<bool> segmentVoided;
  final bool solid;

  // Gap between each of the 10 segments (uniform).
  static const double _gapDeg = 2.5;
  static const double _gapRad = _gapDeg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const thickness = 19.0;
    final outerR = size.width / 2 * 1.10;
    final innerR = outerR - thickness;

    if (solid) {
      final path = Path()
        ..addOval(Rect.fromCircle(center: center, radius: outerR))
        ..addOval(Rect.fromCircle(center: center, radius: innerR));
      path.fillType = PathFillType.evenOdd;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = CassandraColors.brightSnow;
      canvas.drawPath(path, paint);
      return;
    }

    final count = segmentColors.length;
    if (count == 0) return;

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
        oldDelegate.segmentVoided != segmentVoided ||
        oldDelegate.solid != solid;
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
    this.submitted = false,
    required this.onPick,
    this.outcome,
    this.matchBreakdown,
    this.expanded = false,
    this.onToggleExpand,
    this.memberRows,
  });

  final PredictionMatch match;
  final PickOption pick;
  final bool locked;
  final bool submitted;
  final ValueChanged<PickOption> onPick;
  final MatchOutcome? outcome;
  final MatchScoreBreakdown? matchBreakdown;
  final bool expanded;
  final VoidCallback? onToggleExpand;
  final List<_MemberPickData>? memberRows;

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

    Widget card = Container(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            locked
                ? _buildPostLockLayout(homeInitial, awayInitial)
                : _buildPreMatchLayout(centerText, homeInitial, awayInitial),
            if (expanded) _buildMemberPicksOverlay(),
          ],
        ),
      ),
    );

    if (onToggleExpand != null) {
      card = GestureDetector(onTap: onToggleExpand, child: card);
    }

    return card;
  }

  Widget _buildMemberPicksOverlay() {
    final rows = memberRows;
    if (rows == null || rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(height: 1, color: CassandraColors.charcoal),
        const SizedBox(height: 8),
        for (final row in rows)
          _MemberPickRow(data: row),
      ],
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
        Container(height: 1, color: CassandraColors.charcoal),

        const SizedBox(height: 8),

        // ── All 6 odds on one row ──────────────────────────────────
        Row(
          children: [
            _CompactOddsButton(
              label: '1',
              odds: match.odds.home,
              selected: pick == PickOption.home,
              locked: locked || submitted,
              onPressed: () => onPick(PickOption.home),
            ),
            _CompactOddsButton(
              label: 'X',
              odds: match.odds.draw,
              selected: pick == PickOption.draw,
              locked: locked || submitted,
              onPressed: () => onPick(PickOption.draw),
            ),
            _CompactOddsButton(
              label: '2',
              odds: match.odds.away,
              selected: pick == PickOption.away,
              locked: locked || submitted,
              onPressed: () => onPick(PickOption.away),
            ),
            _CompactOddsButton(
              label: '1X',
              odds: match.odds.homeDraw,
              selected: pick == PickOption.homeDraw,
              locked: locked || submitted,
              onPressed: () => onPick(PickOption.homeDraw),
            ),
            _CompactOddsButton(
              label: 'X2',
              odds: match.odds.drawAway,
              selected: pick == PickOption.drawAway,
              locked: locked || submitted,
              onPressed: () => onPick(PickOption.drawAway),
            ),
            _CompactOddsButton(
              label: '12',
              odds: match.odds.homeAway,
              selected: pick == PickOption.homeAway,
              locked: locked || submitted,
              onPressed: () => onPick(PickOption.homeAway),
            ),
          ],
        ),
      ],
    );
  }

  /// Opposing pick label: single ↔ double chance complement.
  String _opposingPickLabel() {
    switch (pick) {
      case PickOption.home:
        return 'X2';
      case PickOption.draw:
        return '12';
      case PickOption.away:
        return '1X';
      case PickOption.homeDraw:
        return '2';
      case PickOption.drawAway:
        return '1';
      case PickOption.homeAway:
        return 'X';
      case PickOption.none:
        return '-';
    }
  }

  /// Whether the current live score matches the user's pick.
  bool get _isCurrentlyCorrect {
    final h = match.homeGoals ?? 0;
    final a = match.awayGoals ?? 0;
    switch (pick) {
      case PickOption.home:
        return h > a;
      case PickOption.draw:
        return h == a;
      case PickOption.away:
        return a > h;
      case PickOption.homeDraw:
        return h >= a;
      case PickOption.drawAway:
        return a >= h;
      case PickOption.homeAway:
        return h != a;
      case PickOption.none:
        return false;
    }
  }

  static const _mintLeaf = Color(0xFF00B884);
  static const _amaranth = Color(0xFFE01E48);

  /// Background for the played-odds bubble: mint leaf when correct.
  Color? get _playedBubbleBg {
    if (pick.isNone || !_isStarted) return null;
    return _isCurrentlyCorrect ? _mintLeaf : null;
  }

  /// Background for the opposing-odds bubble: amaranth when wrong.
  Color? get _opposingBubbleBg {
    if (pick.isNone || !_isStarted) return null;
    return _isCurrentlyCorrect ? null : _amaranth;
  }

  /// Post-lock: status | teams + score | 2 pick bubbles.
  Widget _buildPostLockLayout(String homeInitial, String awayInitial) {
    final hasPick = !pick.isNone;
    final kickoff = match.kickoff.toLocal();
    final dateStr =
        '${kickoff.day.toString().padLeft(2, '0')}/${kickoff.month.toString().padLeft(2, '0')}';
    final timeStr =
        '${kickoff.hour.toString().padLeft(2, '0')}:${kickoff.minute.toString().padLeft(2, '0')}';

    return Row(
      children: [
        // ── Left: date/time ────────────────────────────────────────
        SizedBox(
          width: 50,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: CassandraColors.inkBlackV2,
                ),
              ),
              Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: CassandraColors.inkBlackV2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),

        // ── Center: team rows with logos, names & scores ──────────────
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Home team row
              Row(
                children: [
                  _TeamLogo(
                    url: match.homeTeamLogo,
                    initial: homeInitial,
                    teamName: match.homeTeam,
                  ),
                  const SizedBox(width: 6),
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
                  if (_isStarted)
                    Padding(
                      padding: const EdgeInsets.only(right: 13),
                      child: Text(
                        '${match.homeGoals ?? 0}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: CassandraColors.inkBlackV2,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              // Away team row
              Row(
                children: [
                  _TeamLogo(
                    url: match.awayTeamLogo,
                    initial: awayInitial,
                    teamName: match.awayTeam,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      match.awayTeam,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: CassandraColors.inkBlackV2,
                      ),
                    ),
                  ),
                  if (_isStarted)
                    Padding(
                      padding: const EdgeInsets.only(right: 13),
                      child: Text(
                        '${match.awayGoals ?? 0}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: CassandraColors.inkBlackV2,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // ── Right: 2 pick bubbles (always reserve space) ─────────
        const SizedBox(width: 8),
        if (hasPick) ...[
          _PostLockPickBubble(
            label: pick.label,
            odds: _winOdds,
            bgColor: _playedBubbleBg,
          ),
          const SizedBox(width: 4),
          _PostLockPickBubble(
            label: _opposingPickLabel(),
            odds: _loseOdds,
            bgColor: _opposingBubbleBg,
          ),
        ] else
          const SizedBox(width: 114),
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
// Post-Lock Pick Bubble (non-interactive, snow white)
// ─────────────────────────────────────────────────────────────────────────────

class _PostLockPickBubble extends StatelessWidget {
  const _PostLockPickBubble({
    required this.label,
    required this.odds,
    this.bgColor,
  });

  final String label;
  final double odds;
  final Color? bgColor;

  @override
  Widget build(BuildContext context) {
    final isColored = bgColor != null;
    final bg = bgColor ?? CassandraColors.brightSnow;
    final fg = isColored
        ? CassandraColors.brightSnow
        : CassandraColors.inkBlackV2;
    return Container(
      width: 55,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: CassandraColors.inkBlackV2, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            formatOdds(odds),
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Member Pick Data + Row
// ─────────────────────────────────────────────────────────────────────────────

class _MemberPickData {
  final String name;
  final PickOption pick;
  final double odds;
  final bool isCorrect;
  final bool isStarted;

  const _MemberPickData({
    required this.name,
    required this.pick,
    required this.odds,
    required this.isCorrect,
    required this.isStarted,
  });
}

class _MemberPickRow extends StatelessWidget {
  const _MemberPickRow({required this.data});

  final _MemberPickData data;

  static const _mintLeaf = Color(0xFF00B884);
  static const _amaranth = Color(0xFFE01E48);

  @override
  Widget build(BuildContext context) {
    Color? bubbleBg;
    if (data.isStarted) {
      bubbleBg = data.isCorrect ? _mintLeaf : _amaranth;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              data.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CassandraColors.inkBlackV2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _PostLockPickBubble(
            label: data.pick.label,
            odds: data.odds,
            bgColor: bubbleBg,
          ),
        ],
      ),
    );
  }
}
