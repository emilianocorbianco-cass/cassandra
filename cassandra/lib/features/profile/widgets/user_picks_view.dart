import 'package:flutter/material.dart';

import 'package:cassandra/app/widgets/team_name.dart';
import '../../group/models/group_member.dart';
import '../../../l10n/app_localizations.dart';
import '../../leaderboards/models/matchday_data.dart';
import '../../predictions/models/formatters.dart';
import '../../predictions/models/pick_option.dart';
import '../../scoring/models/match_outcome.dart';
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
    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isEnglish = l10n.localeName.startsWith('en');
    final cachedMatches = app.cachedPredictionMatches;
    final day = app.scoringRules.scoreRound(
      matches: (cachedMatches ?? matchday.matches),
      picksByMatchId: picksByMatchId,
      outcomesByMatchId: matchday.outcomesByMatchId,
    );

    final breakdownById = {for (final b in day.matchBreakdowns) b.matchId: b};

    final daysLabel = formatMatchdayDays(
      (cachedMatches ?? matchday.matches).map((m) => m.kickoff),
      english: isEnglish,
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
                  l10n.groupMatchdayLabel(matchday.dayNumber, daysLabel),
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
                          '${l10n.statsTotal}: ${formatOdds(day.total)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${l10n.predictionsBaseLabel}: ${formatOdds(day.baseTotal)}',
                        ),
                        Text('${l10n.groupBonusLabel}: ${day.bonusPoints}'),
                        const SizedBox(height: 6),
                        Text('${l10n.statsCorrect}: ${day.correctCount}/10'),
                        Text('${l10n.groupAvgOddsPlayedLabel}: $avgOddsLabel'),
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
                      '${l10n.groupPickLabel} ${pick.label} (${l10n.groupOddsLabel} $playedOddsLabel)  •  ${l10n.groupOutcomeLabel} ${outcome.label}\n'
                      '${l10n.leaderboardsPoints}: $sign${formatOdds(b.basePoints)}',
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
