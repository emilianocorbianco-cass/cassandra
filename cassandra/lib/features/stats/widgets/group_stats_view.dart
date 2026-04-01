import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../../app/theme/cassandra_colors.dart';
import '../../badges/widgets/avatar_with_badges.dart';
import '../../leaderboards/models/season_leaderboard_entry.dart';
import '../../predictions/models/formatters.dart';
import '../models/group_metric.dart';
import '../models/player_season_stats.dart';
import '../stats_engine.dart';

class GroupStatsView extends StatelessWidget {
  const GroupStatsView({
    super.key,
    required this.entries,
    required this.metric,
    required this.onMetricChanged,
  });

  final List<SeasonLeaderboardEntry> entries;
  final GroupMetric metric;
  final ValueChanged<GroupMetric> onMetricChanged;

  String _formatPercent(double v) {
    return '${(v * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  List<PlayerSeasonStats> _sortedGroup() {
    final list = CassandraStatsEngine.computeForEntries(entries);

    int cmp(PlayerSeasonStats a, PlayerSeasonStats b) {
      switch (metric) {
        case GroupMetric.avgPoints:
          final t = b.averagePointsPerDay.compareTo(a.averagePointsPerDay);
          if (t != 0) return t;
          return b.totalPoints.compareTo(a.totalPoints);

        case GroupMetric.totalPoints:
          final t = b.totalPoints.compareTo(a.totalPoints);
          if (t != 0) return t;
          return b.averagePointsPerDay.compareTo(a.averagePointsPerDay);

        case GroupMetric.correctRate:
          final t = b.correctRate.compareTo(a.correctRate);
          if (t != 0) return t;
          return b.totalCorrect.compareTo(a.totalCorrect);

        case GroupMetric.perfectWeeks:
          final t = b.perfectWeeks.compareTo(a.perfectWeeks);
          if (t != 0) return t;
          return b.averagePointsPerDay.compareTo(a.averagePointsPerDay);
      }
    }

    list.sort(cmp);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sorted = _sortedGroup();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: SegmentedButton<GroupMetric>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: GroupMetric.avgPoints,
                label: Text(l10n.statsMetricAverage),
              ),
              ButtonSegment(
                value: GroupMetric.totalPoints,
                label: Text(l10n.statsMetricTotal),
              ),
              ButtonSegment(
                value: GroupMetric.correctRate,
                label: Text(l10n.statsMetricPercentCorrect),
              ),
              const ButtonSegment(
                value: GroupMetric.perfectWeeks,
                label: Text('10/10'),
              ),
            ],
            selected: {metric},
            onSelectionChanged: (s) => onMetricChanged(s.first),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 90),
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final p = sorted[i];

              String valueLabel;
              switch (metric) {
                case GroupMetric.avgPoints:
                  valueLabel = formatOdds(p.averagePointsPerDay);
                  break;
                case GroupMetric.totalPoints:
                  valueLabel = formatOdds(p.totalPoints);
                  break;
                case GroupMetric.correctRate:
                  valueLabel = _formatPercent(p.correctRate);
                  break;
                case GroupMetric.perfectWeeks:
                  valueLabel = '${p.perfectWeeks}';
                  break;
              }

              return Card(
                child: ListTile(
                  leading: SizedBox(
                    width: 64,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${i + 1}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: CassandraColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AvatarWithBadges(
                          radius: 18,
                          backgroundColor: CassandraColors.primary,
                          text: p.member.avatarInitial,
                          badges: const [],
                          imagePathOrUrl: p.member.photoUrl,
                        ),
                      ],
                    ),
                  ),
                  title: Text(p.member.uiName),
                  subtitle: Text(
                    '${l10n.statsMatchdays}: ${p.daysPlayed} • '
                    '${l10n.statsCorrect}: ${p.totalCorrect}/${p.totalMatches}',
                  ),
                  trailing: Text(
                    valueLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
