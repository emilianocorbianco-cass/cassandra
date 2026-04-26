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
import '../../services/firestore/models/picks_document.dart';
import '../badges/widgets/avatar_with_badges.dart';
import '../group/models/group_member.dart';
import '../leaderboards/models/matchday_data.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/models/score_breakdown.dart';
import '../scoring/ranking_rules.dart';
import '../scoring/scoring_engine.dart';
import 'models/formatters.dart';
import 'models/mock_prediction_data.dart';
import 'models/pick_option.dart';
import 'models/prediction_match.dart';
import 'predictions_history_page.dart';
import '../serie_a/live_standings_overlay.dart';
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
  String? _lastGroupId;

  // ── Multi-group submit: remember "send individually" choice per matchday ──
  static int? _individualSubmitMatchday;

  // ── Group leaderboard (post-lock) ──
  List<_LeaderboardEntry> _leaderboardEntries = const [];
  bool _leaderboardFetched = false;

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
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentGroupId = CassandraScope.of(context).activeGroupId;
    if (_lastGroupId != null && _lastGroupId != currentGroupId) {
      _memberPicksFetched = false;
      _cachedGroupMembers = null;
      _expandedMatchId = null;
      _leaderboardFetched = false;
      _leaderboardEntries = const [];
      // Reset submitted state — will re-check for the new group below.
      _submitted = false;
    }
    _lastGroupId = currentGroupId;

    // Restore submitted state from persisted picks history for current group.
    final scope = CassandraScope.of(context);
    if (!_submitted) {
      scope.ensureCurrentUserPicksHistoryLoaded();
      if (scope.hasSavedPicksForMatchday(_effectiveMatchdayNumber)) {
        _submitted = true;
      }
    }

    if (_didLoadRealFixtures) return;
    _didLoadRealFixtures = true;

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
    appState.ensureCurrentUserPicksHistoryLoaded();
    final dayPicks = appState.picksForCurrentUserForMatchday(
      _effectiveMatchdayNumber,
    );
    return dayPicks[matchId] ?? PickOption.none;
  }

  int get _pickedCount => matches.where((m) => !_pickFor(m.id).isNone).length;
  /// Matches that are still playable (not started) but have no pick.
  int get _playableMissingCount =>
      matches.where((m) => _pickFor(m.id).isNone && !_isMatchdayLocked).length;
  /// Lock = already submitted OR matchday lock time has passed.
  bool get _locked {
    final override = CassandraScope.of(context).debugLockOverride;
    if (override != null) return override;
    return _submitted || _isMatchdayLocked;
  }

  /// Whether the matchday is locked (15 minutes before the first kickoff).
  bool get _isMatchdayLocked {
    if (matches.isEmpty) return false;
    final firstKickoff = matches
        .map((m) => m.kickoff)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return CassandraScope.of(context)
        .now()
        .isAfter(firstKickoff.subtract(const Duration(minutes: 15)));
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
    if (match != null && _isMatchdayLocked) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.predictionsPickLockedSnack)));
      return;
    }
    final currentPick = _pickFor(matchId);
    final effectivePick = currentPick == pick ? PickOption.none : pick;
    setState(() => _picks[matchId] = effectivePick);
    CassandraScope.of(context).setCurrentUserPick(matchId, effectivePick);
  }

  void _onHeroSubmit() {
    if (_submitted) return;
    if (_playableMissingCount > 0) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.predictionsMissingConfirm(_playableMissingCount),
          ),
        ),
      );
      return;
    }
    final appState = CassandraScope.of(context);
    final groupIds = appState.firestoreGroupIds;
    if (groupIds.length > 1 &&
        _individualSubmitMatchday != _effectiveMatchdayNumber) {
      _showMultiGroupDialog();
    } else {
      _submit(VisibilityChoice.public).then((ok) {
        if (mounted && ok) setState(() => _submitted = true);
      });
    }
  }

  Future<void> _showMultiGroupDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CassandraColors.inkBlack,
        title: Text(
          l10n.submitMultiGroupTitle,
          style: const TextStyle(color: CassandraColors.brightSnow),
        ),
        content: Text(
          l10n.submitMultiGroupBody,
          style: const TextStyle(color: CassandraColors.brightSnow),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              l10n.submitMultiGroupSingle,
              style: const TextStyle(color: CassandraColors.brightSnow),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: CassandraColors.primary,
            ),
            child: Text(l10n.submitMultiGroupAll),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    if (result) {
      await _submitToAllGroups();
    } else {
      _individualSubmitMatchday = _effectiveMatchdayNumber;
      final ok = await _submit(VisibilityChoice.public);
      if (mounted && ok) setState(() => _submitted = true);
    }
  }

  Future<void> _submitToAllGroups() async {
    final appState = CassandraScope.of(context);
    final groupIds = List<String>.from(appState.firestoreGroupIds);

    // Capture picks and state BEFORE any async work — setActiveGroupId would
    // clear them, so we avoid switching the active group altogether.
    appState.ensureCurrentUserPicksLoaded();
    appState.ensureCurrentUserPicksHistoryLoaded();
    appState.ensureMatchdayMatchesLoaded();
    appState.ensureOutcomesHistoryLoaded();

    final dayNumber = _effectiveMatchdayNumber;
    final currentMatches = List<PredictionMatch>.of(matches);
    final allPicks = <String, PickOption>{
      for (final m in currentMatches)
        if (!_pickFor(m.id).isNone) m.id: _pickFor(m.id),
    };

    // Save local state once (shared across groups).
    appState.saveCurrentUserPicksHistory(
      dayNumber: dayNumber,
      picksByMatchId: allPicks,
    );
    await appState.saveMatchdayMatchesSnapshot(
      matchdayNumber: dayNumber,
      matches: currentMatches,
    );
    appState.ensureMatchesHistoryLoaded();
    appState.saveMatchesHistory(
      matchdayNumber: dayNumber,
      matches: currentMatches,
    );
    final outcomesNow = <String, MatchOutcome>{
      for (final e in appState.effectivePredictionOutcomesByMatchId.entries)
        e.key: e.value,
    };
    if (outcomesNow.isNotEmpty) {
      appState.saveOutcomesHistory(
        dayNumber: dayNumber,
        outcomesByMatchId: outcomesNow,
      );
    }
    DayScoreBreakdown? scoreCache;
    if (outcomesNow.isNotEmpty) {
      scoreCache = appState.scoringRules.scoreRound(
        matches: currentMatches,
        picksByMatchId: allPicks,
        outcomesByMatchId: outcomesNow,
      );
    }

    // Submit to each group using targetGroupId — no active-group switch needed.
    var allOk = true;
    for (final groupId in groupIds) {
      final ok = await appState.submitPicksToFirestore(
        dayNumber: dayNumber,
        picksByMatchId: allPicks,
        visibility: 'public',
        score: scoreCache,
        targetGroupId: groupId,
      );
      if (!ok) allOk = false;
    }
    if (!mounted) return;
    if (allOk) {
      final l10n = AppLocalizations.of(context)!;
      setState(() => _submitted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.predictionsSlipSubmitted(
            l10n.predictionsVisibilityPublic,
          )),
        ),
      );
    } else {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.predictionsSlipSubmitFailed)),
      );
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

  Future<bool> _submit(VisibilityChoice visibility) async {
    final l10n = AppLocalizations.of(context)!;
    if (_submitted) return false;
    final playableMissing = _playableMissingCount;
    if (playableMissing > 0) {
      final ok = await _confirmSubmitIfMissing(playableMissing);
      if (!ok) return false;
      if (!mounted) return false;
    }
    if (!mounted) return false;
    final appState = CassandraScope.of(context);
    appState.ensureCurrentUserPicksLoaded();
    appState.ensureCurrentUserPicksHistoryLoaded();
    appState.ensureMatchdayMatchesLoaded();
    appState.ensureOutcomesHistoryLoaded();

    // Build the complete picks map from appState (which accumulates picks
    // across widget lifecycles) instead of the local _picks map, which
    // resets to {} every time the widget is recreated (e.g. tab switch).
    final allPicks = <String, PickOption>{
      for (final m in matches)
        if (!_pickFor(m.id).isNone) m.id: _pickFor(m.id),
    };

    appState.saveCurrentUserPicksHistory(
      dayNumber: _effectiveMatchdayNumber,
      picksByMatchId: allPicks,
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
      scoreCache = appState.scoringRules.scoreRound(
        matches: matches,
        picksByMatchId: allPicks,
        outcomesByMatchId: outcomesNow,
      );
    }
    final visLabel = visibility == VisibilityChoice.public
        ? 'public'
        : 'private';
    final submitted = await appState.submitPicksToFirestore(
      dayNumber: _effectiveMatchdayNumber,
      picksByMatchId: allPicks,
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
        final demoNow = scope.now();
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

      final now = appState.now();
      final cursorDay = appState.cassandraMatchdayCursor;
      appState.ensureOriginKickoffsLoaded();

      // Trust the cursor — it was already corrected by API-Football in
      // home_shell. Fetch exactly this day from Firestore.
      final resolvedDoc = await fs.getMatchdayData(
        seasonKey: appState.currentSeasonKey,
        dayNumber: cursorDay,
      );

      await appState.persistOriginKickoffs();

      MatchdayProgress? resolvedProgress;

      // Use Firestore data if available; otherwise use cached matches
      // (home_shell may have already fetched from API and cached them).
      final mList = (resolvedDoc != null && resolvedDoc.matches.isNotEmpty)
          ? resolvedDoc.matches
          : appState.cachedPredictionMatches;
      final outcomes = (resolvedDoc != null && resolvedDoc.matches.isNotEmpty)
          ? resolvedDoc.outcomesByMatchId
          : appState.effectivePredictionOutcomesByMatchId;

      if (mList != null && mList.isNotEmpty) {
        for (final m in mList) {
          appState.registerOriginKickoff(matchId: m.id, kickoff: m.kickoff);
        }

        String statusFor(PredictionMatch m) =>
            (outcomes[m.id] ?? MatchOutcome.pending).isGraded ? 'FT' : 'NS';
        resolvedProgress = computeMatchdayProgress<PredictionMatch>(
          mList,
          now: now,
          kickoff: (m) => m.kickoff,
          originKickoff: (m) => appState.originKickoffFor(
            matchId: m.id,
            fallbackKickoff: m.kickoff,
          ),
          statusShort: (m) => statusFor(m),
        );
      }

      if (mList == null || mList.isEmpty || resolvedProgress == null) {
        if (kDebugMode) {
          debugPrint('[fixtures] no data for cursor day=$cursorDay');
        }
        if (mounted) {
          setState(() {
            _shownMatchdayNumber = cursorDay;
          });
        }
        return;
      }

      final resolvedDayNumber = cursorDay;
      appState.setMatchdayProgress(
        matchdayNumber: resolvedDayNumber,
        progress: resolvedProgress,
        allowAutoAdvance: false,
      );

      if (!mounted) return;
      final displayDay = appState.cassandraMatchdayCursor;
      setState(() {
        _shownMatchdayNumber = displayDay;
        _matches = mList;
        _usingRealFixtures = true;
      });
      scope.setCachedPredictionMatches(
        mList,
        isReal: true,
        updatedAt: resolvedDoc?.updatedAt ?? DateTime.now(),
      );
      scope.setCachedPredictionOutcomesByMatchId(outcomes);
      appState.setRecentMatchdayDataBulk(
        matchesByMatchday: {cursorDay: mList},
        outcomesByMatchday: {cursorDay: outcomes},
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[fixtures] load failed: $e');
        debugPrint('$st');
      }
      if (mounted) {
        final fallbackAppState = CassandraScope.of(context);
        setState(() {
          _shownMatchdayNumber = fallbackAppState.uiMatchdayNumber;
        });
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
    final s = match.statusShort;
    final isLive =
        s != null && const {'1H', 'HT', '2H', 'ET', 'BT', 'LIVE'}.contains(s);
    final isFT = s == 'FT' || s == 'AET' || s == 'PEN';
    final isStarted = isLive || isFT;
    final matchLocked = _isMatchdayLocked;
    final rows = <_MemberPickData>[];
    for (final member in members) {
      if (member.id == currentUid) continue;
      final memberPicks = allPicks[member.id];
      var pick = memberPicks?[match.id] ?? PickOption.none;
      final isAuto = pick.isNone;
      if (!matchLocked && isAuto) {
        // Pre-lock: member hasn't submitted — show "Non inviato"
        rows.add(_MemberPickData(
          name: member.uiName,
          pick: PickOption.none,
          odds: 0,
          opposingLabel: '',
          opposingOdds: 0,
          isCorrect: false,
          isLive: false,
          isFT: false,
          hidden: true,
        ));
        continue;
      }
      if (isAuto) {
        pick = CassandraScoringEngine.lowestOddsPick(match);
      }
      final odds = CassandraScoringEngine.oddsForPick(match, pick);
      final isCorrect = isStarted && isPickCorrectForMatch(match, pick);
      rows.add(
        _MemberPickData(
          name: member.uiName,
          pick: pick,
          odds: odds,
          opposingLabel: _opposingLabelFor(pick),
          opposingOdds: _loseOddsFor(match, pick),
          isCorrect: isCorrect,
          isLive: isLive,
          isFT: isFT,
          isAuto: matchLocked && isAuto,
        ),
      );
    }
    return rows;
  }

  static String _opposingLabelFor(PickOption pick) {
    return pick.label;
  }

  static double _loseOddsFor(PredictionMatch match, PickOption pick) {
    return 0;
  }

  void _fetchGroupLeaderboardIfNeeded() {
    if (_leaderboardFetched) return;
    final appState = CassandraScope.of(context);
    if (!_locked || !appState.hasGroup) return;
    _leaderboardFetched = true;

    final fs = appState.firestoreService;
    if (fs == null) return;

    final seasonKey = appState.currentSeasonKey;
    final groupId = appState.activeGroupId;
    if (groupId == null) return;

    final currentMatchdayNumber = _effectiveMatchdayNumber;
    final currentMatches = matches
        .where((m) {
          final origin = appState.originKickoffFor(
            matchId: m.id,
            fallbackKickoff: m.kickoff,
          );
          return m.kickoff.difference(origin) <= const Duration(hours: 48);
        })
        .toList(growable: false);
    // Base outcomes from Firestore cache
    final baseOutcomes = <String, MatchOutcome>{
      for (final m in currentMatches)
        if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
          m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
    };
    // Live overrides: derive outcome from live homeGoals/awayGoals
    const liveStatuses = {
      '1H',
      'HT',
      '2H',
      'ET',
      'BT',
      'LIVE',
      'FT',
      'AET',
      'PEN',
    };
    final liveOverrides = <String, MatchOutcome>{
      for (final m in currentMatches)
        if (liveStatuses.contains(m.statusShort) &&
            m.homeGoals != null &&
            m.awayGoals != null)
          m.id: m.homeGoals! > m.awayGoals!
              ? MatchOutcome.home
              : m.homeGoals! < m.awayGoals!
              ? MatchOutcome.away
              : MatchOutcome.draw,
    };
    final effectiveOutcomesByMatchId = <String, MatchOutcome>{
      ...baseOutcomes,
      ...liveOverrides,
    };

    appState
        .fetchFirestoreGroupMembers()
        .then((members) async {
          if (!mounted) return;
          final seasonDocs = await fs.getPicksForSeason(
            seasonKey: seasonKey,
            groupId: groupId,
          );
          if (!mounted) return;

          final memberIdSet = members.map((m) => m.id).toSet();
          final filteredDocs = seasonDocs
              .where((d) => memberIdSet.contains(d.uid))
              .toList(growable: false);
          final seasonPicksByMemberId = <String, List<PicksDocument>>{};
          for (final doc in filteredDocs) {
            seasonPicksByMemberId
                .putIfAbsent(doc.uid, () => <PicksDocument>[])
                .add(doc);
          }

          appState.ensureMatchdayMatchesLoaded();
          final seasonDaySet = <int>{
            ...appState.currentUserPicksByMatchday.keys,
            ...appState.matchesByMatchday.keys,
            ...appState.recentMatchesByMatchday.keys,
            ...appState.outcomesByMatchday.keys,
            for (final docs in seasonPicksByMemberId.values)
              for (final pd in docs)
                if (pd.dayNumber > 0) pd.dayNumber,
          };
          final seasonDays = seasonDaySet.toList()..sort();
          final seasonMatchdayByDay = <int, MatchdayData>{};
          for (final day in seasonDays) {
            final savedMatches = appState.matchesByMatchday[day];
            final recentMatches = appState.recentMatchesByMatchday[day];
            final matchesForDay =
                (savedMatches != null && savedMatches.isNotEmpty)
                ? savedMatches
                : (recentMatches ?? const <PredictionMatch>[]);
            final savedOutcomes = appState.outcomesByMatchday[day];
            final recentOutcomes = appState.recentOutcomesByMatchday[day];
            final outcomesForDay = <String, MatchOutcome>{
              if (recentOutcomes != null) ...recentOutcomes,
              if (savedOutcomes != null) ...savedOutcomes,
            };
            seasonMatchdayByDay[day] = MatchdayData(
              dayNumber: day,
              matches: matchesForDay,
              outcomesByMatchId: outcomesForDay,
            );
          }

          final entries = members.map((member) {
            final docs =
                seasonPicksByMemberId[member.id] ?? const <PicksDocument>[];
            var totalPoints = 0.0;
            final avgOddsValues = <double>[];

            for (final pd in docs) {
              if (pd.dayNumber == currentMatchdayNumber) continue;
              // Prefer server-side score; fall back to client recompute.
              final score = pd.score;
              if (score != null) {
                totalPoints += score.total;
                if (score.averageOddsPlayed != null) {
                  avgOddsValues.add(score.averageOddsPlayed!);
                }
              } else {
                final md = seasonMatchdayByDay[pd.dayNumber];
                if (md != null && md.matches.isNotEmpty) {
                  final dayScore = appState.scoringRules.scoreRound(
                    matches: md.matches,
                    picksByMatchId: pd.picksByMatchId,
                    outcomesByMatchId: md.outcomesByMatchId,
                  );
                  totalPoints += dayScore.total;
                  if (dayScore.averageOddsPlayed != null) {
                    avgOddsValues.add(dayScore.averageOddsPlayed!);
                  }
                }
              }
            }

            // Current matchday picks for this member
            final currentDoc = docs.cast<PicksDocument?>().firstWhere(
              (d) => d?.dayNumber == currentMatchdayNumber,
              orElse: () => null,
            );
            final firestorePicks =
                currentDoc?.picksByMatchId ?? const <String, PickOption>{};
            // For the current user, fall back to local picks if Firestore
            // doesn't have them yet (pre-submit state).
            final Map<String, PickOption> currentPicks;
            if (firestorePicks.isNotEmpty) {
              currentPicks = firestorePicks;
            } else if (member.id == appState.profile.id) {
              final localPicks =
                  appState.hasSavedPicksForMatchday(currentMatchdayNumber)
                  ? appState.currentUserPicksForMatchday(currentMatchdayNumber)
                  : appState.currentUserPicksByMatchId;
              currentPicks = localPicks.isNotEmpty
                  ? localPicks
                  : firestorePicks;
            } else {
              currentPicks = firestorePicks;
            }
            // Prefer server-side score (computed by Cloud Function every
            // minute). Only fall back to client-side calculation when the
            // server hasn't scored this document yet (just submitted).
            if (currentDoc?.score != null) {
              totalPoints += currentDoc!.score!.total;
              if (currentDoc.score!.averageOddsPlayed != null) {
                avgOddsValues.add(currentDoc.score!.averageOddsPlayed!);
              }
            } else if (effectiveOutcomesByMatchId.isNotEmpty) {
              final currentDayScore = appState.scoringRules.scoreRound(
                matches: currentMatches,
                picksByMatchId: currentPicks,
                outcomesByMatchId: effectiveOutcomesByMatchId,
              );
              totalPoints += currentDayScore.total;
              if (currentDayScore.averageOddsPlayed != null) {
                avgOddsValues.add(currentDayScore.averageOddsPlayed!);
              }
            }

            final avgOdds = avgOddsValues.isEmpty
                ? null
                : avgOddsValues.reduce((a, b) => a + b) / avgOddsValues.length;

            return _LeaderboardEntry(
              member: member,
              totalPoints: totalPoints,
              averageOddsPlayed: avgOdds,
            );
          }).toList();

          entries.sort(
            (a, b) => compareCassandraRanking(
              aTotal: a.totalPoints,
              bTotal: b.totalPoints,
              aAverageOddsPlayed: a.averageOddsPlayed,
              bAverageOddsPlayed: b.averageOddsPlayed,
              aTeamName: a.member.teamName,
              bTeamName: b.member.teamName,
            ),
          );

          if (!mounted) return;
          setState(() => _leaderboardEntries = entries);
        })
        .catchError((Object e) {
          if (kDebugMode) {
            debugPrint('[predictions] leaderboard fetch failed: $e');
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _fetchGroupLeaderboardIfNeeded();

    final appState = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isEnglish = l10n.localeName.startsWith('en');
    final usingRealFixturesNow =
        _usingRealFixtures || appState.cachedPredictionMatchesAreReal;
    final standings = computeLiveStandings(
      appState.cachedSeasonStandings,
      appState.cachedPredictionMatches ?? const [],
    );

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

    const liveStatuses = {'1H', 'HT', '2H', 'ET', 'BT', 'LIVE'};
    final scoreOutcomesByMatchId = <String, MatchOutcome>{
      for (final m in scoringMatches)
        if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
          m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
      // Live overrides: provisional outcome from current score.
      for (final m in scoringMatches)
        if (liveStatuses.contains(m.statusShort) &&
            m.homeGoals != null &&
            m.awayGoals != null)
          m.id: m.homeGoals! > m.awayGoals!
              ? MatchOutcome.home
              : m.homeGoals! < m.awayGoals!
              ? MatchOutcome.away
              : MatchOutcome.draw,
    };
    final DayScoreBreakdown dayScore = appState.scoringRules.scoreRound(
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

    // Hero card height: includes outer padding and a bit of extra room
    // to avoid bottom overflow on compact devices.
    const heroAreaHeight = 224.0;

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
                        child: SizedBox(height: heroAreaHeight + 14),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
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
                            final memberRows = expanded
                                ? _buildMemberRows(match)
                                : null;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 18),
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
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            children: [
                              const Divider(height: 1, thickness: 1),
                              const SizedBox(height: 18),
                              if (!_locked && standings.isNotEmpty)
                                SerieAStandingsTable(standings: standings),
                              if (_locked && _leaderboardEntries.isNotEmpty)
                                _GroupLeaderboardSection(
                                  entries: _leaderboardEntries,
                                ),
                            ],
                          ),
                        ),
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
                    left: 18,
                    right: 18,
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

class _HeroScoreCard extends StatefulWidget {
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

  @override
  State<_HeroScoreCard> createState() => _HeroScoreCardState();
}

class _HeroScoreCardState extends State<_HeroScoreCard>
    with SingleTickerProviderStateMixin {
  static const _fg = CassandraColors.brightSnow;
  static const _cardHeight = 216.0;
  static const _flipDuration = Duration(milliseconds: 810);

  late final AnimationController _flipController = AnimationController(
    vsync: this,
    duration: _flipDuration,
  );
  late final CurvedAnimation _flipAnimation = CurvedAnimation(
    parent: _flipController,
    curve: Curves.easeInOutCubic,
  );

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _toggleCardFace() {
    if (_flipController.isAnimating) return;
    if (_flipController.value >= 0.5) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
  }

  List<Color> _segmentColors() {
    const liveStatuses = {'1H', 'HT', '2H', 'ET', 'BT', 'LIVE'};
    return widget.matches.map((m) {
      final outcome = widget.outcomesByMatchId[m.id];
      final isPending = outcome == null || outcome.isPending;
      final isVoided = outcome?.isVoided ?? false;
      if (isVoided) return Colors.transparent;
      if (isPending) {
        // Derive provisional outcome from live goals for inner-border coloring.
        final s = m.statusShort;
        if (s != null &&
            liveStatuses.contains(s) &&
            m.homeGoals != null &&
            m.awayGoals != null) {
          final liveOutcome = m.homeGoals! > m.awayGoals!
              ? MatchOutcome.home
              : m.homeGoals! < m.awayGoals!
              ? MatchOutcome.away
              : MatchOutcome.draw;
          final pick = widget.pickFor(m.id);
          final correct = _isPickCorrect(pick, liveOutcome);
          return correct ? CassandraColors.mintLeaf : CassandraColors.primary;
        }
        return CassandraColors.charcoal;
      }
      final pick = widget.pickFor(m.id);
      final correct = _isPickCorrect(pick, outcome);
      return correct ? CassandraColors.mintLeaf : CassandraColors.primary;
    }).toList();
  }

  List<bool> _segmentVoided() {
    return widget.matches.map((m) {
      final outcome = widget.outcomesByMatchId[m.id];
      return outcome?.isVoided ?? false;
    }).toList();
  }

  List<bool> _segmentLive() {
    return widget.matches.map((m) {
      final s = m.statusShort;
      return s != null &&
          const {'1H', 'HT', '2H', 'ET', 'BT', 'LIVE'}.contains(s);
    }).toList();
  }

  /// Max score: all picks correct + best bonus.
  /// Before submission, unpicked matches assume best possible pick.
  double _computeMaxScore() {
    double base = 0;
    double maxWinningOddsSum = 0;
    int maxCorrectCount = 0;
    for (final m in widget.matches) {
      final pick = widget.pickFor(m.id);
      if (pick.isNone) {
        if (!widget.submitted) {
          base += _max1X2(m.odds);
          maxWinningOddsSum += _max1X2(m.odds);
          maxCorrectCount++;
        }
      } else {
        final odds = CassandraScoringEngine.oddsForPick(m, pick);
        base += odds;
        maxWinningOddsSum += odds;
        maxCorrectCount++;
      }
    }
    return base +
        CassandraScoringEngine.bonusForCombinedScore(
          maxWinningOddsSum + maxCorrectCount,
        );
  }

  /// Min score: all picks wrong → 0 base + worst bonus.
  double _computeMinScore() {
    return CassandraScoringEngine.bonusForCombinedScore(0).toDouble();
  }

  static double _max1X2(Odds o) {
    var m = o.home;
    if (o.draw > m) m = o.draw;
    if (o.away > m) m = o.away;
    return m;
  }

  String _flipButtonTooltip() {
    if (_flipController.value >= 0.5) {
      return widget.isEnglish ? 'Back to score' : 'Torna al punteggio';
    }
    return widget.isEnglish ? 'Show bonus rules' : 'Mostra regole bonus';
  }

  String _bonusRulesTitle() {
    return widget.isEnglish ? 'Bonus points' : 'Calcolo punti bonus';
  }

  String _bonusPointsLabel(int points) {
    final abs = points.abs();
    final suffix = abs == 1
        ? (widget.isEnglish ? 'point' : 'punto')
        : (widget.isEnglish ? 'points' : 'punti');
    if (points < 0) return '-$abs $suffix';
    return '$abs $suffix';
  }

  List<({String range, int points})> _bonusRuleRows() {
    return const [
      (range: '> 30', points: 10),
      (range: '26 - 30', points: 7),
      (range: '22 - 26', points: 4),
      (range: '18 - 22', points: 1),
      (range: '15 - 18', points: 0),
      (range: '12 - 15', points: -1),
      (range: '9 - 12', points: -4),
      (range: '< 9', points: -7),
    ];
  }

  Widget _buildCardShell({required Widget child}) {
    // Cap text scaling so the hero card never overflows on Android devices
    // with large system font size.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(
          maxScaleFactor: 1.0,
        ),
      ),
      child: Container(
        height: _cardHeight,
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: child,
            ),
            Positioned(
              top: -14,
              right: -2,
              child: _HeroCardFlipButton(
                tooltip: _flipButtonTooltip(),
                onTap: _toggleCardFace,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrontFace(AppLocalizations l10n) {
    final correctCount = widget.dayScore.correctCount;
    final matchCount = widget.matches.length;
    final totalPoints = formatOdds(widget.dayScore.total);

    final segColors = _segmentColors();
    final segVoided = _segmentVoided();
    final segLive = _segmentLive();

    final matchdayTitle = widget.isEnglish
        ? 'Matchday ${widget.matchdayNumber}'
        : 'Giornata ${widget.matchdayNumber}';

    final bool allPicked =
        widget.pickedCount >= widget.totalMatches && widget.totalMatches > 0;

    const charcoalBg = Color(0xFF344A54);
    const mintLeaf = Color(0xFF00B884);
    const amaranth = Color(0xFFE01E48);

    Color submitBg;
    String submitLabel;
    if (widget.submitted) {
      submitBg = amaranth;
      submitLabel = l10n.predictionsSubmittedButton;
    } else if (allPicked) {
      submitBg = mintLeaf;
      submitLabel = l10n.predictionsSubmitButton;
    } else {
      submitBg = charcoalBg;
      submitLabel = l10n.predictionsSubmitButton;
    }

    Widget ringCenter;
    bool useSolidRing;

    if (widget.locked) {
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
      useSolidRing = true;
      ringCenter = Center(
        child: GestureDetector(
          onTap: widget.submitted ? null : widget.onSubmit,
          child: Container(
            width: 92,
            height: 92,
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
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),
      );
    }

    const ringSize = 104.0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 50,
            child: Transform.translate(
              offset: const Offset(0, -4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    matchdayTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                    color: _fg,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 28),
                Transform.translate(
                  offset: const Offset(0, -8),
                  child: Center(
                    child: SizedBox(
                      width: ringSize,
                      height: ringSize,
                      child: CustomPaint(
                        painter: _RingPainter(
                          segmentColors: segColors,
                          segmentVoided: segVoided,
                          segmentLive: segLive,
                          solid: useSolidRing,
                        ),
                        child: ringCenter,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
          Container(
            width: 0.5,
            color: CassandraColors.brightSnow,
          ),
          Expanded(
            flex: 50,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 0, 20, 0),
              child: widget.locked
                  ? _buildPostLockBreakdown(
                      l10n,
                      correctCount,
                      matchCount,
                      totalPoints,
                    )
                  : _buildPreLockBreakdown(l10n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackFace() {
    final rules = _bonusRuleRows();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _bonusRulesTitle(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _fg,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rowHeight = constraints.maxHeight / rules.length;
              // Labels aligned to rows 2, 3, 4 (12-15, 15-18, 18-22).
              const labelStyle = TextStyle(
                color: _fg,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                height: 1.0,
              );
              const textH = 12.0; // approx text height at fontSize 12
              double rowCenter(int i) =>
                  rowHeight * i + rowHeight / 2 - textH / 2;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 156,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 2,
                          bottom: 2,
                          right: 0,
                          child: SizedBox(
                            width: 14,
                            child: CustomPaint(
                              painter: _HeroBonusBracketPainter(
                                color: _fg.withValues(alpha: 0.78),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 20,
                          top: rowCenter(2),
                          child: Text(
                            widget.isEnglish
                                ? 'Winning odds'
                                : 'Quote vincenti',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            softWrap: false,
                            style: labelStyle,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 20,
                          top: rowCenter(3),
                          child: const Text(
                            '+',
                            textAlign: TextAlign.center,
                            style: labelStyle,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 20,
                          top: rowCenter(4),
                          child: Text(
                            widget.isEnglish
                                ? 'Correct picks'
                                : 'Pronostici corretti',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            softWrap: false,
                            style: labelStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: rules.map((rule) {
                        final pointsColor = rule.points > 0
                            ? CassandraColors.mintLeaf
                            : rule.points < 0
                            ? CassandraColors.primary
                            : _fg;
                        return Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text(
                                rule.range,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _fg,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 5,
                              child: Text(
                                _bonusPointsLabel(rule.points),
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: pointsColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: _cardHeight,
      child: AnimatedBuilder(
        animation: _flipAnimation,
        builder: (context, child) {
          final angle = _flipAnimation.value * math.pi;
          final showFront = angle <= math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0016)
              ..rotateX(angle),
            child: showFront
                ? _buildCardShell(child: _buildFrontFace(l10n))
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateX(math.pi),
                    child: _buildCardShell(child: _buildBackFace()),
                  ),
          );
        },
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
    final basePoints = widget.dayScore.baseTotal;
    final bonusVal = widget.dayScore.bonusPoints.toDouble();
    final totalVal = widget.dayScore.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 1. "Punti" — live base score
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isEnglish ? 'Points' : 'Punti',
              style: const TextStyle(
                color: _fg,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                height: 1.1,
              ),
            ),
            Text(
              formatOdds(basePoints),
              style: TextStyle(
                color: _valueColor(basePoints),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 2. "Punti bonus"
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isEnglish ? 'Bonus points' : 'Punti bonus',
              style: const TextStyle(
                color: _fg,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                height: 1.1,
              ),
            ),
            Text(
              widget.bonusSigned,
              style: TextStyle(
                color: _valueColor(bonusVal),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 3. "Punti totali"
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isEnglish ? 'Total points' : 'Punti totali',
              style: const TextStyle(
                color: _fg,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                height: 1.1,
              ),
            ),
            Text(
              totalPoints,
              style: TextStyle(
                color: _valueColor(totalVal),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ],
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
        // 1. Picks made
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.predictionsPicksMade,
              style: const TextStyle(
                color: _fg,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                height: 1.1,
              ),
            ),
            Text(
              '${widget.pickedCount}/${widget.totalMatches}',
              style: const TextStyle(
                color: _fg,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 2. Max Points
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.predictionsMaxPoints,
              style: const TextStyle(
                color: _fg,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                height: 1.1,
              ),
            ),
            Text(
              formatOdds(maxScore),
              style: const TextStyle(
                color: _fg,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 3. Min Points
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.predictionsMinPoints,
              style: const TextStyle(
                color: _fg,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                height: 1.1,
              ),
            ),
            Text(
              formatOdds(minScore),
              style: const TextStyle(
                color: _fg,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroCardFlipButton extends StatelessWidget {
  const _HeroCardFlipButton({required this.tooltip, required this.onTap});

  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Text(
              '\u24D8',
              style: TextStyle(
                color: CassandraColors.brightSnow,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroBonusBracketPainter extends CustomPainter {
  const _HeroBonusBracketPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.92, 0)
      ..lineTo(size.width * 0.24, 0)
      ..lineTo(size.width * 0.24, size.height)
      ..lineTo(size.width * 0.92, size.height);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeroBonusBracketPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flat 2D Ring Painter — two semicircles × 5 segments
// ─────────────────────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.segmentColors,
    required this.segmentVoided,
    required this.segmentLive,
    this.solid = false,
  });

  final List<Color> segmentColors;
  final List<bool> segmentVoided;
  final List<bool> segmentLive;
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
        : CassandraColors.charcoal;
    final isLive = index < segmentLive.length && segmentLive[index];
    final isColored =
        baseColor != CassandraColors.charcoal &&
        baseColor != Colors.transparent;

    if (isLive && isColored) {
      // Live match with provisional result: fill bright snow, stroke all edges.
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = CassandraColors.brightSnow;
      canvas.drawPath(path, fillPaint);

      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = baseColor;
      canvas.drawPath(path, borderPaint);
      return;
    }

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
        oldDelegate.segmentLive != segmentLive ||
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
        for (final row in rows) _MemberPickRow(data: row),
      ],
    );
  }

  /// Pre-match: teams row + 3 odds buttons (1/X/2).
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
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
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
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
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

        // ── 1 / X / 2 odds buttons ──────────────────────────────────
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
          ],
        ),
      ],
    );
  }

  /// Opposing pick label: single ↔ double chance complement.
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

  /// Single bubble background — solid fill only at FT.
  Color? get _pickBubbleBg {
    if (pick.isNone || !_isFT) return null;
    return _isCurrentlyCorrect ? _mintLeaf : _amaranth;
  }

  /// Single bubble border — colored outline while live.
  Color? get _pickBubbleBorder {
    if (pick.isNone || !_isLive) return null;
    return _isCurrentlyCorrect ? _mintLeaf : _amaranth;
  }

  /// Post-lock: status | teams + score | 2 pick bubbles.
  Widget _buildPostLockLayout(String homeInitial, String awayInitial) {
    final hasPick = !pick.isNone;

    return Row(
      children: [
        // ── Left: date/time or live status ────────────────────────
        _MatchStatusColumn(match: match),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
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

        // ── Right: single pick bubble ──────────────────────────────
        const SizedBox(width: 8),
        if (hasPick)
          _PostLockPickBubble(
            label: pick.label,
            odds: _winOdds,
            bgColor: _pickBubbleBg,
            borderColor: _pickBubbleBorder,
            large: true,
          )
        else
          const SizedBox(width: 68),
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
                  fontSize: 11,
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
    this.borderColor,
    this.large = false,
  });

  final String label;
  final double odds;
  final Color? bgColor;
  final Color? borderColor;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final hasFill = bgColor != null;
    final bg = bgColor ?? CassandraColors.brightSnow;
    final border = borderColor ?? CassandraColors.inkBlackV2;
    final fg = hasFill
        ? CassandraColors.brightSnow
        : CassandraColors.inkBlackV2;
    final w = large ? 68.0 : 55.0;
    final fontSize = large ? 15.0 : 12.0;
    final hPad = large ? 10.0 : 7.0;
    final vPad = large ? 8.0 : 6.0;
    final radius = large ? 12.0 : 9.0;
    return Container(
      width: w,
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: border,
          width: borderColor != null ? 2.5 : 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            formatOdds(odds),
            style: TextStyle(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Match Status Column (left of logos in post-lock layout)
// ─────────────────────────────────────────────────────────────────────────────

class _MatchStatusColumn extends StatelessWidget {
  const _MatchStatusColumn({required this.match});

  final PredictionMatch match;

  @override
  Widget build(BuildContext context) {
    final s = match.statusShort;
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    // Halftime or finished → single centered label
    if (s == 'HT') {
      return SizedBox(
        width: 50,
        child: Center(
          child: Text(
            isEn ? 'HT' : 'INT',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: CassandraColors.inkBlackV2,
            ),
          ),
        ),
      );
    }
    if (s == 'FT' || s == 'AET' || s == 'PEN') {
      return SizedBox(
        width: 50,
        child: Center(
          child: Text(
            isEn ? 'FT' : 'FINE',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: CassandraColors.inkBlackV2,
            ),
          ),
        ),
      );
    }

    // Live (1H, 2H, ET) → minute + half label
    if (s == '1H' || s == '2H' || s == 'ET' || s == 'BT' || s == 'LIVE') {
      final apiElapsed = match.elapsed;
      final int minute;
      final String halfLabel;
      if (s == '1H' || s == 'LIVE') {
        minute =
            apiElapsed?.clamp(1, 45) ??
            (CassandraScope.of(context).now().difference(match.kickoff).inMinutes + 1).clamp(
              1,
              45,
            );
        halfLabel = isEn ? '1H' : '1T';
      } else if (s == '2H') {
        minute =
            apiElapsed?.clamp(46, 90) ??
            (CassandraScope.of(context).now().difference(match.kickoff).inMinutes - 21).clamp(
              46,
              90,
            );
        halfLabel = isEn ? '2H' : '2T';
      } else {
        // ET / BT
        minute =
            apiElapsed?.clamp(91, 120) ??
            (CassandraScope.of(context).now().difference(match.kickoff).inMinutes - 36).clamp(
              91,
              120,
            );
        halfLabel = isEn ? 'ET' : 'TS';
      }
      return SizedBox(
        width: 50,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "$minute'",
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: CassandraColors.inkBlackV2,
              ),
            ),
            Text(
              halfLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: CassandraColors.inkBlackV2,
              ),
            ),
          ],
        ),
      );
    }

    // Pre-match → date + time
    final kickoff = match.kickoff.toLocal();
    final dateStr =
        '${kickoff.day.toString().padLeft(2, '0')}/${kickoff.month.toString().padLeft(2, '0')}';
    final timeStr =
        '${kickoff.hour.toString().padLeft(2, '0')}:${kickoff.minute.toString().padLeft(2, '0')}';
    return SizedBox(
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
    const size = 26.0;

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
  final String opposingLabel;
  final double opposingOdds;
  final bool isCorrect;
  final bool isLive;
  final bool isFT;
  final bool isAuto;
  final bool hidden;

  const _MemberPickData({
    required this.name,
    required this.pick,
    required this.odds,
    required this.opposingLabel,
    required this.opposingOdds,
    required this.isCorrect,
    required this.isLive,
    required this.isFT,
    this.isAuto = false,
    this.hidden = false,
  });
}

class _MemberPickRow extends StatelessWidget {
  const _MemberPickRow({required this.data});

  final _MemberPickData data;

  static const _mintLeaf = Color(0xFF00B884);
  static const _amaranth = Color(0xFFE01E48);

  @override
  Widget build(BuildContext context) {
    if (data.hidden) {
      final l10n = AppLocalizations.of(context)!;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Flexible(
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
            const SizedBox(width: 6),
            Text(
              l10n.memberPickNotSubmitted,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
                color: CassandraColors.inkBlackV2.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      );
    }

    // Single bubble: fill on FT, border on live
    Color? bg;
    Color? border;
    if (data.isFT) {
      bg = data.isCorrect ? _mintLeaf : _amaranth;
    } else if (data.isLive) {
      border = data.isCorrect ? _mintLeaf : _amaranth;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
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
                if (data.isAuto) ...[
                  const SizedBox(width: 4),
                  Text(
                    'auto',
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: CassandraColors.inkBlackV2.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _PostLockPickBubble(
            label: data.pick.label,
            odds: data.odds,
            bgColor: bg,
            borderColor: border,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Group leaderboard (post-lock)
// ─────────────────────────────────────────────────────────────────────────────

class _LeaderboardEntry {
  _LeaderboardEntry({
    required this.member,
    required this.totalPoints,
    required this.averageOddsPlayed,
  });

  final GroupMember member;
  final double totalPoints;
  final double? averageOddsPlayed;
}

class _GroupLeaderboardSection extends StatelessWidget {
  const _GroupLeaderboardSection({required this.entries});

  final List<_LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++)
          _leaderboardTile(entries[i], i),
      ],
    );
  }

  Widget _leaderboardTile(_LeaderboardEntry e, int index) {
    final pts = formatOdds(e.totalPoints);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
        leading: SizedBox(
          width: 64,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: CassandraColors.inkBlack,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AvatarWithBadges(
                radius: 18,
                backgroundColor: CassandraColors.primary,
                text: e.member.avatarInitial,
                badges: const [],
                imagePathOrUrl: e.member.photoUrl,
              ),
            ],
          ),
        ),
        title: Text(e.member.uiName),
        trailing: Text(
          pts,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: e.totalPoints >= 0
                ? CassandraColors.inkBlack
                : CassandraColors.primary,
          ),
        ),
      ),
      ),
    );
  }
}
