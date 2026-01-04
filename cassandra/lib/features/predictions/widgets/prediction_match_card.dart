import 'package:flutter/material.dart';
import '../models/pick_option.dart';
import '../models/prediction_match.dart';
import '../models/formatters.dart';
import 'odds_button.dart';

class PredictionMatchCard extends StatelessWidget {
  final PredictionMatch match;
  final PickOption pick;
  final bool locked;
  final ValueChanged<PickOption> onPick;
  final VoidCallback onClear;

  const PredictionMatchCard({
    super.key,
    required this.match,
    required this.pick,
    required this.locked,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    match.homeTeam,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const Text('vs'),
                Expanded(
                  child: Text(
                    match.awayTeam,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Kickoff: ${formatKickoff(match.kickoff)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),

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
            Text('Doppia chance', style: Theme.of(context).textTheme.bodySmall),
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

            if (!pick.isNone) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: locked ? null : onClear,
                  child: const Text('Azzera scelta'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
