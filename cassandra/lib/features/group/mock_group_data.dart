import 'dart:math';

import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/scoring_engine.dart';

import 'models/group_leaderboard_entry.dart';
import 'models/group_member.dart';

List<GroupMember> mockGroupMembers({GroupMember? overrideMember}) {
  final members = <GroupMember>[
    const GroupMember(
      id: 'u1',
      displayName: 'Alessandro',
      teamName: 'FC Oracolo',
      avatarSeed: 11,
      favoriteTeam: 'Inter',
    ),
    const GroupMember(
      id: 'u2',
      displayName: 'Andrea',
      teamName: 'FC Gufatori',
      avatarSeed: 22,
      favoriteTeam: 'Roma',
    ),
    const GroupMember(
      id: 'u3',
      displayName: 'Eric',
      teamName: 'FC Camado',
      avatarSeed: 33,
      favoriteTeam: 'Juventus',
    ),
    const GroupMember(
      id: 'u4',
      displayName: 'Vincenzo',
      teamName: 'FC Re della Quota',
      avatarSeed: 44,
      favoriteTeam: 'Atalanta',
    ),
    const GroupMember(
      id: 'u5',
      displayName: 'Davide',
      teamName: 'FC Parziale',
      avatarSeed: 55,
      favoriteTeam: 'Bologna',
    ),
    const GroupMember(
      id: 'u6',
      displayName: 'Emiliano',
      teamName: 'FC Cassandra',
      avatarSeed: 66,
      favoriteTeam: 'Milan',
    ),
  ];

  if (overrideMember != null) {
    final idx = members.indexWhere((m) => m.id == overrideMember.id);
    if (idx != -1) {
      members[idx] = overrideMember;
    }
  }

  return members;
}

/// Risultati mock (deterministici: stessi a ogni run).
Map<String, MatchOutcome> mockOutcomesForMatches(
  List<PredictionMatch> matches,
) {
  final rnd = Random(777);
  const outcomes = [MatchOutcome.home, MatchOutcome.draw, MatchOutcome.away];

  final map = <String, MatchOutcome>{};
  for (final m in matches) {
    map[m.id] = outcomes[rnd.nextInt(outcomes.length)];
  }
  return map;
}

/// Picks mock per un utente (deterministici per seed+giornata).
Map<String, PickOption> mockPicksForMember(
  String memberSeed,
  List<PredictionMatch> matches,
) {
  final rnd = Random(memberSeed.hashCode);

  PickOption randomPick() {
    final x = rnd.nextDouble();

    // ~10% non giocata
    if (x < 0.10) return PickOption.none;

    // ~65% singole
    if (x < 0.75) {
      const singles = [PickOption.home, PickOption.draw, PickOption.away];
      return singles[rnd.nextInt(singles.length)];
    }

    // ~25% doppie
    const doubles = [
      PickOption.homeDraw,
      PickOption.drawAway,
      PickOption.homeAway,
    ];
    return doubles[rnd.nextInt(doubles.length)];
  }

  final picks = <String, PickOption>{};
  for (final m in matches) {
    picks[m.id] = randomPick();
  }
  return picks;
}

/// Classifica gruppo (giornata) + ordinamento:
/// 1) totale punti desc
/// 2) quota media giocata desc
List<GroupLeaderboardEntry> buildSortedMockGroupLeaderboard({
  required List<PredictionMatch> matches,
  required Map<String, MatchOutcome> outcomesByMatchId,
  List<GroupMember>? members,
}) {
  final membersList = members ?? mockGroupMembers();

  final entries = membersList.map((member) {
    final picks = mockPicksForMember(member.id, matches);

    final day = CassandraScoringEngine.computeDayScore(
      matches: matches,
      picksByMatchId: picks,
      outcomesByMatchId: outcomesByMatchId,
    );

    return GroupLeaderboardEntry(
      member: member,
      picksByMatchId: picks,
      day: day,
    );
  }).toList();

  entries.sort((a, b) {
    final t = b.day.total.compareTo(a.day.total);
    if (t != 0) return t;

    final aAvg = a.day.averageOddsPlayed ?? -1;
    final bAvg = b.day.averageOddsPlayed ?? -1;
    final avgCmp = bAvg.compareTo(aAvg);
    if (avgCmp != 0) return avgCmp;

    return a.member.teamName.compareTo(b.member.teamName);
  });

  return entries;
}
