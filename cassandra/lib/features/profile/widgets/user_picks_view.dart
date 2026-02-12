import 'package:flutter/material.dart';

import 'package:cassandra/app/widgets/team_name.dart';
import '../../../app/state/app_settings.dart';
import '../../../app/state/app_state.dart';
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

  bool _isEnglish(BuildContext context, AppState app) {
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final en = _isEnglish(context, app);
    final cachedMatches = app.cachedPredictionMatches;
    final day = CassandraScoringEngine.computeDayScore(
      matches: (cachedMatches ?? matchday.matches),
      picksByMatchId: picksByMatchId,
      outcomesByMatchId: matchday.outcomesByMatchId,
    );

    final breakdownById = {for (final b in day.matchBreakdowns) b.matchId: b};

    final daysLabel = formatMatchdayDays(
      (cachedMatches ?? matchday.matches).map((m) => m.kickoff),
      english: en,
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
                  '${en ? 'Matchday' : 'Giornata'} ${matchday.dayNumber} - $daysLabel',
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
                          '${en ? 'Total' : 'Totale'}: ${formatOdds(day.total)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text('Base: ${formatOdds(day.baseTotal)}'),
                        Text('Bonus: ${day.bonusPoints}'),
                        const SizedBox(height: 6),
                        Text(
                          '${en ? 'Correct' : 'Esatti'}: ${day.correctCount}/10',
                        ),
                        Text(
                          '${en ? 'Avg. odds' : 'Quota media'}: $avgOddsLabel',
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
                      'pick ${pick.label} (${en ? 'odds' : 'quota'} $playedOddsLabel)  •  ${en ? 'result' : 'res'} ${outcome.label}\n'
                      '${en ? 'points' : 'punti'}: $sign${formatOdds(b.basePoints)}',
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
