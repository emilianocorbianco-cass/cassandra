import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../../app/theme/cassandra_colors.dart';
import '../../badges/widgets/avatar_with_badges.dart';
import '../../leaderboards/models/season_leaderboard_entry.dart';
import '../../predictions/models/formatters.dart';
import '../models/player_season_stats.dart';
import 'stats_mini_card.dart';

class PersonalStatsView extends StatelessWidget {
  const PersonalStatsView({
    super.key,
    required this.entries,
    required this.stats,
    required this.selectedMemberId,
    required this.onMemberSelected,
    required this.loading,
  });

  final List<SeasonLeaderboardEntry> entries;
  final PlayerSeasonStats? stats;
  final String? selectedMemberId;
  final ValueChanged<String?> onMemberSelected;
  final bool loading;

  String _formatPercent(double v) {
    return '${(v * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  Widget _miniStat({required String label, required String value}) {
    return Expanded(
      child: StatsMiniCard(label: label, value: value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final s = stats;

    final totalLabel = s == null ? '0,00' : formatOdds(s.totalPoints);
    final avgLabel = s == null ? '0,00' : formatOdds(s.averagePointsPerDay);
    final oddsLabel = (s == null || s.averageOddsPlayed == null)
        ? '-'
        : formatOdds(s.averageOddsPlayed!);

    final bestLabel =
        (s == null || s.bestDayNumber == null || s.bestDayPoints == null)
        ? '-'
        : 'G${s.bestDayNumber}: ${formatOdds(s.bestDayPoints!)}';

    final worstLabel =
        (s == null || s.worstDayNumber == null || s.worstDayPoints == null)
        ? '-'
        : 'G${s.worstDayNumber}: ${formatOdds(s.worstDayPoints!)}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
      children: [
        if (entries.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedMemberId,
                  isExpanded: true,
                  dropdownColor: CassandraColors.platinum,
                  items: entries.map((e) {
                    return DropdownMenuItem(
                      value: e.member.id,
                      child: Row(
                        children: [
                          AvatarWithBadges(
                            radius: 14,
                            backgroundColor: CassandraColors.primary,
                            text: e.member.avatarInitial,
                            badges: const [],
                            imagePathOrUrl: e.member.photoUrl,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              e.member.uiName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: loading ? null : onMemberSelected,
                ),
              ),
            ),
          ),
        if (entries.isNotEmpty) const SizedBox(height: 10),
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
              value: '${s?.daysPlayed ?? 0}',
            ),
            _miniStat(label: l10n.statsAvgOdds, value: oddsLabel),
          ],
        ),
        Row(
          children: [
            _miniStat(
              label: l10n.statsTotalCorrect,
              value: '${s?.totalCorrect ?? 0}/${s?.totalMatches ?? 0}',
            ),
            _miniStat(
              label: l10n.statsMetricPercentCorrect,
              value: _formatPercent(s?.correctRate ?? 0),
            ),
          ],
        ),
        Row(
          children: [
            _miniStat(
              label: l10n.statsMetricPerfectWeeks,
              value: '${s?.perfectWeeks ?? 0}',
            ),
            _miniStat(
              label: l10n.statsAvgBonus,
              value: formatOdds(s?.averageBonusPerDay ?? 0),
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
                Text(l10n.statsTotalBonus('${s?.totalBonus ?? 0}')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
