import 'package:flutter/material.dart';

import '../../app/state/app_settings.dart';
import '../../app/state/app_state.dart';
import '../../app/state/cassandra_scope.dart';
import '../predictions/models/formatters.dart';
import 'models/season_leaderboard_entry.dart';

import '../profile/user_hub_page.dart';

class MemberSeasonPage extends StatelessWidget {
  final SeasonLeaderboardEntry entry;

  const MemberSeasonPage({super.key, required this.entry});

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

    final days = entry.matchdays.toList()
      ..sort((a, b) => b.matchday.dayNumber.compareTo(a.matchday.dayNumber));

    final totalLabel = formatOdds(entry.totalPoints);
    final avgLabel = formatOdds(entry.averagePerMatchday);
    final avgOddsLabel = entry.averageOddsPlayed == null
        ? '-'
        : formatOdds(entry.averageOddsPlayed!);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.member.teamName),
            Text(
              entry.member.displayName,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
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
                        '${en ? 'Total' : 'Totale'}: $totalLabel',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${en ? 'Avg/matchday' : 'Media/giornata'}: $avgLabel',
                      ),
                      Text(
                        '${en ? 'Matchdays played' : 'Giornate giocate'}: ${entry.daysPlayed}',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${en ? 'Avg. odds' : 'Quota media'}: $avgOddsLabel',
                      ),
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
                        en
                            ? 'Matchday ${d.matchday.dayNumber}'
                            : 'Giornata ${d.matchday.dayNumber}',
                      ),
                      subtitle: Text(
                        '$dayLabel\n${en ? 'correct' : 'esatti'}: ${d.day.correctCount}/10 • bonus: ${d.day.bonusPoints}',
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
