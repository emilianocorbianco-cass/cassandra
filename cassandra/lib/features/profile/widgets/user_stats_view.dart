import 'package:flutter/material.dart';

import '../../../app/theme/cassandra_colors.dart';
import '../../badges/models/badge_counts.dart';
import '../../badges/models/badge_type.dart';
import '../../leaderboards/models/season_leaderboard_entry.dart';
import '../../predictions/models/formatters.dart';
import '../../stats/stats_engine.dart';

class UserStatsView extends StatelessWidget {
  final SeasonLeaderboardEntry entry;
  final BadgeCounts trophies;

  const UserStatsView({super.key, required this.entry, required this.trophies});

  String _formatPercent(double v) {
    return '${(v * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  Widget _miniStat({required String label, required String value}) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: CassandraColors.slate,
                ),
              ),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trophyChip(BadgeType type, int count) {
    Widget icon;
    switch (type) {
      case BadgeType.crown:
        icon = const Icon(Icons.workspace_premium, size: 16);
        break;
      case BadgeType.eyes:
        icon = const Icon(Icons.remove_red_eye, size: 16);
        break;
      case BadgeType.owl:
        icon = const Text('🦉');
        break;
      case BadgeType.loser:
        icon = const Text('L', style: TextStyle(fontWeight: FontWeight.w900));
        break;
    }

    return Chip(label: Text('$count'), avatar: icon);
  }

  @override
  Widget build(BuildContext context) {
    final s = CassandraStatsEngine.computeForEntry(entry);

    final totalLabel = formatOdds(s.totalPoints);
    final avgLabel = formatOdds(s.averagePointsPerDay);
    final oddsLabel = s.averageOddsPlayed == null
        ? '-'
        : formatOdds(s.averageOddsPlayed!);

    final bestLabel = (s.bestDayNumber == null || s.bestDayPoints == null)
        ? '-'
        : 'G${s.bestDayNumber}: ${formatOdds(s.bestDayPoints!)}';

    final worstLabel = (s.worstDayNumber == null || s.worstDayPoints == null)
        ? '-'
        : 'G${s.worstDayNumber}: ${formatOdds(s.worstDayPoints!)}';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          Row(
            children: [
              _miniStat(label: 'totale', value: totalLabel),
              _miniStat(label: 'media/giornata', value: avgLabel),
            ],
          ),
          Row(
            children: [
              _miniStat(label: 'giornate giocate', value: '${s.daysPlayed}'),
              _miniStat(label: 'quota media', value: oddsLabel),
            ],
          ),
          Row(
            children: [
              _miniStat(
                label: 'esatti totali',
                value: '${s.totalCorrect}/${s.totalMatches}',
              ),
              _miniStat(
                label: '% esatti',
                value: _formatPercent(s.correctRate),
              ),
            ],
          ),
          Row(
            children: [
              _miniStat(
                label: 'settimane perfette',
                value: '${s.perfectWeeks}',
              ),
              _miniStat(
                label: 'bonus medio',
                value: formatOdds(s.averageBonusPerDay),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Highlights',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text('Miglior giornata: $bestLabel'),
                  Text('Peggior giornata: $worstLabel'),
                  const SizedBox(height: 8),
                  Text('Bonus totale: ${s.totalBonus}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Trofei (storico)',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _trophyChip(
                        BadgeType.crown,
                        trophies.of(BadgeType.crown),
                      ),
                      _trophyChip(BadgeType.eyes, trophies.of(BadgeType.eyes)),
                      _trophyChip(BadgeType.owl, trophies.of(BadgeType.owl)),
                      _trophyChip(
                        BadgeType.loser,
                        trophies.of(BadgeType.loser),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
