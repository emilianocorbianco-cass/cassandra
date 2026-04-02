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

  Widget _statsRow(Widget left, Widget right) {
    return Row(
      children: [
        left,
        const SizedBox(width: 18),
        right,
      ],
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

    // Sort entries: current user first, then alphabetical.
    final sortedEntries = List<SeasonLeaderboardEntry>.of(entries)
      ..sort((a, b) {
        if (a.member.id == selectedMemberId) return -1;
        if (b.member.id == selectedMemberId) return 1;
        return a.member.uiName.toLowerCase().compareTo(
              b.member.uiName.toLowerCase(),
            );
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 90),
      children: [
        if (sortedEntries.isNotEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedMemberId,
                  isExpanded: true,
                  dropdownColor: CassandraColors.platinum,
                  items: sortedEntries.map((e) {
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
        if (entries.isNotEmpty) const SizedBox(height: 18),
        _statsRow(
          _miniStat(label: l10n.statsTotal, value: totalLabel),
          _miniStat(label: l10n.statsAvgMatchday, value: avgLabel),
        ),
        const SizedBox(height: 18),
        _statsRow(
          _miniStat(
            label: l10n.statsMatchdaysPlayed,
            value: '${s?.daysPlayed ?? 0}',
          ),
          _miniStat(label: l10n.statsAvgOdds, value: oddsLabel),
        ),
        const SizedBox(height: 18),
        _statsRow(
          _miniStat(
            label: l10n.statsTotalCorrect,
            value: '${s?.totalCorrect ?? 0}/${s?.totalMatches ?? 0}',
          ),
          _miniStat(
            label: l10n.statsMetricPercentCorrect,
            value: _formatPercent(s?.correctRate ?? 0),
          ),
        ),
        const SizedBox(height: 18),
        _statsRow(
          _miniStat(
            label: l10n.statsMetricPerfectWeeks,
            value: '${s?.perfectWeeks ?? 0}',
          ),
          _miniStat(
            label: l10n.statsAvgBonus,
            value: formatOdds(s?.averageBonusPerDay ?? 0),
          ),
        ),
        const SizedBox(height: 18),
        _statsRow(
          _miniStat(
            label: l10n.statsBestMatchday(''),
            value: bestLabel,
          ),
          _miniStat(
            label: l10n.statsWorstMatchday(''),
            value: worstLabel,
          ),
        ),
      ],
    );
  }
}
