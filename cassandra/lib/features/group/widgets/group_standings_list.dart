import 'package:flutter/material.dart';

import '../../../app/theme/cassandra_colors.dart';
import '../../badges/badge_engine.dart';
import '../../badges/widgets/avatar_with_badges.dart';
import '../../leaderboards/models/matchday_data.dart';
import '../../predictions/models/formatters.dart';
import '../../predictions/models/prediction_match.dart';
import '../../profile/user_hub_page.dart';
import '../../scoring/models/match_outcome.dart';
import '../models/general_leaderboard_entry.dart';

class GroupStandingsList extends StatelessWidget {
  const GroupStandingsList({
    super.key,
    required this.entries,
    required this.currentMatches,
    required this.outcomesByMatchId,
    required this.currentMatchdayNumber,
    this.onRefresh,
  });

  final List<GeneralLeaderboardEntry> entries;
  final List<PredictionMatch> currentMatches;
  final Map<String, MatchOutcome> outcomesByMatchId;
  final int currentMatchdayNumber;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    Widget list = ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];

        final badges = CassandraBadgeEngine.badgesForGroupMatchday(
          member: e.member,
          rank: i + 1,
          totalPlayers: entries.length,
          matches: currentMatches,
          picksByMatchId: e.currentDayPicksByMatchId,
          outcomesByMatchId: outcomesByMatchId,
          day: e.currentDay,
        );

        final pts = formatOdds(e.totalPoints);

        return Card(
          child: ListTile(
            onTap: () {
              final md = MatchdayData(
                dayNumber: currentMatchdayNumber,
                matches: currentMatches,
                outcomesByMatchId: outcomesByMatchId,
              );

              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => UserHubPage(
                    member: e.member,
                    matchday: md,
                    picksByMatchId: e.currentDayPicksByMatchId,
                    initialTabIndex: 0,
                  ),
                ),
              );
            },
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
                    text: e.member.avatarInitial,
                    badges: badges,
                    imagePathOrUrl: e.member.photoUrl,
                  ),
                ],
              ),
            ),
            title: Text(e.member.uiName),
            trailing: Text(
              pts,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: e.totalPoints >= 0
                    ? CassandraColors.primary
                    : CassandraColors.slate,
              ),
            ),
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
