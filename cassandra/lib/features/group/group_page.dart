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
import '../stats/stats_page.dart';

import 'create_group_page.dart';
import 'join_group_page.dart';
import 'mock_group_data.dart';
import 'group_matchday_page.dart';
import 'models/group_member.dart';
import '../leaderboards/mock_season_data.dart';

class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  bool _didApplyMatches = false;

  static const int _matchdayNumber = 20;

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
  String? _firestoreGroupId;
  bool _firestoreLoading = false;

  @override
  void initState() {
    super.initState();
    _fallbackMatches = mockPredictionMatches();
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
          _firestoreGroupId != null ||
          _firestoreLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _firestoreMembers = null;
            _firestorePicksByMemberId = null;
            _firestoreGroupId = null;
            _firestoreLoading = false;
          });
        });
      }
      return;
    }

    final groupId = appState.activeGroupId!;
    final groupChanged = _firestoreGroupId != groupId;
    final neverLoaded = _firestoreMembers == null && !_firestoreLoading;
    if (!groupChanged && !neverLoaded) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (groupChanged) {
        setState(() {
          _firestoreGroupId = groupId;
          _firestoreMembers = null;
          _firestorePicksByMemberId = null;
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
      final members = await appState.fetchFirestoreGroupMembers();
      final uids = members.map((m) => m.id).toList(growable: false);
      final picks = uids.isEmpty
          ? const <String, Map<String, PickOption>>{}
          : await appState.fetchFirestorePicksForMatchday(
              dayNumber: appState.uiMatchdayNumber,
              uids: uids,
            );

      if (!mounted) return;
      setState(() {
        _firestoreGroupId = groupId;
        _firestoreMembers = members;
        _firestorePicksByMemberId = picks;
        _firestoreLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _firestoreGroupId = groupId;
        _firestoreMembers = const <GroupMember>[];
        _firestorePicksByMemberId = const <String, Map<String, PickOption>>{};
        _firestoreLoading = false;
      });
    }
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

    // Storico reale: picks/outcomes salvati per giornata
    appState.ensureCurrentUserPicksHistoryLoaded();
    appState.ensureOutcomesHistoryLoaded();

    final baseOutcomesByMatchId = appState.cachedPredictionMatchesAreReal
        ? <String, MatchOutcome>{
            for (final m in _matches)
              if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
                m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
          }
        : _outcomes;

    // Se abbiamo outcomes salvati per questa giornata, usali (sovrascrivono live/demo).
    final outcomesByMatchId =
        appState.hasSavedOutcomesForMatchday(_matchdayNumber)
        ? <String, MatchOutcome>{
            ...baseOutcomesByMatchId,
            ...appState.outcomesForMatchday(_matchdayNumber),
          }
        : baseOutcomesByMatchId;

    // Aggancia la cache runtime (che viene aggiornata da Pronostici/Settings).
    _syncFromCacheIfNeeded(appState);

    final totalMatches = _matches.length;
    final gradedCount = _matches.where((m) {
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
    );

    final useFirestoreMembers = _canUseFirestoreGroup(appState);
    final members = useFirestoreMembers
        ? (_firestoreMembers ?? const <GroupMember>[])
        : <GroupMember>[overrideMember];

    appState.ensureCurrentUserPicksLoaded();
    appState.ensureMemberPicksLoaded();

    final currentUserPicksForDay =
        appState.hasSavedPicksForMatchday(_matchdayNumber)
        ? appState.currentUserPicksForMatchday(_matchdayNumber)
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

    final entries = buildSortedMockGroupLeaderboard(
      matches: _matches,
      outcomesByMatchId: outcomesByMatchId,
      members: members,
      overridePicksByMemberId: overridePicksByMemberId,
    );

    // Storico (DEMO) per ora: giornate 16–19 (evitiamo mismatch con la giornata corrente reale).
    final seasonMatchdays =
        mockSeasonMatchdays(
          startDay: 16,
          count: 4,
          demoSeed: appState.demoSeed,
        ).map((md) {
          if (!appState.hasSavedOutcomesForMatchday(md.dayNumber)) return md;

          return MatchdayData(
            dayNumber: md.dayNumber,
            matches: md.matches,
            outcomesByMatchId: <String, MatchOutcome>{
              ...md.outcomesByMatchId,
              ...appState.outcomesForMatchday(md.dayNumber),
            },
          );
        }).toList();
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
                                _matches,
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
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final e = entries[i];

                          final badges =
                              CassandraBadgeEngine.badgesForGroupMatchday(
                                member: e.member,
                                rank: i + 1,
                                totalPlayers: entries.length,
                                matches: _matches,
                                picksByMatchId: e.picksByMatchId,
                                outcomesByMatchId: outcomesByMatchId,
                                day: e.day,
                              );

                          final pts = formatOdds(e.day.total);

                          return Card(
                            child: ListTile(
                              onTap: () {
                                final md = MatchdayData(
                                  dayNumber: _matchdayNumber,
                                  matches: _matches,
                                  outcomesByMatchId: outcomesByMatchId,
                                );

                                Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                    builder: (_) => UserHubPage(
                                      member: e.member,
                                      matchday: md,
                                      picksByMatchId: e.picksByMatchId,
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
                                    ),
                                  ],
                                ),
                              ),
                              title: Text(e.member.uiName),
                              trailing: Text(
                                pts,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: e.day.total >= 0
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
