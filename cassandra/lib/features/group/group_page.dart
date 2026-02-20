import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/state/app_state.dart';
import '../../app/theme/cassandra_colors.dart';
import 'widgets/group_image_picker.dart';
import '../badges/badge_engine.dart';
import '../badges/widgets/avatar_with_badges.dart';
import '../leaderboards/models/matchday_data.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/mock_prediction_data.dart';
import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../profile/user_hub_page.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/models/score_breakdown.dart';
import '../scoring/ranking_rules.dart';
import '../scoring/scoring_engine.dart';
import '../stats/stats_page.dart';

import 'create_group_page.dart';
import 'join_group_page.dart';
import 'mock_group_data.dart';
import 'group_matchday_page.dart';
import 'models/group_member.dart';
import '../leaderboards/mock_season_data.dart';
import '../../services/firestore/models/picks_document.dart';
import '../../services/firestore/models/group_document.dart';
import '../../services/firestore/models/matchday_document.dart';

class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  bool _didApplyMatches = false;

  // Fallback demo: stabile, creato una volta.
  late final List<PredictionMatch> _fallbackMatches;

  // Lista match effettiva (cache se c'è, altrimenti demo)
  List<PredictionMatch> _matches = [];

  // Esiti demo per calcolare classifica/punti (finché non useremo risultati reali).
  Map<String, MatchOutcome> _outcomes = {};

  // Firma per capire quando i match sono cambiati (es: refresh API).
  String _matchesSignature = '';
  String _pendingSignature = '';

  int _segment = 0; // 0 = classifica, 1 = giornate, 2 = stats

  // Firestore state
  List<GroupMember>? _firestoreMembers;
  Map<String, Map<String, PickOption>>? _firestorePicksByMemberId;
  Map<String, List<PicksDocument>>? _firestoreSeasonPicksByMemberId;
  String? _firestoreGroupId;
  bool _firestoreLoading = false;
  String? _firestoreSeasonKey;
  int? _firestoreDayNumber;
  List<PicksDocument> _firestoreSeasonPicksDocs = const <PicksDocument>[];
  MatchdayDocument? _firestoreCurrentMatchday;
  Timer? _firestoreRevealTimer;
  StreamSubscription<List<GroupMemberDocument>>? _firestoreMembersSub;
  StreamSubscription<List<PicksDocument>>? _firestoreSeasonPicksSub;
  StreamSubscription<MatchdayDocument?>? _firestoreMatchdaySub;

  @override
  void initState() {
    super.initState();
    _fallbackMatches = mockPredictionMatches();
  }

  @override
  void dispose() {
    _cancelFirestoreRealtime();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didApplyMatches) return;
    _didApplyMatches = true;
    _applyMatches(_fallbackMatches);
  }

  String _signatureFor(List<PredictionMatch> matches) {
    final ids = matches.map((m) => m.id).toList()..sort();
    return ids.join('|');
  }

  void _applyMatches(List<PredictionMatch> matches) {
    _matches = matches;
    _outcomes = mockOutcomesForMatches(matches);
    _matchesSignature = _signatureFor(matches);
    _pendingSignature = '';
  }

  void _syncFromCacheIfNeeded(dynamic appState) {
    final cached = appState.cachedPredictionMatches as List<PredictionMatch>?;
    final desired = cached ?? _fallbackMatches;
    final sig = _signatureFor(desired);

    // Già allineati o sync già pianificata.
    if (sig == _matchesSignature || sig == _pendingSignature) return;

    _pendingSignature = sig;

    // Non chiamiamo setState dentro build: lo pianifichiamo post-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _applyMatches(desired);
      });
    });
  }

  bool _canUseFirestoreGroup(AppState appState) =>
      appState.firestoreService != null &&
      appState.isAuthenticated &&
      appState.activeGroupId != null;

  void _ensureFirestoreMembersLoaded(AppState appState) {
    if (!_canUseFirestoreGroup(appState)) {
      if (_firestoreMembers != null ||
          _firestorePicksByMemberId != null ||
          _firestoreSeasonPicksByMemberId != null ||
          _firestoreGroupId != null ||
          _firestoreSeasonKey != null ||
          _firestoreDayNumber != null ||
          _firestoreCurrentMatchday != null ||
          _firestoreSeasonPicksDocs.isNotEmpty ||
          _firestoreLoading) {
        _cancelFirestoreRealtime();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _firestoreMembers = null;
            _firestorePicksByMemberId = null;
            _firestoreSeasonPicksByMemberId = null;
            _firestoreGroupId = null;
            _firestoreSeasonKey = null;
            _firestoreDayNumber = null;
            _firestoreCurrentMatchday = null;
            _firestoreSeasonPicksDocs = const <PicksDocument>[];
            _firestoreLoading = false;
          });
        });
      }
      return;
    }

    final groupId = appState.activeGroupId!;
    final seasonKey = appState.currentSeasonKey;
    final dayNumber = appState.uiMatchdayNumber;
    final groupChanged = _firestoreGroupId != groupId;
    final seasonChanged = _firestoreSeasonKey != seasonKey;
    final dayChanged = _firestoreDayNumber != dayNumber;
    final neverLoaded = _firestoreMembers == null && !_firestoreLoading;
    if (!groupChanged && !seasonChanged && !dayChanged && !neverLoaded) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (groupChanged || seasonChanged || dayChanged) {
        _cancelFirestoreRealtime();
        setState(() {
          _firestoreGroupId = groupId;
          _firestoreSeasonKey = seasonKey;
          _firestoreDayNumber = dayNumber;
          _firestoreMembers = null;
          _firestorePicksByMemberId = null;
          _firestoreSeasonPicksByMemberId = null;
          _firestoreCurrentMatchday = null;
          _firestoreSeasonPicksDocs = const <PicksDocument>[];
        });
      }
      _refreshFromFirestore();
    });
  }

  Future<void> _refreshFromFirestore() async {
    final appState = CassandraScope.of(context);
    if (!_canUseFirestoreGroup(appState)) return;
    final groupId = appState.activeGroupId!;
    if (_firestoreLoading) return;

    setState(() => _firestoreLoading = true);
    try {
      final fs = appState.firestoreService;
      if (fs == null) {
        if (!mounted) return;
        setState(() {
          _firestoreLoading = false;
        });
        return;
      }

      final members = await appState.fetchFirestoreGroupMembers();
      final uids = members.map((m) => m.id).toList(growable: false);
      final matchdayData = await fs.getMatchdayData(
        seasonKey: appState.currentSeasonKey,
        dayNumber: appState.uiMatchdayNumber,
      );
      final seasonDocs = await fs.getPicksForSeason(
        seasonKey: appState.currentSeasonKey,
        groupId: groupId,
      );
      final memberIdSet = uids.toSet();
      final filteredSeasonDocs = seasonDocs
          .where((d) => memberIdSet.contains(d.uid))
          .toList(growable: false);
      final seasonPicksByMemberId = _buildSeasonPicksByMember(
        filteredSeasonDocs,
      );
      final currentDayDocs = filteredSeasonDocs
          .where((d) => d.dayNumber == appState.uiMatchdayNumber)
          .toList(growable: false);
      final picks = _buildVisibleMatchdayPicks(
        docs: currentDayDocs,
        requesterUid: appState.profile.id,
        lockTime: matchdayData?.lockTime,
      );

      if (!mounted) return;
      setState(() {
        _firestoreGroupId = groupId;
        _firestoreSeasonKey = appState.currentSeasonKey;
        _firestoreDayNumber = appState.uiMatchdayNumber;
        _firestoreMembers = members;
        _firestoreCurrentMatchday = matchdayData;
        _firestoreSeasonPicksDocs = filteredSeasonDocs;
        _firestorePicksByMemberId = picks;
        _firestoreSeasonPicksByMemberId = seasonPicksByMemberId;
        _firestoreLoading = false;
      });

      _scheduleFirestoreReveal(matchdayData?.lockTime);
      _bindFirestoreRealtime(
        appState: appState,
        groupId: groupId,
        seasonKey: appState.currentSeasonKey,
        dayNumber: appState.uiMatchdayNumber,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _firestoreGroupId = groupId;
        _firestoreSeasonKey = appState.currentSeasonKey;
        _firestoreDayNumber = appState.uiMatchdayNumber;
        _firestoreMembers = const <GroupMember>[];
        _firestorePicksByMemberId = const <String, Map<String, PickOption>>{};
        _firestoreSeasonPicksByMemberId = const <String, List<PicksDocument>>{};
        _firestoreCurrentMatchday = null;
        _firestoreSeasonPicksDocs = const <PicksDocument>[];
        _firestoreLoading = false;
      });
    }
  }

  void _bindFirestoreRealtime({
    required AppState appState,
    required String groupId,
    required String seasonKey,
    required int dayNumber,
  }) {
    final fs = appState.firestoreService;
    if (fs == null) return;

    final shouldRebind =
        _firestoreMembersSub == null ||
        _firestoreSeasonPicksSub == null ||
        _firestoreMatchdaySub == null ||
        _firestoreGroupId != groupId ||
        _firestoreSeasonKey != seasonKey ||
        _firestoreDayNumber != dayNumber;
    if (!shouldRebind) return;

    _cancelFirestoreRealtime();

    _firestoreMembersSub = fs.streamGroupMembers(groupId).listen((docs) async {
      final members = docs
          .map(
            (d) => GroupMember(
              id: d.uid,
              displayName: d.displayName,
              teamName: d.teamName,
              avatarSeed: d.avatarSeed,
              favoriteTeam: d.favoriteTeam,
              photoUrl: (d.photoUrl?.trim().isNotEmpty ?? false)
                  ? d.photoUrl!.trim()
                  : null,
            ),
          )
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _firestoreMembers = members;
      });
      _recomputeFirestoreDerived(appState);
    });

    _firestoreSeasonPicksSub = fs
        .streamPicksForSeason(seasonKey: seasonKey, groupId: groupId)
        .listen((docs) {
          if (!mounted) return;
          setState(() {
            _firestoreSeasonPicksDocs = docs;
          });
          _recomputeFirestoreDerived(appState);
        });

    _firestoreMatchdaySub = fs
        .streamMatchdayData(seasonKey: seasonKey, dayNumber: dayNumber)
        .listen((doc) {
          if (!mounted) return;
          setState(() {
            _firestoreCurrentMatchday = doc;
          });
          _scheduleFirestoreReveal(doc?.lockTime);
          _recomputeFirestoreDerived(appState);
        });
  }

  void _cancelFirestoreRealtime() {
    _firestoreRevealTimer?.cancel();
    _firestoreRevealTimer = null;
    _firestoreMembersSub?.cancel();
    _firestoreMembersSub = null;
    _firestoreSeasonPicksSub?.cancel();
    _firestoreSeasonPicksSub = null;
    _firestoreMatchdaySub?.cancel();
    _firestoreMatchdaySub = null;
  }

  Map<String, List<PicksDocument>> _buildSeasonPicksByMember(
    List<PicksDocument> docs,
  ) {
    final byMember = <String, List<PicksDocument>>{};
    for (final doc in docs) {
      byMember.putIfAbsent(doc.uid, () => <PicksDocument>[]).add(doc);
    }
    for (final picks in byMember.values) {
      picks.sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
    }
    return byMember;
  }

  Map<String, Map<String, PickOption>> _buildVisibleMatchdayPicks({
    required List<PicksDocument> docs,
    required String requesterUid,
    required DateTime? lockTime,
  }) {
    final revealAtOrAfterLock =
        lockTime != null && !DateTime.now().isBefore(lockTime);
    final out = <String, Map<String, PickOption>>{};

    for (final d in docs) {
      if (d.uid == requesterUid) {
        out[d.uid] = d.picksByMatchId;
        continue;
      }

      final visibility = d.visibility.toLowerCase().trim();
      if (visibility == 'public') {
        out[d.uid] = d.picksByMatchId;
        continue;
      }

      final hiddenUntilLock =
          visibility == 'private' ||
          visibility == 'friends' ||
          visibility.isEmpty;
      if (hiddenUntilLock && revealAtOrAfterLock) {
        out[d.uid] = d.picksByMatchId;
      } else {
        out[d.uid] = const <String, PickOption>{};
      }
    }

    return out;
  }

  void _recomputeFirestoreDerived(AppState appState) {
    if (!mounted) return;
    final members = _firestoreMembers ?? const <GroupMember>[];
    if (members.isEmpty) {
      setState(() {
        _firestorePicksByMemberId = const <String, Map<String, PickOption>>{};
        _firestoreSeasonPicksByMemberId = const <String, List<PicksDocument>>{};
      });
      return;
    }

    final memberIds = members.map((m) => m.id).toSet();
    final seasonDocs = _firestoreSeasonPicksDocs
        .where((d) => memberIds.contains(d.uid))
        .toList(growable: false);
    final seasonPicksByMemberId = _buildSeasonPicksByMember(seasonDocs);
    final dayNumber = _firestoreDayNumber ?? appState.uiMatchdayNumber;
    final currentDayDocs = seasonDocs
        .where((d) => d.dayNumber == dayNumber)
        .toList(growable: false);
    final picksByMemberId = _buildVisibleMatchdayPicks(
      docs: currentDayDocs,
      requesterUid: appState.profile.id,
      lockTime: _firestoreCurrentMatchday?.lockTime,
    );

    setState(() {
      _firestoreSeasonPicksByMemberId = seasonPicksByMemberId;
      _firestorePicksByMemberId = picksByMemberId;
    });
  }

  void _scheduleFirestoreReveal(DateTime? lockTime) {
    _firestoreRevealTimer?.cancel();
    _firestoreRevealTimer = null;
    if (lockTime == null) return;
    final now = DateTime.now();
    if (!now.isBefore(lockTime)) return;
    final wait = lockTime.difference(now) + const Duration(seconds: 1);
    _firestoreRevealTimer = Timer(wait, () {
      if (!mounted) return;
      final appState = CassandraScope.of(context);
      _recomputeFirestoreDerived(appState);
    });
  }

  String _matchdayLabelFor(
    int matchdayNumber,
    List<PredictionMatch> matches, {
    required bool english,
    required AppLocalizations l10n,
  }) {
    final days = formatMatchdayDays(
      matches.map((m) => m.kickoff),
      english: english,
    );
    return l10n.groupMatchdayLabel(matchdayNumber, days);
  }

  Rect? _shareOriginFromContext(BuildContext sourceContext) {
    final renderObject = sourceContext.findRenderObject();
    if (renderObject is! RenderBox) return null;
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }

  Future<void> _shareInvite({
    required String groupName,
    required String inviteCode,
    required BuildContext sourceContext,
    required AppLocalizations l10n,
  }) async {
    if (inviteCode.trim().isEmpty) return;
    final text = l10n.groupShareInviteMessage(groupName, inviteCode);
    final messenger = ScaffoldMessenger.of(context);
    final shareOrigin = _shareOriginFromContext(sourceContext);
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: shareOrigin),
      );
      if (!mounted) return;
      if (result.status == ShareResultStatus.unavailable) {
        await Clipboard.setData(ClipboardData(text: inviteCode));
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.groupShareUnavailableCodeCopied)),
        );
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: inviteCode));
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.groupShareUnavailableCodeCopied)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = CassandraScope.of(context);
    _ensureFirestoreMembersLoaded(appState);
    final l10n = AppLocalizations.of(context)!;

    if (!appState.hasGroup) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            l10n.groupTitle,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => CreateGroupPage(
                              onGroupCreated: () {
                                Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).pop();
                                setState(() {});
                              },
                            ),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: CassandraColors.primary,
                        foregroundColor: CassandraColors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(l10n.groupEmptyCreateButton),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => JoinGroupPage(
                              onJoined: () {
                                Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).pop();
                                setState(() {});
                              },
                            ),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(l10n.groupEmptyJoinButton),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final en = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('en');
    final groupName = appState.groupName ?? l10n.groupDefaultName;
    final currentMatchdayNumber = appState.uiMatchdayNumber;
    final currentMatches =
        (_firestoreCurrentMatchday?.matches.isNotEmpty ?? false)
        ? _firestoreCurrentMatchday!.matches
        : _matches;

    // Storico reale: picks/outcomes salvati per giornata
    appState.ensureCurrentUserPicksHistoryLoaded();
    appState.ensureOutcomesHistoryLoaded();

    final firestoreOutcomes =
        _firestoreCurrentMatchday?.outcomesByMatchId ??
        const <String, MatchOutcome>{};
    final baseOutcomesByMatchId = firestoreOutcomes.isNotEmpty
        ? firestoreOutcomes
        : appState.cachedPredictionMatchesAreReal
        ? <String, MatchOutcome>{
            for (final m in currentMatches)
              if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
                m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
          }
        : _outcomes;

    // Se abbiamo outcomes salvati per questa giornata, usali (sovrascrivono live/demo).
    final outcomesByMatchId =
        appState.hasSavedOutcomesForMatchday(currentMatchdayNumber)
        ? <String, MatchOutcome>{
            ...baseOutcomesByMatchId,
            ...appState.outcomesForMatchday(currentMatchdayNumber),
          }
        : baseOutcomesByMatchId;

    // Aggancia la cache runtime (che viene aggiornata da Pronostici/Settings).
    _syncFromCacheIfNeeded(appState);

    final totalMatches = currentMatches.length;
    final gradedCount = currentMatches.where((m) {
      final o = outcomesByMatchId[m.id] ?? MatchOutcome.pending;
      return !o.isPending;
    }).length;

    final resultsLabel = gradedCount == totalMatches
        ? l10n.groupResultsLabel(gradedCount, totalMatches)
        : l10n.groupResultsLabelPartial(gradedCount, totalMatches);

    final overrideMember = GroupMember(
      id: appState.profile.id,
      displayName: appState.profile.displayName,
      teamName: appState.profile.teamName,
      avatarSeed: appState.currentUserAvatarSeed,
      favoriteTeam: appState.profile.favoriteTeam,
      photoUrl: appState.profile.photoUrl,
    );

    final useFirestoreMembers = _canUseFirestoreGroup(appState);
    final members = useFirestoreMembers
        ? (_firestoreMembers ?? const <GroupMember>[])
        : <GroupMember>[overrideMember];

    appState.ensureCurrentUserPicksLoaded();
    appState.ensureMemberPicksLoaded();

    final currentUserPicksForDay =
        appState.hasSavedPicksForMatchday(currentMatchdayNumber)
        ? appState.currentUserPicksForMatchday(currentMatchdayNumber)
        : appState.currentUserPicksByMatchId;

    // Use Firestore picks if available, fallback to mock
    final Map<String, Map<String, PickOption>> overridePicksByMemberId;
    if (useFirestoreMembers) {
      overridePicksByMemberId = {
        ...?_firestorePicksByMemberId,
        if (currentUserPicksForDay.isNotEmpty)
          overrideMember.id: currentUserPicksForDay,
      };
    } else {
      overridePicksByMemberId = {
        ...appState.memberPicksByMemberId,
        overrideMember.id: currentUserPicksForDay,
      };
    }

    final seasonPicksByMemberId = useFirestoreMembers
        ? (_firestoreSeasonPicksByMemberId ??
              const <String, List<PicksDocument>>{})
        : const <String, List<PicksDocument>>{};

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
    final seasonDays = seasonDaySet.toList()..sort((a, b) => a.compareTo(b));
    final seasonMatchdays = seasonDays.isEmpty
        ? mockSeasonMatchdays(
            startDay: 16,
            count: 4,
            demoSeed: appState.demoSeed,
          )
        : seasonDays.map((day) {
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

            return MatchdayData(
              dayNumber: day,
              matches: matchesForDay,
              outcomesByMatchId: outcomesForDay,
            );
          }).toList();
    final seasonMatchdayByDay = <int, MatchdayData>{
      for (final md in seasonMatchdays) md.dayNumber: md,
    };
    final picksByMemberByDay = <int, Map<String, Map<String, PickOption>>>{};
    for (final e in seasonPicksByMemberId.entries) {
      for (final pd in e.value) {
        picksByMemberByDay.putIfAbsent(pd.dayNumber, () => {});
        picksByMemberByDay[pd.dayNumber]![e.key] = pd.picksByMatchId;
      }
    }
    if (overridePicksByMemberId.isNotEmpty) {
      picksByMemberByDay.putIfAbsent(currentMatchdayNumber, () => {});
      picksByMemberByDay[currentMatchdayNumber]!.addAll(
        overridePicksByMemberId,
      );
    }

    final generalEntries = members.map((member) {
      final docs = seasonPicksByMemberId[member.id] ?? const <PicksDocument>[];
      var totalPoints = 0.0;
      final avgOddsValues = <double>[];

      for (final pd in docs) {
        if (pd.dayNumber == currentMatchdayNumber) continue;
        final score = pd.score;
        if (score != null) {
          totalPoints += score.total;
          if (score.averageOddsPlayed != null) {
            avgOddsValues.add(score.averageOddsPlayed!);
          }
          continue;
        }

        final md = seasonMatchdayByDay[pd.dayNumber];
        if (md == null || md.matches.isEmpty) continue;
        final dayScore = CassandraScoringEngine.computeDayScore(
          matches: md.matches,
          picksByMatchId: pd.picksByMatchId,
          outcomesByMatchId: md.outcomesByMatchId,
        );
        totalPoints += dayScore.total;
        if (dayScore.averageOddsPlayed != null) {
          avgOddsValues.add(dayScore.averageOddsPlayed!);
        }
      }

      final currentPicks =
          overridePicksByMemberId[member.id] ??
          picksByMemberByDay[currentMatchdayNumber]?[member.id] ??
          const <String, PickOption>{};
      final currentDayScore = CassandraScoringEngine.computeDayScore(
        matches: currentMatches,
        picksByMatchId: currentPicks,
        outcomesByMatchId: outcomesByMatchId,
      );
      totalPoints += currentDayScore.total;
      if (currentDayScore.averageOddsPlayed != null) {
        avgOddsValues.add(currentDayScore.averageOddsPlayed!);
      }

      final avgOdds = avgOddsValues.isEmpty
          ? null
          : avgOddsValues.reduce((a, b) => a + b) / avgOddsValues.length;

      return _GeneralLeaderboardEntry(
        member: member,
        currentDay: currentDayScore,
        currentDayPicksByMatchId: currentPicks,
        totalPoints: totalPoints,
        averageOddsPlayed: avgOdds,
      );
    }).toList();
    generalEntries.sort((a, b) {
      return compareCassandraRanking(
        aTotal: a.totalPoints,
        bTotal: b.totalPoints,
        aAverageOddsPlayed: a.averageOddsPlayed,
        bAverageOddsPlayed: b.averageOddsPlayed,
        aTeamName: a.member.teamName,
        bTeamName: b.member.teamName,
      );
    });

    final seasonMatchdaysDesc = seasonMatchdays.toList()
      ..sort((a, b) => b.dayNumber.compareTo(a.dayNumber));

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          l10n.groupTitle,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: l10n.groupJoinTooltip,
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => JoinGroupPage(
                    onJoined: () {
                      Navigator.of(context, rootNavigator: true).pop();
                      setState(() {});
                    },
                  ),
                ),
              );
            },
          ),
          Builder(
            builder: (buttonContext) => IconButton(
              icon: const Icon(Icons.share),
              onPressed: () async {
                final code = appState.groupInviteCode ?? '';
                await _shareInvite(
                  groupName: groupName,
                  inviteCode: code,
                  sourceContext: buttonContext,
                  l10n: l10n,
                );
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      GroupImageDisplay(
                        imagePath: appState.groupImagePath,
                        radius: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              groupName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _matchdayLabelFor(
                                appState.uiMatchdayNumber,
                                currentMatches,
                                english: en,
                                l10n: l10n,
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    resultsLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CassandraColors.slate,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 0, label: Text(l10n.groupStandings)),
                      ButtonSegment(value: 1, label: Text(l10n.groupMatchdays)),
                      ButtonSegment(value: 2, label: Text(l10n.groupStats)),
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
              child:
                  useFirestoreMembers &&
                      _firestoreLoading &&
                      _firestoreMembers == null
                  ? const Center(child: CircularProgressIndicator())
                  : useFirestoreMembers && members.isEmpty
                  ? Center(child: Text(l10n.commonNoDataAvailable))
                  : _segment == 2
                  ? const StatsPage(embedded: true, lockToGroup: true)
                  : _segment == 1
                  ? RefreshIndicator(
                      onRefresh: _refreshFromFirestore,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        itemCount: seasonMatchdaysDesc.length,
                        itemBuilder: (context, i) {
                          final md = seasonMatchdaysDesc[i];

                          final daysLabel = formatMatchdayDays(
                            md.matches.map((m) => m.kickoff),
                            english: en,
                          );

                          final graded = md.matches.where((m) {
                            final o = md.outcomesByMatchId[m.id];
                            return o != null && o != MatchOutcome.pending;
                          }).length;

                          final total = md.matches.length;
                          final mdResultsLabel = graded == total
                              ? l10n.groupResultsShort(graded, total)
                              : l10n.groupResultsShortPartial(graded, total);

                          final mdTitle = l10n.groupMatchdayTitle(md.dayNumber);

                          final mdResultsPrefix = l10n.groupResultsPrefix;

                          return Card(
                            child: ListTile(
                              title: Text(mdTitle),
                              subtitle: Text(
                                '$daysLabel\n$mdResultsPrefix: $mdResultsLabel',
                              ),
                              isThreeLine: true,
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                    builder: (_) => GroupMatchdayPage(
                                      matchday: md,
                                      members: members,
                                      groupName: groupName,
                                      picksByMemberId:
                                          picksByMemberByDay[md.dayNumber] ??
                                          const <
                                            String,
                                            Map<String, PickOption>
                                          >{},
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refreshFromFirestore,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        itemCount: generalEntries.length,
                        itemBuilder: (context, i) {
                          final e = generalEntries[i];

                          final badges =
                              CassandraBadgeEngine.badgesForGroupMatchday(
                                member: e.member,
                                rank: i + 1,
                                totalPlayers: generalEntries.length,
                                matches: currentMatches,
                                picksByMatchId: e.currentDayPicksByMatchId,
                                outcomesByMatchId: outcomesByMatchId,
                                day: e.currentDay,
                              );

                          final pts = formatOdds(e.totalPoints);

                          return Card(
                            child: ListTile(
                              onTap: () {
                                final md = MatchdayData(
                                  dayNumber: currentMatchdayNumber,
                                  matches: currentMatches,
                                  outcomesByMatchId: outcomesByMatchId,
                                );

                                Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                    builder: (_) => UserHubPage(
                                      member: e.member,
                                      matchday: md,
                                      picksByMatchId:
                                          e.currentDayPicksByMatchId,
                                      initialTabIndex: 0,
                                    ),
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
                                      backgroundColor: CassandraColors.primary,
                                      text: e.member.avatarInitial,
                                      badges: badges,
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
                                      ? CassandraColors.primary
                                      : CassandraColors.slate,
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

class _GeneralLeaderboardEntry {
  _GeneralLeaderboardEntry({
    required this.member,
    required this.currentDay,
    required this.currentDayPicksByMatchId,
    required this.totalPoints,
    required this.averageOddsPlayed,
  });

  final GroupMember member;
  final DayScoreBreakdown currentDay;
  final Map<String, PickOption> currentDayPicksByMatchId;
  final double totalPoints;
  final double? averageOddsPlayed;
}
