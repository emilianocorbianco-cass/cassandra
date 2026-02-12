import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/state/app_settings.dart';
import '../../app/state/app_state.dart';
import '../../app/state/cassandra_scope.dart';
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

import '../../app/widgets/demo_banner.dart';
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

  int _segment = 0; // 0 = classifica, 1 = giornate (placeholder)

  // Firestore state
  List<GroupMember>? _firestoreMembers;
  Map<String, Map<String, PickOption>>? _firestorePicksByMemberId;
  bool _firestoreLoading = false;

  bool _isEnglish(AppState app) {
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  String _t(AppState app, String it, String en) => _isEnglish(app) ? en : it;

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

  Future<void> _refreshFromFirestore() async {
    final appState = CassandraScope.of(context);
    if (appState.activeGroupId == null) return;

    setState(() => _firestoreLoading = true);
    try {
      final members = await appState.fetchFirestoreGroupMembers();
      if (members.isEmpty) {
        setState(() => _firestoreLoading = false);
        return;
      }

      final uids = members.map((m) => m.id).toList();
      final picks = await appState.fetchFirestorePicksForMatchday(
        dayNumber: appState.uiMatchdayNumber,
        uids: uids,
      );

      if (!mounted) return;
      setState(() {
        _firestoreMembers = members;
        _firestorePicksByMemberId = picks;
        _firestoreLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _firestoreLoading = false);
    }
  }

  String _matchdayLabelFor(
    int matchdayNumber,
    List<PredictionMatch> matches, {
    required bool english,
  }) {
    final days = formatMatchdayDays(
      matches.map((m) => m.kickoff),
      english: english,
    );
    return english
        ? 'matchday $matchdayNumber - $days'
        : 'giornata $matchdayNumber - $days';
  }

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final appState = CassandraScope.of(context);

    if (!appState.hasGroup) {
      return CreateGroupPage(onGroupCreated: () => setState(() {}));
    }

    final en = _isEnglish(appState);
    final groupName = appState.groupName ?? 'Cassandra Crew';

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

    final resultsLabel = en
        ? (gradedCount == totalMatches
              ? 'results: $gradedCount/$totalMatches'
              : 'results: $gradedCount/$totalMatches (partial)')
        : (gradedCount == totalMatches
              ? 'risultati: $gradedCount/$totalMatches'
              : 'risultati: $gradedCount/$totalMatches (parziale)');

    final dataLabel = _firestoreLoading
        ? _t(appState, 'aggiornamento...', 'refreshing...')
        : appState.cachedPredictionMatchesAreReal
        ? _t(appState, 'dati: reali (API)', 'data: real (API)')
        : _t(appState, 'dati: demo', 'data: demo');

    final updatedLabel =
        (appState.cachedPredictionMatchesAreReal &&
            appState.cachedPredictionMatchesUpdatedAt != null)
        ? ' \u2022 ${en ? 'upd.' : 'agg.'} ${formatKickoff(appState.cachedPredictionMatchesUpdatedAt!)}'
        : '';

    final overrideMember = GroupMember(
      id: appState.profile.id,
      displayName: appState.profile.displayName,
      teamName: appState.profile.teamName,
      avatarSeed: appState.currentUserAvatarSeed,
      favoriteTeam: appState.profile.favoriteTeam,
    );

    // Use Firestore members if available, fallback to mock
    final members =
        _firestoreMembers ?? mockGroupMembers(overrideMember: overrideMember);

    appState.ensureCurrentUserPicksLoaded();
    appState.ensureMemberPicksLoaded();

    final currentUserPicksForDay =
        appState.hasSavedPicksForMatchday(_matchdayNumber)
        ? appState.currentUserPicksForMatchday(_matchdayNumber)
        : appState.currentUserPicksByMatchId;

    // Use Firestore picks if available, fallback to mock
    final Map<String, Map<String, PickOption>> overridePicksByMemberId;
    if (_firestorePicksByMemberId != null) {
      overridePicksByMemberId = {
        ..._firestorePicksByMemberId!,
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
        title: Text(_t(appState, 'Il mio gruppo', 'My group')),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: _t(appState, 'Unisciti a un gruppo', 'Join a group'),
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
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              final code = appState.groupInviteCode ?? '';
              final text = en
                  ? 'Join my group "$groupName" on Cassandra! Code: $code'
                  : 'Unisciti al mio gruppo «$groupName» su Cassandra! Codice: $code';
              SharePlus.instance.share(ShareParams(text: text));
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$dataLabel$updatedLabel',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_firestoreMembers == null)
              DemoBanner(
                label: _t(
                  appState,
                  'Dati di esempio \u2014 unisciti a un gruppo per vedere dati reali',
                  'Sample data \u2014 join a group to see real data',
                ),
              ),
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
                    segments: [
                      ButtonSegment(
                        value: 0,
                        label: Text(_t(appState, 'classifica', 'standings')),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text(_t(appState, 'giornate', 'matchdays')),
                      ),
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
              child: _segment == 1
                  ? RefreshIndicator(
                      onRefresh: _refreshFromFirestore,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        itemCount: seasonMatchdaysDesc.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  _t(
                                    appState,
                                    'Storico giornate (DEMO)\n'
                                        'Qui mostriamo 16–19 dai mock. Appena abbiamo storico reale via API, lo rendiamo "vero".',
                                    'Matchday history (DEMO)\n'
                                        'Showing 16–19 from mocks. Once we have real history via API, we\'ll make it live.',
                                  ),
                                ),
                              ),
                            );
                          }

                          final md = seasonMatchdaysDesc[i - 1];

                          final daysLabel = formatMatchdayDays(
                            md.matches.map((m) => m.kickoff),
                            english: en,
                          );

                          final graded = md.matches.where((m) {
                            final o = md.outcomesByMatchId[m.id];
                            return o != null && o != MatchOutcome.pending;
                          }).length;

                          final total = md.matches.length;
                          final mdResultsLabel = en
                              ? (graded == total
                                    ? '$graded/$total'
                                    : '$graded/$total (partial)')
                              : (graded == total
                                    ? '$graded/$total'
                                    : '$graded/$total (parziale)');

                          final mdTitle = en
                              ? 'Matchday ${md.dayNumber}'
                              : 'Giornata ${md.dayNumber}';

                          final mdResultsPrefix = en ? 'results' : 'risultati';

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
                                      backgroundColor: _avatarColorFromSeed(
                                        e.member.avatarSeed,
                                      ),
                                      text: e.member.displayName
                                          .substring(0, 1)
                                          .toUpperCase(),
                                      badges: badges,
                                    ),
                                  ],
                                ),
                              ),
                              title: Text(e.member.displayName),
                              subtitle: Text(e.member.teamName),
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
