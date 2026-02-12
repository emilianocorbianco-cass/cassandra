import 'package:flutter/material.dart';

import '../../../app/theme/cassandra_colors.dart';
import '../../badges/badge_engine.dart';
import '../../badges/widgets/avatar_with_badges.dart';
import '../../predictions/models/formatters.dart';
import '../../predictions/models/pick_option.dart';
import '../../predictions/models/prediction_match.dart';
import '../../scoring/models/match_outcome.dart';
import '../mock_group_data.dart';
import '../models/group_member.dart';

class GroupMatchdayLeaderboard extends StatelessWidget {
  const GroupMatchdayLeaderboard({
    super.key,
    required this.matches,
    required this.outcomesByMatchId,
    required this.members,
    this.overridePicksByMemberId = const {},
  });

  final List<PredictionMatch> matches;
  final Map<String, MatchOutcome> outcomesByMatchId;
  final List<GroupMember> members;
  final Map<String, Map<String, PickOption>> overridePicksByMemberId;

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final entries = buildSortedMockGroupLeaderboard(
      matches: matches,
      outcomesByMatchId: outcomesByMatchId,
      members: members,
      overridePicksByMemberId: overridePicksByMemberId,
    );

    if (entries.isEmpty) {
      return const Center(child: Text('Nessun dato disponibile'));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];

        final badges = CassandraBadgeEngine.badgesForGroupMatchday(
          member: e.member,
          rank: i + 1,
          totalPlayers: entries.length,
          matches: matches,
          picksByMatchId: e.picksByMatchId,
          outcomesByMatchId: outcomesByMatchId,
          day: e.day,
        );

        final pts = formatOdds(e.day.total);

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
                    backgroundColor: _avatarColorFromSeed(e.member.avatarSeed),
                    text: e.member.displayName.substring(0, 1).toUpperCase(),
                    badges: badges,
                  ),
                ],
              ),
            ),
            title: Text(e.member.displayName),
            subtitle: Text(e.member.teamName),
            trailing: Text(
              pts,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: e.day.total >= 0
                    ? CassandraColors.primary
                    : CassandraColors.slate,
              ),
            ),
          ),
        );
      },
    );
  }
}
