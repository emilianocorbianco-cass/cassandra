import 'package:flutter/material.dart';

import '../../group/models/group_member.dart';
import '../../leaderboards/models/matchday_data.dart';
import '../../predictions/models/formatters.dart';
import '../../predictions/models/pick_option.dart';
import '../../scoring/models/match_outcome.dart';
import '../../scoring/scoring_engine.dart';
import 'package:cassandra/app/state/cassandra_scope.dart';

class UserPicksView extends StatelessWidget {
  final GroupMember member;
  final MatchdayData matchday;
  final Map<String, PickOption> picksByMatchId;

  const UserPicksView({
    super.key,
    required this.member,
    required this.matchday,
    required this.picksByMatchId,
  });

  @override
  Widget build(BuildContext context) {
    final cachedMatches = CassandraScope.of(context).cachedPredictionMatches;
    final day = CassandraScoringEngine.computeDayScore(
      matches: (cachedMatches ?? matchday.matches),
      picksByMatchId: picksByMatchId,
      outcomesByMatchId: matchday.outcomesByMatchId,
    );

    final breakdownById = {for (final b in day.matchBreakdowns) b.matchId: b};

    final daysLabel = formatMatchdayDaysItalian(
      (cachedMatches ?? matchday.matches).map((m) => m.kickoff),
    );
    final avgOddsLabel = day.averageOddsPlayed == null
        ? '-'
        : formatOdds(day.averageOddsPlayed!);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Giornata ${matchday.dayNumber} - $daysLabel',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Totale: ${formatOdds(day.total)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text('Base: ${formatOdds(day.baseTotal)}'),
                        Text('Bonus: ${day.bonusPoints}'),
                        const SizedBox(height: 6),
                        Text('Esatti: ${day.correctCount}/10'),
                        Text('Quota media: $avgOddsLabel'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              itemCount: (cachedMatches ?? matchday.matches).length,
              itemBuilder: (context, i) {
                final m = (cachedMatches ?? matchday.matches)[i];
                final pick = picksByMatchId[m.id] ?? PickOption.none;
                final outcome =
                    matchday.outcomesByMatchId[m.id] ?? MatchOutcome.voided;
                final b = breakdownById[m.id]!;

                IconData icon;
                if (outcome.isVoided) {
                  icon = Icons.remove_circle_outline;
                } else if (pick.isNone) {
                  icon = Icons.horizontal_rule;
                } else if (b.correct) {
                  icon = Icons.check_circle_outline;
                } else {
                  icon = Icons.cancel_outlined;
                }

                final sign = b.basePoints >= 0 ? '+' : '';
                final playedOddsLabel = b.playedOdds == null
                    ? '-'
                    : formatOdds(b.playedOdds!);

                return Card(
                  child: ListTile(
                    leading: Icon(icon),
                    title: Text('${m.homeTeam} - ${m.awayTeam}'),
                    subtitle: Text(
                      'pick ${pick.label} (quota $playedOddsLabel)  •  res ${outcome.label}\n'
                      'punti: $sign${formatOdds(b.basePoints)}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
