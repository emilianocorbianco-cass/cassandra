import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/features/badges/badge_engine.dart';
import 'package:cassandra/features/badges/models/badge_type.dart';
import 'package:cassandra/features/group/models/group_member.dart';
import 'package:cassandra/features/predictions/models/pick_option.dart';
import 'package:cassandra/features/predictions/models/prediction_match.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';
import 'package:cassandra/features/scoring/models/score_breakdown.dart';

void main() {
  const odds = Odds(
    home: 2.0,
    draw: 3.0,
    away: 4.0,
    homeDraw: 1.3,
    drawAway: 1.7,
    homeAway: 1.4,
  );

  final match = PredictionMatch(
    id: 'm1',
    homeTeam: 'Inter',
    awayTeam: 'Milan',
    kickoff: DateTime(2026, 1, 1, 18, 0),
    odds: odds,
  );

  const dayPerfect = DayScoreBreakdown(
    matchBreakdowns: [],
    baseTotal: 0,
    bonusPoints: 20,
    total: 20,
    correctCount: 10,
    averageOddsPlayed: 2.0,
  );

  const dayNormal = DayScoreBreakdown(
    matchBreakdowns: [],
    baseTotal: 0,
    bonusPoints: 0,
    total: 0,
    correctCount: 3,
    averageOddsPlayed: 2.0,
  );

  test('adds crown for rank 1', () {
    const member = GroupMember(
      id: 'u',
      displayName: 'A',
      teamName: 'T',
      avatarSeed: 1,
      favoriteTeam: 'Inter',
    );

    final badges = CassandraBadgeEngine.badgesForGroupMatchday(
      member: member,
      rank: 1,
      totalPlayers: 6,
      matches: [match],
      picksByMatchId: {'m1': PickOption.home},
      outcomesByMatchId: {'m1': MatchOutcome.home},
      day: dayNormal,
    );

    expect(badges, contains(BadgeType.crown));
  });

  test('adds loser for last place (when >1 player)', () {
    const member = GroupMember(
      id: 'u',
      displayName: 'A',
      teamName: 'T',
      avatarSeed: 1,
    );

    final badges = CassandraBadgeEngine.badgesForGroupMatchday(
      member: member,
      rank: 6,
      totalPlayers: 6,
      matches: [match],
      picksByMatchId: const {},
      outcomesByMatchId: {'m1': MatchOutcome.home},
      day: dayNormal,
    );

    expect(badges, contains(BadgeType.loser));
  });

  test('adds eyes for 10/10 correct', () {
    const member = GroupMember(
      id: 'u',
      displayName: 'A',
      teamName: 'T',
      avatarSeed: 1,
    );

    final badges = CassandraBadgeEngine.badgesForGroupMatchday(
      member: member,
      rank: 3,
      totalPlayers: 6,
      matches: [match],
      picksByMatchId: const {},
      outcomesByMatchId: {'m1': MatchOutcome.home},
      day: dayPerfect,
    );

    expect(badges, contains(BadgeType.eyes));
  });

  test('adds owl when favorite predicted to win but loses', () {
    const member = GroupMember(
      id: 'u',
      displayName: 'A',
      teamName: 'T',
      avatarSeed: 1,
      favoriteTeam: 'Inter',
    );

    // Inter è home; lo dai vincente (PickOption.home) ma perde (outcome away)
    final badges = CassandraBadgeEngine.badgesForGroupMatchday(
      member: member,
      rank: 3,
      totalPlayers: 6,
      matches: [match],
      picksByMatchId: {'m1': PickOption.home},
      outcomesByMatchId: {'m1': MatchOutcome.away},
      day: dayNormal,
    );

    expect(badges, contains(BadgeType.owl));
  });
}
