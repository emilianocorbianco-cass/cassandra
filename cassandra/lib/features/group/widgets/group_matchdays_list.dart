import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../leaderboards/models/matchday_data.dart';
import '../../predictions/models/formatters.dart';
import '../../predictions/models/pick_option.dart';
import '../../scoring/models/match_outcome.dart';
import '../group_matchday_page.dart';
import '../models/group_member.dart';

class GroupMatchdaysList extends StatelessWidget {
  const GroupMatchdaysList({
    super.key,
    required this.matchdays,
    required this.members,
    required this.groupName,
    required this.picksByMemberByDay,
    required this.isEnglish,
    this.onRefresh,
  });

  final List<MatchdayData> matchdays;
  final List<GroupMember> members;
  final String groupName;
  final Map<int, Map<String, Map<String, PickOption>>> picksByMemberByDay;
  final bool isEnglish;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    Widget list = ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: matchdays.length,
      itemBuilder: (context, i) {
        final md = matchdays[i];

        final daysLabel = formatMatchdayDays(
          md.matches.map((m) => m.kickoff),
          english: isEnglish,
        );

        final graded = md.matches.where((m) {
          final o = md.outcomesByMatchId[m.id];
          return o != null && o != MatchOutcome.pending;
        }).length;

        final total = md.matches.length;
        final mdResultsLabel = graded == total
            ? l10n.groupResultsShort(graded, total)
            : l10n.groupResultsShortPartial(graded, total);

        final mdTitle = l10n.groupMatchdayTitle(md.dayNumber);
        final mdResultsPrefix = l10n.groupResultsPrefix;

        return Card(
          child: ListTile(
            title: Text(mdTitle),
            subtitle: Text('$daysLabel\n$mdResultsPrefix: $mdResultsLabel'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => GroupMatchdayPage(
                    matchday: md,
                    members: members,
                    groupName: groupName,
                    picksByMemberId:
                        picksByMemberByDay[md.dayNumber] ??
                        const <String, Map<String, PickOption>>{},
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (onRefresh != null) {
      list = RefreshIndicator(onRefresh: onRefresh!, child: list);
    }

    return list;
  }
}
