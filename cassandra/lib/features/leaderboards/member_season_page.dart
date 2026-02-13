import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../predictions/models/formatters.dart';
import 'models/season_leaderboard_entry.dart';

import '../profile/user_hub_page.dart';

class MemberSeasonPage extends StatelessWidget {
  final SeasonLeaderboardEntry entry;

  const MemberSeasonPage({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final en = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('en');

    final days = entry.matchdays.toList()
      ..sort((a, b) => b.matchday.dayNumber.compareTo(a.matchday.dayNumber));

    final totalLabel = formatOdds(entry.totalPoints);
    final avgLabel = formatOdds(entry.averagePerMatchday);
    final avgOddsLabel = entry.averageOddsPlayed == null
        ? '-'
        : formatOdds(entry.averageOddsPlayed!);

    return Scaffold(
      appBar: AppBar(title: Text(entry.member.uiName)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${l10n.statsTotal}: $totalLabel',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text('${l10n.statsAvgMatchday}: $avgLabel'),
                      Text('${l10n.statsMatchdaysPlayed}: ${entry.daysPlayed}'),
                      const SizedBox(height: 6),
                      Text('${l10n.statsAvgOdds}: $avgOddsLabel'),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: days.length,
                itemBuilder: (context, i) {
                  final d = days[i];
                  final dayLabel = formatMatchdayDays(
                    d.matchday.matches.map((m) => m.kickoff),
                    english: en,
                  );

                  final pts = d.day.total;
                  final ptsLabel = formatOdds(pts);
                  final sign = pts >= 0 ? '+' : '';

                  return Card(
                    child: ListTile(
                      title: Text(
                        l10n.groupMatchdayTitle(d.matchday.dayNumber),
                      ),
                      subtitle: Text(
                        '$dayLabel\n${l10n.statsCorrect}: ${d.day.correctCount}/10 • bonus: ${d.day.bonusPoints}',
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        '$sign$ptsLabel',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onTap: () {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => UserHubPage(
                              member: entry.member,
                              matchday: d.matchday,
                              picksByMatchId: d.picksByMatchId,
                              initialTabIndex: 0,
                            ),
                          ),
                        );
                      },
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
