import 'package:flutter/material.dart';

import '../../app/theme/cassandra_colors.dart';
import '../leaderboards/models/matchday_data.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/scoring_engine.dart';
import 'models/formatters.dart';
import 'models/pick_option.dart';

class PredictionsMatchdayPage extends StatelessWidget {
  const PredictionsMatchdayPage({
    super.key,
    required this.matchday,
    required this.picksByMatchId,
    this.tag,
  });

  final MatchdayData matchday;
  final Map<String, PickOption> picksByMatchId;
  final String? tag;

  String _daysLabel() =>
      formatMatchdayDaysItalian(matchday.matches.map((m) => m.kickoff));

  String _resultsLabel() {
    final total = matchday.matches.length;
    final graded = matchday.matches.where((m) {
      final o = matchday.outcomesByMatchId[m.id] ?? MatchOutcome.pending;
      return !o.isPending;
    }).length;

    return graded == total
        ? 'risultati: $graded/$total'
        : 'risultati: $graded/$total (parziale)';
  }

  @override
  Widget build(BuildContext context) {
    final day = CassandraScoringEngine.computeDayScore(
      matches: matchday.matches,
      picksByMatchId: picksByMatchId,
      outcomesByMatchId: matchday.outcomesByMatchId,
    );

    final byId = {for (final b in day.matchBreakdowns) b.matchId: b};

    final title = tag == null
        ? 'Giornata ${matchday.dayNumber}'
        : 'Giornata ${matchday.dayNumber} ($tag)';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _daysLabel(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _resultsLabel(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CassandraColors.slate,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Totale: ${formatOdds(day.total)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text('Base: ${formatOdds(day.baseTotal)}'),
                          Text('Bonus: ${day.bonusPoints}'),
                          const SizedBox(height: 6),
                          Text(
                            'Esatti: ${day.correctCount}/${matchday.matches.length}',
                          ),
                          Text(
                            'Quota media: ${day.averageOddsPlayed == null ? '-' : formatOdds(day.averageOddsPlayed!)}',
                          ),
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
                itemCount: matchday.matches.length,
                itemBuilder: (context, i) {
                  final m = matchday.matches[i];
                  final pick = picksByMatchId[m.id] ?? PickOption.none;
                  final outcome =
                      matchday.outcomesByMatchId[m.id] ?? MatchOutcome.pending;

                  final b = byId[m.id];
                  final points = b?.basePoints ?? 0;
                  final sign = points >= 0 ? '+' : '';
                  final pointsLabel = '$sign${formatOdds(points)}';

                  final oddsLabel = b?.playedOdds == null
                      ? '-'
                      : formatOdds(b!.playedOdds!);

                  return Card(
                    child: ListTile(
                      title: Text('${m.homeTeam} - ${m.awayTeam}'),
                      subtitle: Text(
                        'pick ${pick.label} (quota $oddsLabel)  •  res ${outcome.label}\n'
                        'punti: $pointsLabel',
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
