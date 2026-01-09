import 'package:flutter/material.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../badges/season_badge_engine.dart';
import '../badges/widgets/avatar_with_badges.dart';
import '../group/mock_group_data.dart';
import '../group/models/group_member.dart';
import '../predictions/models/formatters.dart';
import 'matchday_leaderboard_page.dart';
import 'member_season_page.dart';
import 'mock_season_data.dart';
import 'models/matchday_data.dart';
import 'models/season_leaderboard_entry.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';

class LeaderboardsPage extends StatefulWidget {
  const LeaderboardsPage({super.key});

  @override
  State<LeaderboardsPage> createState() => _LeaderboardsPageState();
}

enum _GeneralMode { points, average }

class _LeaderboardsPageState extends State<LeaderboardsPage> {
  int _segment = 0; // 0=generale, 1=giornate
  _GeneralMode _generalMode = _GeneralMode.points;

  late final List<MatchdayData> _matchdays;

  @override
  void initState() {
    super.initState();
    _matchdays = mockSeasonMatchdays(startDay: 16, count: 5);
  }

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  List<SeasonLeaderboardEntry> _sortedGeneral(
    List<SeasonLeaderboardEntry> input,
  ) {
    final list = List<SeasonLeaderboardEntry>.of(input);

    list.sort((a, b) {
      if (_generalMode == _GeneralMode.points) {
        final t = b.totalPoints.compareTo(a.totalPoints);
        if (t != 0) return t;

        final ao = a.averageOddsPlayed ?? -1;
        final bo = b.averageOddsPlayed ?? -1;
        final o = bo.compareTo(ao);
        if (o != 0) return o;

        return a.member.teamName.compareTo(b.member.teamName);
      } else {
        final t = b.averagePerMatchday.compareTo(a.averagePerMatchday);
        if (t != 0) return t;

        final p = b.totalPoints.compareTo(a.totalPoints);
        if (p != 0) return p;

        return a.member.teamName.compareTo(b.member.teamName);
      }
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final appState = CassandraScope.of(context);

    final cachedMatches = appState.cachedPredictionMatches;
    final liveDayNumber = _matchdays.isNotEmpty
        ? _matchdays.last.dayNumber
        : 20;
    final useLive =
        appState.cachedPredictionMatchesAreReal &&
        cachedMatches != null &&
        cachedMatches.isNotEmpty;

    final liveOutcomes = <String, MatchOutcome>{};
    if (cachedMatches != null) {
      for (final m in cachedMatches) {
        liveOutcomes[m.id] =
            appState.effectivePredictionOutcomesByMatchId[m.id] ??
            MatchOutcome.pending;
      }
    }

    final liveMatchday = useLive
        ? MatchdayData(
            dayNumber: liveDayNumber,
            matches: cachedMatches,
            outcomesByMatchId: liveOutcomes,
          )
        : null;

    final matchdays = useLive
        ? [
            for (final md in _matchdays)
              if (md.dayNumber != liveDayNumber) md,
            liveMatchday!,
          ]
        : _matchdays;

    final overrideMember = GroupMember(
      id: appState.profile.id,
      displayName: appState.profile.displayName,
      teamName: appState.profile.teamName,
      avatarSeed: appState.currentUserAvatarSeed,
      favoriteTeam: appState.profile.favoriteTeam,
    );

    final members = mockGroupMembers(overrideMember: overrideMember);

    final entries = buildMockSeasonLeaderboardEntries(
      matchdays: matchdays,
      members: members,
    );

    // Override: l'utente corrente usa i pick reali persistiti (quando presenti).
    appState.ensureCurrentUserPicksLoaded();
    final currentUserEntry = buildSeasonEntryForMemberFromPicks(
      member: overrideMember,
      matchdays: matchdays,
      picksByMatchId: appState.currentUserPicksByMatchId,
    );
    final entriesWithCurrent = [
      for (final e in entries)
        if (e.member.id != overrideMember.id) e,
      currentUserEntry,
    ];

    appState.ensureMemberPicksLoaded();
    final entriesWithOverrides = entriesWithCurrent.map((e) {
      final override = appState.memberPicksByMemberId[e.member.id];
      if (override != null && override.isNotEmpty) {
        return buildSeasonEntryForMemberFromPicks(
          member: e.member,
          matchdays: matchdays,
          picksByMatchId: override,
        );
      }
      return e;
    }).toList();

    final sorted = _sortedGeneral(entriesWithOverrides);

    return Scaffold(
      appBar: AppBar(title: const Text('Classifiche')),
      body: SafeArea(
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Builder(
                  builder: (context) {
                    // Debug: dati/pronostici cache (coerente con Gruppo/Utente)
                    final app = CassandraScope.of(context);
                    final matches = app.cachedPredictionMatches;
                    final total = matches?.length ?? 0;
                    final outcomes = app.effectivePredictionOutcomesByMatchId;
                    final graded = (matches == null)
                        ? 0
                        : matches.where((m) {
                            final o = outcomes[m.id] ?? MatchOutcome.pending;
                            return !o.isPending;
                          }).length;

                    final kind = app.cachedPredictionMatchesAreReal
                        ? 'reali (API)'
                        : (total > 0 ? 'demo' : 'vuota');

                    final updated = app.cachedPredictionMatchesUpdatedAt;
                    String fmt(DateTime dt) {
                      final dd = dt.day.toString().padLeft(2, '0');
                      final mm = dt.month.toString().padLeft(2, '0');
                      final hh = dt.hour.toString().padLeft(2, '0');
                      final mi = dt.minute.toString().padLeft(2, '0');
                      return '$dd/$mm $hh:$mi';
                    }

                    final updatedLabel = (updated == null)
                        ? 'mai'
                        : fmt(updated);

                    final resultsLabel = (total == 0)
                        ? null
                        : (graded == total
                              ? 'risultati: $graded/$total'
                              : 'risultati: $graded/$total (parziale)');

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('dati: $kind • agg. $updatedLabel'),
                        if (resultsLabel != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            resultsLabel,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('generale')),
                      ButtonSegment(value: 1, label: Text('giornate')),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (s) =>
                        setState(() => _segment = s.first),
                  ),
                  const SizedBox(height: 10),
                  if (_segment == 0)
                    SegmentedButton<_GeneralMode>(
                      segments: const [
                        ButtonSegment(
                          value: _GeneralMode.points,
                          label: Text('punti'),
                        ),
                        ButtonSegment(
                          value: _GeneralMode.average,
                          label: Text('media'),
                        ),
                      ],
                      selected: {_generalMode},
                      onSelectionChanged: (s) =>
                          setState(() => _generalMode = s.first),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _segment == 1
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      itemCount: matchdays.length,
                      itemBuilder: (context, i) {
                        final md = matchdays[matchdays.length - 1 - i];
                        final isLive = useLive && md.dayNumber == liveDayNumber;
                        final daysLabel = formatMatchdayDaysItalian(
                          md.matches.map((m) => m.kickoff),
                        );

                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: CassandraColors.primary
                                  .withAlpha(31),
                              child: Text(
                                '${md.dayNumber}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: CassandraColors.primary,
                                ),
                              ),
                            ),
                            title: Text(
                              isLive
                                  ? 'Giornata ${md.dayNumber} (LIVE)'
                                  : 'Giornata ${md.dayNumber}',
                            ),
                            subtitle: Text(() {
                              final total = md.matches.length;
                              final graded = md.matches.where((m) {
                                final o =
                                    md.outcomesByMatchId[m.id] ??
                                    MatchOutcome.pending;
                                return !o.isPending;
                              }).length;
                              final rl = (graded == total)
                                  ? 'risultati: $graded/$total'
                                  : 'risultati: $graded/$total (parziale)';
                              return '$daysLabel\n$rl';
                            }()),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MatchdayLeaderboardPage(
                                    matchday: md,
                                    seasonEntries: entriesWithOverrides,
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
                      itemCount: sorted.length,
                      itemBuilder: (context, i) {
                        final e = sorted[i];

                        final badges =
                            CassandraSeasonBadgeEngine.badgesForSeason(
                              entry: e,
                              rank: i + 1,
                              totalPlayers: sorted.length,
                            );

                        final metricLabel = _generalMode == _GeneralMode.points
                            ? formatOdds(e.totalPoints)
                            : formatOdds(e.averagePerMatchday);

                        return Card(
                          child: ListTile(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MemberSeasonPage(entry: e),
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
                              metricLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
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
