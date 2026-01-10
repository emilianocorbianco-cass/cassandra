import 'package:flutter/material.dart';

import '../predictions/models/formatters.dart';
import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/score_breakdown.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/scoring_engine.dart';

class PredictionsMatchdayPage extends StatelessWidget {
  final int matchdayNumber;
  final List<PredictionMatch> matches;
  final Map<String, PickOption> picksByMatchId;
  final Map<String, MatchOutcome> outcomesByMatchId;
  final bool isDemoData;

  const PredictionsMatchdayPage({
    super.key,
    required this.matchdayNumber,
    required this.matches,
    required this.picksByMatchId,
    required this.outcomesByMatchId,
    this.isDemoData = false,
  });

  String _pickLabel(PickOption p) {
    switch (p) {
      case PickOption.home:
        return '1';
      case PickOption.draw:
        return 'X';
      case PickOption.away:
        return '2';
      case PickOption.homeDraw:
        return '1X';
      case PickOption.drawAway:
        return 'X2';
      case PickOption.homeAway:
        return '12';
      case PickOption.none:
        return '—';
    }
  }

  bool _isCorrect(PickOption pick, MatchOutcome outcome) {
    if (pick == PickOption.none) return false;
    if (outcome.isPending) return false;

    switch (pick) {
      case PickOption.home:
        return outcome == MatchOutcome.home;
      case PickOption.draw:
        return outcome == MatchOutcome.draw;
      case PickOption.away:
        return outcome == MatchOutcome.away;
      case PickOption.homeDraw:
        return outcome == MatchOutcome.home || outcome == MatchOutcome.draw;
      case PickOption.drawAway:
        return outcome == MatchOutcome.draw || outcome == MatchOutcome.away;
      case PickOption.homeAway:
        return outcome == MatchOutcome.home || outcome == MatchOutcome.away;
      case PickOption.none:
        return false;
    }
  }

  String _fmtPoints(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final DayScoreBreakdown day = CassandraScoringEngine.computeDayScore(
      matches: matches,
      picksByMatchId: picksByMatchId,
      outcomesByMatchId: outcomesByMatchId,
    );

    final daysLabel = formatMatchdayDaysItalian(matches.map((m) => m.kickoff));

    return Scaffold(
      appBar: AppBar(title: Text('Giornata $matchdayNumber')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(daysLabel, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Totale',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        _fmtPoints(day.total),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Expanded(child: Text('Base')),
                      Text(_fmtPoints(day.baseTotal)),
                    ],
                  ),
                  Row(
                    children: [
                      const Expanded(child: Text('Bonus')),
                      Text(day.bonusPoints.toString()),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Expanded(child: Text('Quota media giocata')),
                      Text(
                        (day.averageOddsPlayed == null)
                            ? '—'
                            : _fmtPoints(day.averageOddsPlayed!),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isDemoData
                        ? 'Dati: DEMO (fixture non storicizzate)'
                        : 'Dati: salvati',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...matches.map((m) {
            final pick = picksByMatchId[m.id] ?? PickOption.none;
            final outcome = outcomesByMatchId[m.id] ?? MatchOutcome.pending;

            final status = outcome.isPending
                ? '⏳'
                : (_isCorrect(pick, outcome) ? '✅' : '❌');

            final outcomeLabel = outcome.isPending
                ? 'in attesa'
                : (outcome == MatchOutcome.home
                      ? '1'
                      : outcome == MatchOutcome.draw
                      ? 'X'
                      : '2');

            return Card(
              child: ListTile(
                title: Text('${m.homeTeam} - ${m.awayTeam}'),
                subtitle: Text(
                  'Pick: ${_pickLabel(pick)} • Esito: $outcomeLabel',
                ),
                trailing: Text(status),
              ),
            );
          }),
        ],
      ),
    );
  }
}
