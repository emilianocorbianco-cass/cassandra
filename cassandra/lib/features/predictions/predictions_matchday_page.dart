import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../app/widgets/team_name.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/score_breakdown.dart';
import '../scoring/models/match_outcome.dart';
import '../../app/state/cassandra_scope.dart';

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
    final l10n = AppLocalizations.of(context)!;
    final en = l10n.localeName.startsWith('en');
    final appState = CassandraScope.of(context);

    final DayScoreBreakdown day = appState.scoringRules.scoreRound(
      matches: matches,
      picksByMatchId: picksByMatchId,
      outcomesByMatchId: outcomesByMatchId,
    );

    final daysLabel = formatMatchdayDays(
      matches.map((m) => m.kickoff),
      english: en,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.groupMatchdayTitle(matchdayNumber))),
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
                          l10n.statsTotal,
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
                      Expanded(child: Text(l10n.predictionsBaseLabel)),
                      Text(_fmtPoints(day.baseTotal)),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.groupBonusLabel)),
                      Text(day.bonusPoints.toString()),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.groupAvgOddsPlayedLabel)),
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
                        ? l10n.predictionsDataDemoFixturesNotSaved
                        : l10n.predictionsDataSaved,
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
                ? l10n.predictionsOutcomePending
                : (outcome == MatchOutcome.home
                      ? '1'
                      : outcome == MatchOutcome.draw
                      ? 'X'
                      : '2');

            return Card(
              child: ListTile(
                title: Row(
                  children: [
                    Expanded(
                      child: TeamName(
                        name: m.homeTeam,
                        logoUrl: m.homeTeamLogo,
                      ),
                    ),
                    const Text(' - '),
                    Expanded(
                      child: TeamName(
                        name: m.awayTeam,
                        logoUrl: m.awayTeamLogo,
                        reversed: true,
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '${l10n.groupPickLabel}: ${_pickLabel(pick)} • ${l10n.groupOutcomeLabel}: $outcomeLabel',
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
