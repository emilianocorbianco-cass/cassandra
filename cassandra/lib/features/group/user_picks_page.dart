import 'package:flutter/material.dart';

import '../predictions/models/formatters.dart';
import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/scoring_engine.dart';

import 'models/group_member.dart';

class UserPicksPage extends StatelessWidget {
  final GroupMember member;
  final List<PredictionMatch> matches;
  final Map<String, PickOption> picksByMatchId;
  final Map<String, MatchOutcome> outcomesByMatchId;

  const UserPicksPage({
    super.key,
    required this.member,
    required this.matches,
    required this.picksByMatchId,
    required this.outcomesByMatchId,
  });

  @override
  Widget build(BuildContext context) {
    final day = CassandraScoringEngine.computeDayScore(
      matches: matches,
      picksByMatchId: picksByMatchId,
      outcomesByMatchId: outcomesByMatchId,
    );

    final breakdownById = {for (final b in day.matchBreakdowns) b.matchId: b};

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(member.teamName),
            Text(
              member.displayName,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),

      body: SafeArea(
        child: Column(
          children: [
            // Summary
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Totale: ${formatOdds(day.total)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text('Base: ${formatOdds(day.baseTotal)}'),
                      Text('Bonus: ${day.bonusPoints}'),
                      const SizedBox(height: 6),
                      Text('Esatti: ${day.correctCount}/10'),
                      Text(
                        'Quota media: ${day.averageOddsPlayed == null ? '-' : formatOdds(day.averageOddsPlayed!)}',
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Divider(height: 1),

            // Picks list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: matches.length,
                itemBuilder: (context, i) {
                  final m = matches[i];
                  final pick = picksByMatchId[m.id] ?? PickOption.none;
                  final outcome =
                      outcomesByMatchId[m.id] ?? MatchOutcome.voided;
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
      ),
    );
  }
}
