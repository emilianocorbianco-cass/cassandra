import '../badges/season_badge_engine.dart';
import '../badges/widgets/avatar_with_badges.dart';

import 'package:flutter/material.dart';

import '../../app/theme/cassandra_colors.dart';
import '../predictions/models/formatters.dart';
import 'matchday_leaderboard_page.dart';
import 'member_season_page.dart';
import 'mock_season_data.dart';
import 'models/matchday_data.dart';
import 'models/season_leaderboard_entry.dart';

class LeaderboardsPage extends StatefulWidget {
  const LeaderboardsPage({super.key});

  @override
  State<LeaderboardsPage> createState() => _LeaderboardsPageState();
}

class _LeaderboardsPageState extends State<LeaderboardsPage> {
  int _segment = 0; // 0 = generale, 1 = giornate
  int _generalMode = 0; // 0 = punti, 1 = media

  late final List<MatchdayData> _matchdays;
  late final List<SeasonLeaderboardEntry> _entries;

  @override
  void initState() {
    super.initState();
    _matchdays = mockSeasonMatchdays(startDay: 16, count: 5); // 16–20
    _entries = buildMockSeasonLeaderboardEntries(matchdays: _matchdays);
  }

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  String get _seasonLabel {
    if (_matchdays.isEmpty) return '';
    return 'stagione demo • giornate ${_matchdays.first.dayNumber}–${_matchdays.last.dayNumber}';
  }

  List<SeasonLeaderboardEntry> _sortedGeneral() {
    final list = List.of(_entries);

    if (_generalMode == 0) {
      // GENERALE per PUNTI
      list.sort((a, b) {
        final t = b.totalPoints.compareTo(a.totalPoints);
        if (t != 0) return t;

        final aOdds = a.averageOddsPlayed ?? -1;
        final bOdds = b.averageOddsPlayed ?? -1;
        final oddsCmp = bOdds.compareTo(aOdds);
        if (oddsCmp != 0) return oddsCmp;

        return a.member.teamName.compareTo(b.member.teamName);
      });
    } else {
      // GENERALE per MEDIA punti/giornata
      list.sort((a, b) {
        final t = b.averagePerMatchday.compareTo(a.averagePerMatchday);
        if (t != 0) return t;

        final aOdds = a.averageOddsPlayed ?? -1;
        final bOdds = b.averageOddsPlayed ?? -1;
        final oddsCmp = bOdds.compareTo(aOdds);
        if (oddsCmp != 0) return oddsCmp;

        // se media uguale, chi ha giocato più giornate è “più affidabile”
        final d = b.daysPlayed.compareTo(a.daysPlayed);
        if (d != 0) return d;

        return a.member.teamName.compareTo(b.member.teamName);
      });
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final general = _sortedGeneral();

    return Scaffold(
      appBar: AppBar(title: const Text('Classifiche')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _seasonLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('generale')),
                      ButtonSegment(value: 1, label: Text('giornate')),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (s) =>
                        setState(() => _segment = s.first),
                  ),
                  if (_segment == 0) ...[
                    const SizedBox(height: 10),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('punti')),
                        ButtonSegment(value: 1, label: Text('media')),
                      ],
                      selected: {_generalMode},
                      onSelectionChanged: (s) =>
                          setState(() => _generalMode = s.first),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _segment == 1
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      itemCount: _matchdays.length,
                      itemBuilder: (context, i) {
                        final md =
                            _matchdays[_matchdays.length -
                                1 -
                                i]; // latest first
                        final daysLabel = formatMatchdayDaysItalian(
                          md.matches.map((m) => m.kickoff),
                        );

                        return Card(
                          child: ListTile(
                            title: Text('Giornata ${md.dayNumber}'),
                            subtitle: Text(daysLabel),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MatchdayLeaderboardPage(
                                    matchday: md,
                                    seasonEntries: _entries,
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
                      itemCount: general.length,
                      itemBuilder: (context, i) {
                        final e = general[i];
                        final badges =
                            CassandraSeasonBadgeEngine.badgesForSeason(
                              entry: e,
                              rank: i + 1,
                              totalPlayers: general.length,
                            );

                        final value = _generalMode == 0
                            ? e.totalPoints
                            : e.averagePerMatchday;
                        final valueLabel = formatOdds(value);
                        final sign = value >= 0 ? '+' : '';

                        final avgOddsLabel = e.averageOddsPlayed == null
                            ? '-'
                            : formatOdds(e.averageOddsPlayed!);

                        final subtitle = _generalMode == 0
                            ? '${e.member.teamName}\nmedia/giornata: ${formatOdds(e.averagePerMatchday)} • giornate: ${e.daysPlayed} • quota: $avgOddsLabel'
                            : '${e.member.teamName}\ntotale: ${formatOdds(e.totalPoints)} • giornate: ${e.daysPlayed} • quota: $avgOddsLabel';

                        return Card(
                          child: ListTile(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MemberSeasonPage(entry: e),
                                ),
                              );
                            },
                            isThreeLine: true,
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
                            subtitle: Text(subtitle),
                            trailing: Text(
                              '$sign$valueLabel',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
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
