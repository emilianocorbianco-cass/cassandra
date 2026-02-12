import 'package:flutter/material.dart';

import '../../app/state/app_settings.dart';
import '../../app/state/app_state.dart';
import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../leaderboards/mock_season_data.dart';
import '../leaderboards/models/season_leaderboard_entry.dart';
import '../predictions/models/formatters.dart';
import 'models/player_season_stats.dart';
import 'stats_engine.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

enum GroupMetric { avgPoints, totalPoints, correctRate, perfectWeeks }

class _StatsPageState extends State<StatsPage> {
  int _segment = 0; // 0 = personali, 1 = gruppo
  GroupMetric _metric = GroupMetric.avgPoints;

  late final List<SeasonLeaderboardEntry> _entries;
  late final List<PlayerSeasonStats> _stats;

  String? _selectedMemberId;

  bool _isEnglish(AppState app) {
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  String _t(AppState app, String it, String en) => _isEnglish(app) ? en : it;

  @override
  void initState() {
    super.initState();

    // Coerente con Classifiche: 5 giornate demo (16–20)
    final matchdays = mockSeasonMatchdays(startDay: 16, count: 5);
    _entries = buildMockSeasonLeaderboardEntries(matchdays: matchdays);
    _stats = CassandraStatsEngine.computeForEntries(_entries);

    // Default: Emiliano se esiste, altrimenti primo
    final preferred = _entries.where((e) => e.member.id == 'u6').toList();
    _selectedMemberId = preferred.isNotEmpty
        ? preferred.first.member.id
        : _entries.first.member.id;
  }

  SeasonLeaderboardEntry get _selectedEntry {
    return _entries.firstWhere((e) => e.member.id == _selectedMemberId);
  }

  PlayerSeasonStats get _selectedStats {
    return CassandraStatsEngine.computeForEntry(_selectedEntry);
  }

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  String _formatPercent(double v) {
    return '${(v * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
  }

  List<PlayerSeasonStats> _sortedGroup() {
    final list = List<PlayerSeasonStats>.of(_stats);

    int cmp(PlayerSeasonStats a, PlayerSeasonStats b) {
      switch (_metric) {
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

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final s = _selectedStats;

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

    return Scaffold(
      appBar: AppBar(title: Text(_t(app, 'Statistiche', 'Stats'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 0,
                        label: Text(_t(app, 'personali', 'personal')),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text(_t(app, 'gruppo', 'group')),
                      ),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (s) =>
                        setState(() => _segment = s.first),
                  ),
                  const SizedBox(height: 10),
                  if (_segment == 0)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedMemberId,
                            isExpanded: true,
                            items: _entries.map((e) {
                              return DropdownMenuItem(
                                value: e.member.id,
                                child: Text(
                                  '${e.member.displayName} • ${e.member.teamName}',
                                ),
                              );
                            }).toList(),
                            onChanged: (v) =>
                                setState(() => _selectedMemberId = v),
                          ),
                        ),
                      ),
                    ),
                  if (_segment == 1) ...[
                    SegmentedButton<GroupMetric>(
                      segments: [
                        ButtonSegment(
                          value: GroupMetric.avgPoints,
                          label: Text(_t(app, 'media', 'average')),
                        ),
                        ButtonSegment(
                          value: GroupMetric.totalPoints,
                          label: Text(_t(app, 'totale', 'total')),
                        ),
                        ButtonSegment(
                          value: GroupMetric.correctRate,
                          label: Text(_t(app, '% esatti', '% correct')),
                        ),
                        ButtonSegment(
                          value: GroupMetric.perfectWeeks,
                          label: const Text('10/10'),
                        ),
                      ],
                      selected: {_metric},
                      onSelectionChanged: (s) =>
                          setState(() => _metric = s.first),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _segment == 0
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      children: [
                        Row(
                          children: [
                            _miniStat(
                              label: _t(app, 'totale', 'total'),
                              value: totalLabel,
                            ),
                            _miniStat(
                              label: _t(app, 'media/giornata', 'avg/matchday'),
                              value: avgLabel,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            _miniStat(
                              label: _t(
                                app,
                                'giornate giocate',
                                'matchdays played',
                              ),
                              value: '${s.daysPlayed}',
                            ),
                            _miniStat(
                              label: _t(app, 'quota media', 'avg odds'),
                              value: oddsLabel,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            _miniStat(
                              label: _t(app, 'esatti totali', 'total correct'),
                              value: '${s.totalCorrect}/${s.totalMatches}',
                            ),
                            _miniStat(
                              label: _t(app, '% esatti', '% correct'),
                              value: _formatPercent(s.correctRate),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            _miniStat(
                              label: _t(
                                app,
                                'settimane perfette',
                                'perfect weeks',
                              ),
                              value: '${s.perfectWeeks}',
                            ),
                            _miniStat(
                              label: _t(app, 'bonus medio', 'avg bonus'),
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
                                  'Highlights',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '${_t(app, 'Miglior giornata', 'Best matchday')}: $bestLabel',
                                ),
                                Text(
                                  '${_t(app, 'Peggior giornata', 'Worst matchday')}: $worstLabel',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_t(app, 'Bonus totale', 'Total bonus')}: ${s.totalBonus}',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      itemCount: _sortedGroup().length,
                      itemBuilder: (context, i) {
                        final p = _sortedGroup()[i];

                        String valueLabel;
                        switch (_metric) {
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
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: _avatarColorFromSeed(
                                      p.member.avatarSeed,
                                    ),
                                    child: Text(
                                      p.member.displayName
                                          .substring(0, 1)
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            title: Text(p.member.displayName),
                            subtitle: Text(
                              '${p.member.teamName}\n'
                              '${_t(app, 'giornate', 'matchdays')}: ${p.daysPlayed} • '
                              '${_t(app, 'esatti', 'correct')}: ${p.totalCorrect}/${p.totalMatches}',
                            ),
                            isThreeLine: true,
                            trailing: Text(
                              valueLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
