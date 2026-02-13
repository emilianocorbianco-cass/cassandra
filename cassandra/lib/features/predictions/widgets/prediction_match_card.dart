import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';
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

  Widget _metaChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    Color? borderColor,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final fg = foregroundColor ?? CassandraColors.primary;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor ?? CassandraColors.bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color:
                borderColor ?? CassandraColors.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final teamTextStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: CassandraColors.primary,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: CassandraColors.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
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
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    l10n.commonVersusShort,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: CassandraColors.slate,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: TeamName(
                    name: match.awayTeam,
                    logoUrl: match.awayTeamLogo,
                    style: teamTextStyle,
                    textAlign: TextAlign.end,
                    reversed: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metaChip(
                  context,
                  icon: Icons.schedule_outlined,
                  label:
                      '${l10n.kickoffLabel}: ${formatKickoff(match.kickoff)}',
                ),
              ],
            ),
            const SizedBox(height: 12),

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

            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.call_split_outlined,
                  size: 14,
                  color: CassandraColors.slate,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.predictionsDoubleChance,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CassandraColors.slate,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

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
