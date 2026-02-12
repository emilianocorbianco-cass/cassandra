import 'package:flutter/material.dart';

import 'package:cassandra/app/widgets/team_name.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:cassandra/services/api_football/models/api_football_standing.dart';

class SerieAStandingsTable extends StatelessWidget {
  const SerieAStandingsTable({super.key, required this.standings});

  final List<ApiFootballStanding> standings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final headerStyle = textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final cellStyle = textTheme.bodySmall;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.serieAStandingsTitle, style: textTheme.titleMedium),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 10,
                horizontalMargin: 8,
                headingRowHeight: 32,
                dataRowMinHeight: 30,
                dataRowMaxHeight: 36,
                columns: [
                  DataColumn(label: Text('#', style: headerStyle)),
                  DataColumn(
                    label: Text(l10n.serieATeamColumn, style: headerStyle),
                  ),
                  DataColumn(
                    label: Text(l10n.serieAPlayedColumn, style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(l10n.serieAWinsColumn, style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(l10n.serieADrawsColumn, style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(l10n.serieALossesColumn, style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text('GF', style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(
                      l10n.serieAGoalsAgainstColumn,
                      style: headerStyle,
                    ),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(l10n.serieAGoalDiffColumn, style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(l10n.serieAPointsColumn, style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(l10n.serieALastFiveColumn, style: headerStyle),
                  ),
                ],
                rows: standings.map((s) {
                  return DataRow(
                    cells: [
                      DataCell(Text('${s.rank}', style: cellStyle)),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: TeamName(
                            name: s.teamName,
                            logoUrl: s.teamLogo,
                            style: cellStyle?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      DataCell(Text('${s.played}', style: cellStyle)),
                      DataCell(Text('${s.wins}', style: cellStyle)),
                      DataCell(Text('${s.draws}', style: cellStyle)),
                      DataCell(Text('${s.losses}', style: cellStyle)),
                      DataCell(Text('${s.goalsFor}', style: cellStyle)),
                      DataCell(Text('${s.goalsAgainst}', style: cellStyle)),
                      DataCell(Text('${s.goalDiff}', style: cellStyle)),
                      DataCell(
                        Text(
                          '${s.points}',
                          style: cellStyle?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      DataCell(_FormDots(form: s.form)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormDots extends StatelessWidget {
  const _FormDots({this.form});

  final String? form;

  @override
  Widget build(BuildContext context) {
    final f = form;
    if (f == null || f.isEmpty) return const SizedBox.shrink();

    // Prendi le ultime 5 lettere
    final chars = f.length > 5 ? f.substring(f.length - 5) : f;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: chars.split('').map((c) {
        final Color color;
        switch (c.toUpperCase()) {
          case 'W':
            color = Colors.green;
            break;
          case 'D':
            color = Colors.grey;
            break;
          case 'L':
            color = Colors.red;
            break;
          default:
            color = Colors.grey.shade300;
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        );
      }).toList(),
    );
  }
}
