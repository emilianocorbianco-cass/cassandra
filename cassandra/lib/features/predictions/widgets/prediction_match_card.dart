import 'package:flutter/material.dart';
import '../../../app/theme/cassandra_colors.dart';
import '../../../app/widgets/team_name.dart';
import '../models/pick_option.dart';
import '../models/prediction_match.dart';
import '../models/formatters.dart';
import 'odds_button.dart';

class PredictionMatchCard extends StatelessWidget {
  final PredictionMatch match;
  final PickOption pick;
  final bool locked;
  final ValueChanged<PickOption> onPick;

  const PredictionMatchCard({
    super.key,
    required this.match,
    required this.pick,
    required this.locked,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final baseTeamSize =
        Theme.of(context).textTheme.titleMedium?.fontSize ?? 18;
    final teamTextStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: CassandraColors.slate,
      fontSize: baseTeamSize + 2,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: CassandraColors.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TeamName(
                    name: match.homeTeam,
                    logoUrl: match.homeTeamLogo,
                    style: teamTextStyle,
                    logoScale: 1.1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    formatKickoff(match.kickoff),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: CassandraColors.slate,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: TeamName(
                    name: match.awayTeam,
                    logoUrl: match.awayTeamLogo,
                    style: teamTextStyle,
                    logoScale: 1.1,
                    textAlign: TextAlign.end,
                    reversed: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Singole
            Row(
              children: [
                OddsButton(
                  label: '1',
                  odds: match.odds.home,
                  selected: pick == PickOption.home,
                  locked: locked,
                  onPressed: () => onPick(PickOption.home),
                ),
                OddsButton(
                  label: 'X',
                  odds: match.odds.draw,
                  selected: pick == PickOption.draw,
                  locked: locked,
                  onPressed: () => onPick(PickOption.draw),
                ),
                OddsButton(
                  label: '2',
                  odds: match.odds.away,
                  selected: pick == PickOption.away,
                  locked: locked,
                  onPressed: () => onPick(PickOption.away),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Doppie
            Row(
              children: [
                OddsButton(
                  label: '1X',
                  odds: match.odds.homeDraw,
                  selected: pick == PickOption.homeDraw,
                  locked: locked,
                  onPressed: () => onPick(PickOption.homeDraw),
                ),
                OddsButton(
                  label: 'X2',
                  odds: match.odds.drawAway,
                  selected: pick == PickOption.drawAway,
                  locked: locked,
                  onPressed: () => onPick(PickOption.drawAway),
                ),
                OddsButton(
                  label: '12',
                  odds: match.odds.homeAway,
                  selected: pick == PickOption.homeAway,
                  locked: locked,
                  onPressed: () => onPick(PickOption.homeAway),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
