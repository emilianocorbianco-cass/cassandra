import 'package:flutter/material.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../leaderboards/models/matchday_data.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/models/score_breakdown.dart';
import '../scoring/scoring_engine.dart';
import 'mock_group_data.dart';
import 'models/group_member.dart';

class GroupMatchdayMemberPage extends StatelessWidget {
  const GroupMatchdayMemberPage({
    super.key,
    required this.matchday,
    required this.member,
  });

  final MatchdayData matchday;
  final GroupMember member;

  Map<String, MatchOutcome> _effectiveOutcomes(dynamic appState) {
    final saved = appState.hasSavedOutcomesForMatchday(matchday.dayNumber)
        ? appState.outcomesForMatchday(matchday.dayNumber)
        : const <String, MatchOutcome>{};

    if (saved.isEmpty) return matchday.outcomesByMatchId;

    return <String, MatchOutcome>{...matchday.outcomesByMatchId, ...saved};
  }

  Map<String, PickOption> _picksForMember(
    dynamic appState,
    List<PredictionMatch> matches,
  ) {
    final uid = appState.profile.id;

    if (member.id == uid) {
      if (appState.hasSavedPicksForMatchday(matchday.dayNumber)) {
        return appState.currentUserPicksForMatchday(matchday.dayNumber);
      }

      final current =
          appState.currentUserPicksByMatchId as Map<String, PickOption>?;
      if (current != null && current.isNotEmpty) return current;
    }

    return mockPicksForMember('${member.id}_${matchday.dayNumber}', matches);
  }

  String _pickLabel(PickOption p) {
    switch (p) {
      case PickOption.none:
        return '—';
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
    }
  }

  String _outcomeLabel(MatchOutcome o) {
    switch (o) {
      case MatchOutcome.pending:
        return '-';
      case MatchOutcome.home:
        return '1';
      case MatchOutcome.draw:
        return 'X';
      case MatchOutcome.away:
        return '2';
      case MatchOutcome.voided:
        return 'V';
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = CassandraScope.of(context);

    // safe (non notificano)
    appState.ensureCurrentUserPicksHistoryLoaded();
    appState.ensureOutcomesHistoryLoaded();
    appState.ensureCurrentUserPicksLoaded();

    final matches = matchday.matches;
    final outcomes = _effectiveOutcomes(appState);
    final picks = _picksForMember(appState, matches);

    final DayScoreBreakdown day = CassandraScoringEngine.computeDayScore(
      matches: matches,
      picksByMatchId: picks,
      outcomesByMatchId: outcomes,
    );

    final daysLabel = formatMatchdayDaysItalian(matches.map((m) => m.kickoff));

    final totalMatches = matches.length;
    final gradedCount = matches.where((m) {
      final o = outcomes[m.id] ?? MatchOutcome.pending;
      return !o.isPending;
    }).length;

    final resultsLabel = gradedCount == totalMatches
        ? 'risultati: $gradedCount/$totalMatches'
        : 'risultati: $gradedCount/$totalMatches (parziale)';

    final savedPicks =
        appState.hasSavedPicksForMatchday(matchday.dayNumber) &&
        member.id == appState.profile.id;
    final savedOutcomes = appState.hasSavedOutcomesForMatchday(
      matchday.dayNumber,
    );

    final picksTag = savedPicks ? 'PICK: SALVATI' : 'PICK: demo/runtime';
    final outcomesTag = savedOutcomes ? 'OUT: SALVATI' : 'OUT: runtime';

    return Scaffold(
      appBar: AppBar(
        title: Text('${member.teamName} • Giornata ${matchday.dayNumber}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        daysLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        resultsLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: CassandraColors.slate,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$picksTag • $outcomesTag',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: CassandraColors.slate,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _Metric(
                              label: 'Totale',
                              value: formatOdds(day.total),
                            ),
                          ),
                          Expanded(
                            child: _Metric(
                              label: 'Base',
                              value: formatOdds(day.baseTotal),
                            ),
                          ),
                          Expanded(
                            child: _Metric(
                              label: 'Bonus',
                              value: '${day.bonusPoints}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'quota media giocata: ${day.averageOddsPlayed == null ? '-' : formatOdds(day.averageOddsPlayed!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'esatti: ${day.correctCount}/$totalMatches',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: matches.length,
                itemBuilder: (context, i) {
                  final m = matches[i];
                  final pick = picks[m.id] ?? PickOption.none;
                  final outcome = outcomes[m.id] ?? MatchOutcome.pending;

                  final mb = day.matchBreakdowns.firstWhere(
                    (b) => b.matchId == m.id,
                    orElse: () => MatchScoreBreakdown(
                      matchId: m.id,
                      basePoints: 0,
                      correct: false,
                      playedOdds: null,
                      note: 'n/a',
                    ),
                  );

                  final pts = formatOdds(mb.basePoints);
                  final status = mb.correct
                      ? '✅'
                      : (outcome.isPending ? '⏳' : '❌');

                  return Card(
                    child: ListTile(
                      title: Text('${m.homeTeam} - ${m.awayTeam}'),
                      subtitle: Text(
                        'pick: ${_pickLabel(pick)} • esito: ${_outcomeLabel(outcome)}\n'
                        '${mb.note}${mb.playedOdds == null ? '' : ' • quota: ${formatOdds(mb.playedOdds!)}'}',
                      ),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(status),
                          const SizedBox(height: 4),
                          Text(
                            pts,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
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

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}
