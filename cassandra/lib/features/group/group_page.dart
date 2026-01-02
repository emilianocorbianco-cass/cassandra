import '../badges/badge_engine.dart';
import '../badges/widgets/avatar_with_badges.dart';

import 'package:flutter/material.dart';

import '../../app/theme/cassandra_colors.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/mock_prediction_data.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';

import 'mock_group_data.dart';
import 'models/group_leaderboard_entry.dart';
import 'user_picks_page.dart';

class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  static const int _matchdayNumber = 20;
  static const String _groupName = 'Cassandra Crew';

  late final List<PredictionMatch> _matches;
  late final Map<String, MatchOutcome> _outcomes;
  late final List<GroupLeaderboardEntry> _entries;

  int _segment = 0; // 0 = classifica, 1 = giornate (placeholder)

  @override
  void initState() {
    super.initState();
    _matches = mockPredictionMatches();
    _outcomes = mockOutcomesForMatches(_matches);
    _entries = buildSortedMockGroupLeaderboard(
      matches: _matches,
      outcomesByMatchId: _outcomes,
    );
  }

  String get _matchdayLabel {
    final days = formatMatchdayDaysItalian(_matches.map((m) => m.kickoff));
    return 'giornata $_matchdayNumber - $days';
  }

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Il mio gruppo')),
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
                    _matchdayLabel,
                    style: Theme.of(context).textTheme.bodySmall,
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
                  ? const Center(child: Text('Storico giornate (in arrivo)'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      itemCount: _entries.length,
                      itemBuilder: (context, i) {
                        final e = _entries[i];
                        final badges =
                            CassandraBadgeEngine.badgesForGroupMatchday(
                              member: e.member,
                              rank: i + 1,
                              totalPlayers: _entries.length,
                              matches: _matches,
                              picksByMatchId: e.picksByMatchId,
                              outcomesByMatchId: _outcomes,
                              day: e.day,
                            );

                        final pts = formatOdds(e.day.total);

                        return Card(
                          child: ListTile(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => UserPicksPage(
                                    member: e.member,
                                    matches: _matches,
                                    picksByMatchId: e.picksByMatchId,
                                    outcomesByMatchId: _outcomes,
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
