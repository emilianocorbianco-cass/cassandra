import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/state/app_state.dart';
import '../../app/theme/cassandra_colors.dart';
import '../badges/widgets/avatar_with_badges.dart';
import '../leaderboards/models/matchday_data.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/mock_prediction_data.dart';
import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/models/score_breakdown.dart';
import '../scoring/ranking_rules.dart';
import '../stats/stats_page.dart';

import 'create_group_page.dart';
import 'join_group_page.dart';
import 'mock_group_data.dart';
import 'group_matchday_page.dart';
import 'models/group_member.dart';
import 'widgets/group_image_picker.dart';
import '../leaderboards/mock_season_data.dart';
import '../../services/firestore/firestore_service.dart';
import '../../services/storage/storage_service.dart';
import '../../services/firestore/models/picks_document.dart';
import '../../services/firestore/models/group_document.dart';
import '../../services/firestore/models/matchday_document.dart';

// Status codes API-Football per partite iniziate/finite (usati per lo scoring provvisorio).
const _kLiveStatuses = {'1H', 'HT', '2H', 'ET', 'BT', 'LIVE', 'FT', 'AET', 'PEN'};

class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  /// Cached uid → photoUrl from user docs. Public static so HomeShell
  /// can pre-warm it at app startup for instant photo display.
  static final Map<String, String> memberPhotoCache = <String, String>{};

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _segment = 0; // 0 = classifica, 1 = giornate, 2 = stats
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


  // Firestore state
  List<GroupMember>? _firestoreMembers;
  List<GroupMemberDocument> _pendingMembers = const [];
  Map<String, Map<String, PickOption>>? _firestorePicksByMemberId;
  Map<String, List<PicksDocument>>? _firestoreSeasonPicksByMemberId;
  String? _firestoreGroupId;
  bool _firestoreLoading = false;
  bool _firestoreLoadError = false;
  String? _firestoreSeasonKey;
  int? _firestoreDayNumber;
  List<PicksDocument> _firestoreSeasonPicksDocs = const <PicksDocument>[];
  MatchdayDocument? _firestoreCurrentMatchday;
  Timer? _firestoreRevealTimer;
  StreamSubscription<List<GroupMemberDocument>>? _firestoreMembersSub;
  StreamSubscription<List<PicksDocument>>? _firestoreSeasonPicksSub;
  StreamSubscription<MatchdayDocument?>? _firestoreMatchdaySub;
  final Set<int> _hydratedSeasonMatchdayDays = <int>{};
  bool _seasonHistoryHydrationInFlight = false;
  bool _seasonHistoryHydrationQueued = false;
  String? _seasonHistoryHydrationGroupId;
  String? _seasonHistoryHydrationSeasonKey;



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
            _firestoreLoadError = false;
            _hydratedSeasonMatchdayDays.clear();
            _seasonHistoryHydrationInFlight = false;
            _seasonHistoryHydrationQueued = false;
            _seasonHistoryHydrationGroupId = null;
            _seasonHistoryHydrationSeasonKey = null;
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
    final neverLoaded =
        (_firestoreMembers == null || _firestoreLoadError) &&
        !_firestoreLoading;
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
          _firestoreLoadError = false;
          _hydratedSeasonMatchdayDays.clear();
          _seasonHistoryHydrationInFlight = false;
          _seasonHistoryHydrationQueued = false;
          _seasonHistoryHydrationGroupId = null;
          _seasonHistoryHydrationSeasonKey = null;
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

      // Self-repair: ensure own member doc has current profile data
      final ownIdx = members.indexWhere((m) => m.id == appState.profile.id);
      if (ownIdx >= 0) {
        final own = members[ownIdx];
        final profilePhoto = (appState.profile.photoUrl ?? '').trim();
        final memberPhoto = (own.photoUrl ?? '').trim();
        final teamNameDrifted =
            !own.hasCustomTeamName &&
            own.teamName != appState.profile.teamName;
        if (profilePhoto != memberPhoto ||
            own.displayName != appState.profile.displayName ||
            teamNameDrifted) {
          unawaited(
            appState.firestoreService!.updateGroupMemberProfileInGroups(
              uid: appState.profile.id,
              groupIds: [groupId],
              displayName: appState.profile.displayName,
              teamName: appState.profile.teamName,
              avatarSeed: appState.currentUserAvatarSeed,
              favoriteTeam: appState.profile.favoriteTeam,
              photoUrl: appState.profile.photoUrl,
            ),
          );
          members[ownIdx] = GroupMember(
            id: own.id,
            displayName: appState.profile.displayName,
            teamName: own.hasCustomTeamName
                ? own.teamName
                : appState.profile.teamName,
            avatarSeed: appState.currentUserAvatarSeed,
            favoriteTeam: appState.profile.favoriteTeam,
            hasCustomTeamName: own.hasCustomTeamName,
            photoUrl: profilePhoto.isEmpty ? null : profilePhoto,
          );
        }
      }

      // Apply cached photoUrls synchronously; fetch unknowns in background
      final enriched = _applyPhotoCache(members);
      _fetchMissingPhotosInBackground(enriched, fs);

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
        now: appState.now(),
      );

      if (!mounted) return;
      setState(() {
        _firestoreGroupId = groupId;
        _firestoreSeasonKey = appState.currentSeasonKey;
        _firestoreDayNumber = appState.uiMatchdayNumber;
        _firestoreMembers = enriched;
        _firestoreCurrentMatchday = matchdayData;
        _firestoreSeasonPicksDocs = filteredSeasonDocs;
        _firestorePicksByMemberId = picks;
        _firestoreSeasonPicksByMemberId = seasonPicksByMemberId;
        _firestoreLoading = false;
        _firestoreLoadError = false;
      });
      _scheduleFirestoreReveal(matchdayData?.lockTime);
      _bindFirestoreRealtime(
        appState: appState,
        groupId: groupId,
        seasonKey: appState.currentSeasonKey,
        dayNumber: appState.uiMatchdayNumber,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[group] load failed: $error');
      }
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
        _firestoreLoadError = true;
      });
    }
  }

  void _handleFirestoreRealtimeError(
    AppState appState,
    Object error,
    StackTrace stackTrace,
  ) {
    if (kDebugMode) {
      debugPrint('[group] realtime stream error: $error');
    }
    if (!mounted) return;
    setState(() {
      _firestoreLoading = false;
    });
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

    _firestoreMembersSub = fs
        .streamGroupMembers(groupId)
        .listen(
          (docs) {
            if (!mounted) return;
            final members = docs
                .where((d) => d.isActive)
                .map(
                  (d) => GroupMember(
                    id: d.uid,
                    displayName: d.displayName,
                    teamName: d.teamName,
                    avatarSeed: d.avatarSeed,
                    favoriteTeam: d.favoriteTeam,
                    hasCustomTeamName: d.hasCustomTeamName,
                    photoUrl: (d.photoUrl ?? '').trim().isEmpty
                        ? null
                        : d.photoUrl,
                  ),
                )
                .toList(growable: false);
            final pending = docs
                .where((d) => d.isPending)
                .toList(growable: false);
            setState(() {
              _firestoreMembers = _applyPhotoCache(members);
              _pendingMembers = pending;
            });
            _recomputeFirestoreDerived(appState);
          },
          onError: (Object error, StackTrace stackTrace) {
            _handleFirestoreRealtimeError(appState, error, stackTrace);
          },
        );

    _firestoreSeasonPicksSub = fs
        .streamPicksForSeason(seasonKey: seasonKey, groupId: groupId)
        .listen(
          (docs) {
            if (!mounted) return;
            setState(() {
              _firestoreSeasonPicksDocs = docs;
            });
            _recomputeFirestoreDerived(appState);
          },
          onError: (Object error, StackTrace stackTrace) {
            _handleFirestoreRealtimeError(appState, error, stackTrace);
          },
        );

    _firestoreMatchdaySub = fs.streamMatchdayData(seasonKey: seasonKey, dayNumber: dayNumber)
        .listen(
          (doc) {
            if (!mounted) return;
            setState(() {
              _firestoreCurrentMatchday = doc;
            });
            _scheduleFirestoreReveal(doc?.lockTime);
            _recomputeFirestoreDerived(appState);
          },
          onError: (Object error, StackTrace stackTrace) {
            _handleFirestoreRealtimeError(appState, error, stackTrace);
          },
        );
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

  /// Apply [GroupPage.memberPhotoCache] to a members list, replacing null photoUrls
  /// with cached values from previous user-doc lookups.
  List<GroupMember> _applyPhotoCache(List<GroupMember> members) {
    var changed = false;
    final result = List<GroupMember>.of(members);
    for (var i = 0; i < result.length; i++) {
      if (result[i].photoUrl == null) {
        final cached = GroupPage.memberPhotoCache[result[i].id];
        if (cached != null) {
          result[i] = GroupMember(
            id: result[i].id,
            displayName: result[i].displayName,
            teamName: result[i].teamName,
            avatarSeed: result[i].avatarSeed,
            favoriteTeam: result[i].favoriteTeam,
            hasCustomTeamName: result[i].hasCustomTeamName,
            photoUrl: cached,
          );
          changed = true;
        }
      }
    }
    return changed ? result : members;
  }

  /// Fire-and-forget: fetch user docs for members with missing photoUrl
  /// that aren't in cache yet. Updates [GroupPage.memberPhotoCache], pre-warms the
  /// StorageService byte cache for storage:// URLs, and refreshes
  /// [_firestoreMembers] via setState when done.
  void _fetchMissingPhotosInBackground(
    List<GroupMember> members,
    FirestoreService fs,
  ) {
    final missingUids = <String>[
      for (final m in members)
        if (m.photoUrl == null && !GroupPage.memberPhotoCache.containsKey(m.id)) m.id,
    ];
    if (missingUids.isEmpty) return;

    final storage = StorageService();
    Future.wait(missingUids.map((uid) => fs.getUserProfile(uid))).then((
      profiles,
    ) {
      if (!mounted) return;
      var anyNew = false;
      for (var j = 0; j < missingUids.length; j++) {
        final profile = profiles[j];
        if (profile == null) continue;
        final photo = ((profile['photoUrl'] as String?) ?? '').trim();
        if (photo.isEmpty) continue;
        GroupPage.memberPhotoCache[missingUids[j]] = photo;
        anyNew = true;
        // Pre-warm StorageService byte cache so AvatarWithBadges
        // finds bytes already loaded when it renders.
        if (StorageService.isStorageReference(photo)) {
          storage.readBytesByReference(photo);
        }
      }
      if (anyNew && _firestoreMembers != null) {
        setState(() {
          _firestoreMembers = _applyPhotoCache(_firestoreMembers!);
        });
      }
    });
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
    required DateTime now,
  }) {
    final revealAtOrAfterLock =
        lockTime != null && !now.isBefore(lockTime);
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
      now: appState.now(),
    );

    setState(() {
      _firestoreSeasonPicksByMemberId = seasonPicksByMemberId;
      _firestorePicksByMemberId = picksByMemberId;
    });
    _ensureSeasonHistoryHydrated(appState);
  }

  void _scheduleFirestoreReveal(DateTime? lockTime) {
    _firestoreRevealTimer?.cancel();
    _firestoreRevealTimer = null;
    if (lockTime == null) return;
    final now = CassandraScope.of(context).now();
    if (!now.isBefore(lockTime)) return;
    final wait = lockTime.difference(now) + const Duration(seconds: 1);
    _firestoreRevealTimer = Timer(wait, () {
      if (!mounted) return;
      final appState = CassandraScope.of(context);
      _recomputeFirestoreDerived(appState);
    });
  }

  void _ensureSeasonHistoryHydrated(AppState appState) {
    final fs = appState.firestoreService;
    final groupId = _firestoreGroupId ?? appState.activeGroupId;
    final seasonKey = _firestoreSeasonKey ?? appState.currentSeasonKey;
    if (fs == null || groupId == null || seasonKey.trim().isEmpty) return;

    final allDays = _firestoreSeasonPicksDocs
        .map((d) => d.dayNumber)
        .where((d) => d > 0)
        .toSet();
    if (allDays.isEmpty) return;

    final missingDays =
        allDays
            .where((day) => !_hydratedSeasonMatchdayDays.contains(day))
            .toList()
          ..sort((a, b) => a.compareTo(b));
    if (missingDays.isEmpty) return;

    if (_seasonHistoryHydrationInFlight) {
      final scopeChanged =
          _seasonHistoryHydrationGroupId != groupId ||
          _seasonHistoryHydrationSeasonKey != seasonKey;
      if (scopeChanged) {
        _seasonHistoryHydrationGroupId = groupId;
        _seasonHistoryHydrationSeasonKey = seasonKey;
      }
      _seasonHistoryHydrationQueued = true;
      return;
    }

    _seasonHistoryHydrationGroupId = groupId;
    _seasonHistoryHydrationSeasonKey = seasonKey;
    _seasonHistoryHydrationInFlight = true;
    unawaited(
      _hydrateSeasonHistoryDays(
        appState: appState,
        groupId: groupId,
        seasonKey: seasonKey,
        dayNumbers: missingDays,
      ),
    );
  }

  bool _isSeasonHistoryHydrationScopeCurrent({
    required String groupId,
    required String seasonKey,
  }) {
    return mounted &&
        _firestoreGroupId == groupId &&
        (_firestoreSeasonKey ?? '') == seasonKey;
  }

  Future<void> _hydrateSeasonHistoryDays({
    required AppState appState,
    required String groupId,
    required String seasonKey,
    required List<int> dayNumbers,
  }) async {
    final fs = appState.firestoreService;
    if (fs == null) {
      _seasonHistoryHydrationInFlight = false;
      return;
    }

    final loadedMatches = <int, List<PredictionMatch>>{};
    final loadedOutcomes = <int, Map<String, MatchOutcome>>{};

    try {
      for (final day in dayNumbers) {
        if (!_isSeasonHistoryHydrationScopeCurrent(
          groupId: groupId,
          seasonKey: seasonKey,
        )) {
          return;
        }
        if (_hydratedSeasonMatchdayDays.contains(day)) continue;
        try {
          final md = await fs.getMatchdayData(
            seasonKey: seasonKey,
            dayNumber: day,
          );
          if (!_isSeasonHistoryHydrationScopeCurrent(
            groupId: groupId,
            seasonKey: seasonKey,
          )) {
            return;
          }
          _hydratedSeasonMatchdayDays.add(day);
          if (md == null || md.matches.isEmpty) continue;

          await appState.saveMatchesHistory(
            matchdayNumber: day,
            matches: md.matches,
          );
          await appState.saveMatchdayMatchesSnapshot(
            matchdayNumber: day,
            matches: md.matches,
          );
          loadedMatches[day] = md.matches;

          if (md.outcomesByMatchId.isNotEmpty) {
            appState.saveOutcomesHistory(
              dayNumber: day,
              outcomesByMatchId: md.outcomesByMatchId,
            );
            loadedOutcomes[day] = md.outcomesByMatchId;
          }
        } catch (error) {
          if (kDebugMode) {
            debugPrint('[group] history hydration day $day failed: $error');
          }
        }
      }

      if ((loadedMatches.isNotEmpty || loadedOutcomes.isNotEmpty) &&
          _isSeasonHistoryHydrationScopeCurrent(
            groupId: groupId,
            seasonKey: seasonKey,
          )) {
        appState.setRecentMatchdayDataBulk(
          matchesByMatchday: loadedMatches,
          outcomesByMatchday: loadedOutcomes,
        );
      }
    } finally {
      _seasonHistoryHydrationInFlight = false;
      _seasonHistoryHydrationGroupId = null;
      _seasonHistoryHydrationSeasonKey = null;
      if (_seasonHistoryHydrationQueued) {
        _seasonHistoryHydrationQueued = false;
        if (mounted) {
          _ensureSeasonHistoryHydrated(appState);
        }
      }
    }
  }

  bool _approveInFlight = false;

  Future<void> _callApproveReject(String groupId, String memberUid, String action) async {
    if (_approveInFlight) return;
    _approveInFlight = true;

    // Remove from local list immediately for responsive UI.
    final removed = _pendingMembers.where((m) => m.uid == memberUid).toList();
    if (mounted) {
      setState(() {
        _pendingMembers = _pendingMembers
            .where((m) => m.uid != memberUid)
            .toList(growable: false);
      });
    }

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('approveGroupMember');
      await callable.call({
        'groupId': groupId,
        'memberUid': memberUid,
        'action': action,
      });
      if (kDebugMode) debugPrint('[approve] $action success for $memberUid');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[approve] $action error: $e');
        debugPrint('$st');
      }
      // Restore pending member on failure.
      if (mounted && removed.isNotEmpty) {
        setState(() {
          _pendingMembers = [..._pendingMembers, ...removed];
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$action failed: $e')),
        );
      }
    } finally {
      _approveInFlight = false;
    }
  }

  Widget _buildPendingMembersSection(AppState appState, AppLocalizations l10n) {
    final groupId = appState.activeGroupId;

    return Container(
      color: CassandraColors.inkBlackV2,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.groupPendingMembers,
            style: const TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          for (final member in _pendingMembers)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      member.displayName,
                      style: const TextStyle(
                        color: CassandraColors.brightSnow,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: TextButton(
                      onPressed: groupId == null
                          ? null
                          : () => _callApproveReject(groupId, member.uid, 'approve'),
                      style: TextButton.styleFrom(
                        foregroundColor: CassandraColors.mintLeaf,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(l10n.groupApprove),
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: TextButton(
                      onPressed: groupId == null
                          ? null
                          : () => _callApproveReject(groupId, member.uid, 'reject'),
                      style: TextButton.styleFrom(
                        foregroundColor: CassandraColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(l10n.groupReject),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
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
    super.build(context);
    final appState = CassandraScope.of(context);
    _ensureFirestoreMembersLoaded(appState);
    final l10n = AppLocalizations.of(context)!;

    if (!appState.hasGroup) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            l10n.tabGroup,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          bottom: false,
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
    final rawCurrentMatches =
        (_firestoreCurrentMatchday?.matches.isNotEmpty ?? false)
        ? _firestoreCurrentMatchday!.matches
        : _matches;
    final currentMatches = rawCurrentMatches
        .where((m) {
          final origin = appState.originKickoffFor(
            matchId: m.id,
            fallbackKickoff: m.kickoff,
          );
          return m.kickoff.difference(origin) <= const Duration(hours: 48);
        })
        .toList(growable: false);

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

    // Provisional outcomes per partite in corso: deriva l'esito dal punteggio live
    // (homeGoals/awayGoals) così lo scoring mostra un punteggio provvisorio invece di 0.
    final liveOverrides = <String, MatchOutcome>{
      for (final m in currentMatches)
        if (_kLiveStatuses.contains(m.statusShort) &&
            m.homeGoals != null &&
            m.awayGoals != null)
          m.id: m.homeGoals! > m.awayGoals!
              ? MatchOutcome.home
              : m.homeGoals! < m.awayGoals!
              ? MatchOutcome.away
              : MatchOutcome.draw,
    };
    final effectiveOutcomesByMatchId = liveOverrides.isEmpty
        ? outcomesByMatchId
        : Map<String, MatchOutcome>.unmodifiable({
            ...outcomesByMatchId,
            ...liveOverrides,
          });

    // Aggancia la cache runtime (che viene aggiornata da Pronostici/Settings).
    _syncFromCacheIfNeeded(appState);

    // Prefer per-group handle from Firestore member doc when available.
    final firestoreSelf = _firestoreMembers
        ?.cast<GroupMember?>()
        .firstWhere(
          (m) => m?.id == appState.profile.id,
          orElse: () => null,
        );
    final overrideMember = GroupMember(
      id: appState.profile.id,
      displayName: appState.profile.displayName,
      teamName: firestoreSelf?.hasCustomTeamName == true
          ? firestoreSelf!.teamName
          : appState.profile.teamName,
      avatarSeed: appState.currentUserAvatarSeed,
      favoriteTeam: appState.profile.favoriteTeam,
      hasCustomTeamName: firestoreSelf?.hasCustomTeamName ?? false,
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

        final md = seasonMatchdayByDay[pd.dayNumber];
        if (md != null && md.matches.isNotEmpty) {
          // Always recompute to apply current scoring rules.
          final dayScore = appState.scoringRules.scoreRound(
            matches: md.matches,
            picksByMatchId: pd.picksByMatchId,
            outcomesByMatchId: md.outcomesByMatchId,
          );
          totalPoints += dayScore.total;
          if (dayScore.averageOddsPlayed != null) {
            avgOddsValues.add(dayScore.averageOddsPlayed!);
          }
        } else {
          // Fallback to cached score when matchday data is unavailable.
          final score = pd.score;
          if (score != null) {
            totalPoints += score.total;
            if (score.averageOddsPlayed != null) {
              avgOddsValues.add(score.averageOddsPlayed!);
            }
          }
        }
      }

      final currentPicks =
          overridePicksByMemberId[member.id] ??
          picksByMemberByDay[currentMatchdayNumber]?[member.id] ??
          const <String, PickOption>{};
      final currentDayScore = appState.scoringRules.scoreRound(
        matches: currentMatches,
        picksByMatchId: currentPicks,
        outcomesByMatchId: effectiveOutcomesByMatchId,
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

    // Only show matchdays where at least one group member has picks.
    final playedDays = <int>{
      for (final docs in seasonPicksByMemberId.values)
        for (final pd in docs)
          if (pd.dayNumber > 0) pd.dayNumber,
    };
    final seasonMatchdaysDesc = seasonMatchdays
        .where((md) => playedDays.contains(md.dayNumber))
        .toList()
      ..sort((a, b) => b.dayNumber.compareTo(a.dayNumber));

    return Scaffold(
      backgroundColor: CassandraColors.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  // ── Group image ──
              GroupImageDisplay(
                imagePath: appState.groupImagePath,
                radius: 65,
              ),
              const SizedBox(height: 18),
              // ── Group name ──
              Text(
                groupName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: CassandraColors.brightSnow,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 36),
              // ── Classifica / Giornate / Stats buttons ──
              Container(
                height: 48,
                decoration: BoxDecoration(
                  border: Border.all(color: CassandraColors.brightSnow),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _GroupNavButton(
                        label: l10n.groupStandings,
                        selected: _segment == 0,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(15),
                        ),
                        onTap: () => setState(() => _segment = 0),
                      ),
                    ),
                    Container(width: 1, color: CassandraColors.brightSnow),
                    Expanded(
                      child: _GroupNavButton(
                        label: l10n.groupMatchdays,
                        selected: _segment == 1,
                        borderRadius: BorderRadius.zero,
                        onTap: () => setState(() => _segment = 1),
                      ),
                    ),
                    Container(width: 1, color: CassandraColors.brightSnow),
                    Expanded(
                      child: _GroupNavButton(
                        label: l10n.groupStats,
                        selected: _segment == 2,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(15),
                        ),
                        onTap: () => setState(() => _segment = 2),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // ── Divider ──
              const Divider(color: CassandraColors.brightSnow, thickness: 0.5, height: 0.5),
              // ── Pending members ──
              if (_pendingMembers.isNotEmpty)
                _buildPendingMembersSection(appState, l10n),
              // ── Content based on segment ──
              Expanded(
                child: useFirestoreMembers &&
                        _firestoreLoading &&
                        _firestoreMembers == null
                    ? const Center(child: CircularProgressIndicator())
                    : useFirestoreMembers && _firestoreLoadError
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(l10n.groupSyncError),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => setState(() {
                                _firestoreLoadError = false;
                                _firestoreMembers = null;
                              }),
                              icon: const Icon(Icons.refresh),
                              label: Text(l10n.groupSyncRetry),
                            ),
                          ],
                        ),
                      )
                    : useFirestoreMembers && members.isEmpty
                    ? Center(child: Text(l10n.commonNoDataAvailable))
                    : _segment == 2
                    ? const StatsPage(embedded: true, lockToPersonal: true)
                    : _segment == 1
                    ? _buildMatchdaysList(
                        seasonMatchdaysDesc, members, groupName,
                        picksByMemberByDay, en, l10n,
                      )
                    : _buildStandingsList(generalEntries),
              ),
            ],
          ),
        ),
        // ── Share button in top-right ──
        Positioned(
          top: 10,
          right: 18,
          child: Builder(
            builder: (buttonContext) => IconButton(
              icon: const Icon(Icons.share, color: CassandraColors.brightSnow),
              onPressed: () {
                final code = appState.groupInviteCode ?? '';
                _shareInvite(
                  groupName: groupName,
                  inviteCode: code,
                  sourceContext: buttonContext,
                  l10n: l10n,
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

  Widget _buildStandingsList(List<_GeneralLeaderboardEntry> entries) {
    return RefreshIndicator(
      onRefresh: _refreshFromFirestore,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 18, bottom: 90),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 18),
        itemBuilder: (context, i) {
          final e = entries[i];
          final pts = formatOdds(e.totalPoints);

          return Material(
            color: CassandraColors.platinum,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: CassandraColors.inkBlack,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AvatarWithBadges(
                    radius: 18,
                    backgroundColor: CassandraColors.primary,
                    text: e.member.avatarInitial,
                    badges: const [],
                    imagePathOrUrl: e.member.photoUrl,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      e.member.uiName,
                      style: const TextStyle(
                        color: CassandraColors.inkBlack,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    pts,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: e.totalPoints >= 0
                          ? CassandraColors.inkBlack
                          : CassandraColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMatchdaysList(
    List<MatchdayData> seasonMatchdaysDesc,
    List<GroupMember> members,
    String groupName,
    Map<int, Map<String, Map<String, PickOption>>> picksByMemberByDay,
    bool en,
    AppLocalizations l10n,
  ) {
    return RefreshIndicator(
      onRefresh: _refreshFromFirestore,
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 18, bottom: 90),
        itemCount: seasonMatchdaysDesc.length,
        separatorBuilder: (_, __) => const SizedBox(height: 18),
        itemBuilder: (context, i) {
          final md = seasonMatchdaysDesc[i];
          final daysLabel = formatMatchdayWeekdayRange(
            md.matches.map((m) => m.kickoff),
            english: en,
          );
          final mdTitle = l10n.groupMatchdayTitle(md.dayNumber);

          return Material(
            color: CassandraColors.platinum,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                    builder: (_) => GroupMatchdayPage(
                      matchday: md,
                      members: members,
                      groupName: groupName,
                      picksByMemberId:
                          picksByMemberByDay[md.dayNumber] ??
                          const <String, Map<String, PickOption>>{},
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mdTitle,
                            style: const TextStyle(
                              color: CassandraColors.inkBlack,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            daysLabel,
                            style: TextStyle(
                              color: CassandraColors.inkBlack.withValues(
                                alpha: 0.6,
                              ),
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: CassandraColors.inkBlack,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GroupNavButton extends StatelessWidget {
  const _GroupNavButton({
    required this.label,
    required this.borderRadius,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final BorderRadius borderRadius;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CassandraColors.platinum : Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? CassandraColors.inkBlack
                  : CassandraColors.brightSnow,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
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
