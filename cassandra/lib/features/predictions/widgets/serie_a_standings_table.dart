import 'package:flutter/material.dart';

import 'package:cassandra/app/state/app_settings.dart';
import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/app/state/cassandra_scope.dart';
import 'package:cassandra/app/widgets/team_name.dart';
import 'package:cassandra/services/api_football/models/api_football_standing.dart';

class SerieAStandingsTable extends StatelessWidget {
  const SerieAStandingsTable({super.key, required this.standings});

  final List<ApiFootballStanding> standings;

  bool _isEnglish(BuildContext context, AppState app) {
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final en = _isEnglish(context, app);
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
            Text(
              en ? 'Serie A Standings' : 'Classifica Serie A',
              style: textTheme.titleMedium,
            ),
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
                    label: Text(en ? 'Team' : 'Squadra', style: headerStyle),
                  ),
                  DataColumn(
                    label: Text(en ? 'MP' : 'PG', style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(en ? 'W' : 'V', style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(en ? 'D' : 'P', style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(en ? 'L' : 'S', style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(en ? 'GF' : 'GF', style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(en ? 'GA' : 'GS', style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(en ? 'GD' : 'DR', style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(en ? 'Pts' : 'Pt', style: headerStyle),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text(en ? 'Last 5' : 'Ultime 5', style: headerStyle),
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
