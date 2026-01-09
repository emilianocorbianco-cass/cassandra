import 'package:flutter/material.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../badges/badge_engine.dart';
import '../badges/widgets/avatar_with_badges.dart';
import '../leaderboards/models/matchday_data.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/mock_prediction_data.dart';
import '../predictions/models/prediction_match.dart';
import '../profile/user_hub_page.dart';
import '../scoring/models/match_outcome.dart';

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
  static const int _matchdayNumber = 20;
  static const String _groupName = 'Cassandra Crew';

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

  @override
  void initState() {
    super.initState();
    _fallbackMatches = mockPredictionMatches();
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

  String _matchdayLabelFor(List<PredictionMatch> matches) {
    final days = formatMatchdayDaysItalian(matches.map((m) => m.kickoff));
    return 'giornata $_matchdayNumber - $days';
  }

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final appState = CassandraScope.of(context);

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
        ? 'risultati: $gradedCount/$totalMatches'
        : 'risultati: $gradedCount/$totalMatches (parziale)';

    final dataLabel = appState.cachedPredictionMatchesAreReal
        ? 'dati: reali (API)'
        : 'dati: demo';

    final updatedLabel =
        (appState.cachedPredictionMatchesAreReal &&
            appState.cachedPredictionMatchesUpdatedAt != null)
        ? ' • agg. ${formatKickoff(appState.cachedPredictionMatchesUpdatedAt!)}'
        : '';

    final overrideMember = GroupMember(
      id: appState.profile.id,
      displayName: appState.profile.displayName,
      teamName: appState.profile.teamName,
      avatarSeed: appState.currentUserAvatarSeed,
      favoriteTeam: appState.profile.favoriteTeam,
    );

    final members = mockGroupMembers(overrideMember: overrideMember);

    appState.ensureCurrentUserPicksLoaded();
    appState.ensureMemberPicksLoaded();

    final currentUserPicksForDay =
        appState.hasSavedPicksForMatchday(_matchdayNumber)
        ? appState.currentUserPicksForMatchday(_matchdayNumber)
        : appState.currentUserPicksByMatchId;

    final overridePicksByMemberId = {
      ...appState.memberPicksByMemberId,
      overrideMember.id: currentUserPicksForDay,
    };

    final entries = buildSortedMockGroupLeaderboard(
      matches: _matches,
      outcomesByMatchId: outcomesByMatchId,
      members: members,
      overridePicksByMemberId: overridePicksByMemberId,
    );

    // Storico (DEMO) per ora: giornate 16–19 (evitiamo mismatch con la giornata corrente reale).
    final seasonMatchdays = mockSeasonMatchdays(startDay: 16, count: 4).map((
      md,
    ) {
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
        title: const Text('Il mio gruppo'),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _groupName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _matchdayLabelFor(_matches),
                    style: Theme.of(context).textTheme.bodySmall,
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
                    segments: const [
                      ButtonSegment(value: 0, label: Text('classifica')),
                      ButtonSegment(value: 1, label: Text('giornate')),
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
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      itemCount: seasonMatchdaysDesc.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return const Card(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Storico giornate (DEMO)'
                                'Qui mostriamo 16–19 dai mock. Appena abbiamo storico reale via API, lo rendiamo “vero”.',
                              ),
                            ),
                          );
                        }

                        final md = seasonMatchdaysDesc[i - 1];

                        final daysLabel = formatMatchdayDaysItalian(
                          md.matches.map((m) => m.kickoff),
                        );

                        final graded = md.matches.where((m) {
                          final o = md.outcomesByMatchId[m.id];
                          return o != null && o != MatchOutcome.pending;
                        }).length;

                        final total = md.matches.length;
                        final resultsLabel = graded == total
                            ? '$graded/$total'
                            : '$graded/$total (parziale)';

                        return Card(
                          child: ListTile(
                            title: Text('Giornata ${md.dayNumber}'),
                            subtitle: Text(
                              '$daysLabel\nrisultati: $resultsLabel',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GroupMatchdayPage(
                                    matchday: md,
                                    members: members,
                                    groupName: _groupName,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    )
                  : ListView.builder(
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

                              Navigator.of(context).push(
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
          ],
        ),
      ),
    );
  }
}
