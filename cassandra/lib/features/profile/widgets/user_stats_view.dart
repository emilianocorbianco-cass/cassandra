import 'package:flutter/material.dart';

import '../../../app/theme/cassandra_colors.dart';
import '../../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context)!;
    final s = CassandraStatsEngine.computeForEntry(entry);

    final totalLabel = formatOdds(s.totalPoints);
    final avgLabel = formatOdds(s.averagePointsPerDay);
    final oddsLabel = s.averageOddsPlayed == null
        ? '-'
        : formatOdds(s.averageOddsPlayed!);

    final bestLabel = (s.bestDayNumber == null || s.bestDayPoints == null)
        ? '-'
        : l10n.statsBestDayShort(
            s.bestDayNumber!,
            formatOdds(s.bestDayPoints!),
          );

    final worstLabel = (s.worstDayNumber == null || s.worstDayPoints == null)
        ? '-'
        : l10n.statsWorstDayShort(
            s.worstDayNumber!,
            formatOdds(s.worstDayPoints!),
          );

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          Row(
            children: [
              _miniStat(label: l10n.statsTotal, value: totalLabel),
              _miniStat(label: l10n.statsAvgMatchday, value: avgLabel),
            ],
          ),
          Row(
            children: [
              _miniStat(
                label: l10n.statsMatchdaysPlayed,
                value: '${s.daysPlayed}',
              ),
              _miniStat(label: l10n.statsAvgOdds, value: oddsLabel),
            ],
          ),
          Row(
            children: [
              _miniStat(
                label: l10n.statsTotalCorrect,
                value: '${s.totalCorrect}/${s.totalMatches}',
              ),
              _miniStat(
                label: l10n.statsMetricPercentCorrect,
                value: _formatPercent(s.correctRate),
              ),
            ],
          ),
          Row(
            children: [
              _miniStat(
                label: l10n.statsMetricPerfectWeeks,
                value: '${s.perfectWeeks}',
              ),
              _miniStat(
                label: l10n.statsAvgBonus,
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
                  Text(
                    l10n.statsHighlights,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(l10n.statsBestMatchday(bestLabel)),
                  Text(l10n.statsWorstMatchday(worstLabel)),
                  const SizedBox(height: 8),
                  Text(l10n.statsTotalBonus('${s.totalBonus}')),
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
                  Text(
                    l10n.profileTrophiesHistory,
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
