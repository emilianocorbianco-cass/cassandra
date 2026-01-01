import 'dart:math';

import '../group/mock_group_data.dart'
    show mockGroupMembers, mockPicksForMember;
import '../predictions/models/mock_prediction_data.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/scoring_engine.dart';

import 'models/matchday_data.dart';
import 'models/member_matchday_score.dart';
import 'models/season_leaderboard_entry.dart';

Map<String, MatchOutcome> _mockOutcomesForMatchesSeeded(
  List<PredictionMatch> matches, {
  required int seed,
}) {
  final rnd = Random(seed);
  const outcomes = [MatchOutcome.home, MatchOutcome.draw, MatchOutcome.away];

  final map = <String, MatchOutcome>{};
  for (final m in matches) {
    map[m.id] = outcomes[rnd.nextInt(outcomes.length)];
  }
  return map;
}

/// Crea una “stagione demo” di N giornate.
/// Ogni giornata riusa le stesse 10 partite mock ma con:
/// - id unici (dXX_mY)
/// - kickoff spostati di una settimana tra una giornata e la successiva
List<MatchdayData> mockSeasonMatchdays({
  required int startDay,
  required int count,
}) {
  final template = mockPredictionMatches();
  final firstKickoff = template.first.kickoff;

  final base0 = DateTime(
    firstKickoff.year,
    firstKickoff.month,
    firstKickoff.day,
    firstKickoff.hour,
    firstKickoff.minute,
  );

  final matchdays = <MatchdayData>[];

  for (int i = 0; i < count; i++) {
    final dayNumber = startDay + i;

    // ogni giornata è +7 giorni rispetto alla precedente
    final base = base0.add(Duration(days: i * 7));

    final matches = <PredictionMatch>[];
    for (int j = 0; j < template.length; j++) {
      final m = template[j];
      final delta = m.kickoff.difference(firstKickoff);

      matches.add(
        PredictionMatch(
          id: 'd${dayNumber}_m${j + 1}',
          homeTeam: m.homeTeam,
          awayTeam: m.awayTeam,
          kickoff: base.add(delta),
          odds: m.odds,
        ),
      );
    }

    final outcomes = _mockOutcomesForMatchesSeeded(
      matches,
      seed: 7000 + dayNumber,
    );

    matchdays.add(
      MatchdayData(
        dayNumber: dayNumber,
        matches: matches,
        outcomesByMatchId: outcomes,
      ),
    );
  }

  return matchdays;
}

/// Costruisce classifica generale (punti / media) su più giornate.
/// Simuliamo anche “ingresso tardivo”:
/// - alcuni membri iniziano a giocare dopo 0/1/2 giornate (joinOffset).
List<SeasonLeaderboardEntry> buildMockSeasonLeaderboardEntries({
  required List<MatchdayData> matchdays,
}) {
  final members = mockGroupMembers();
  final entries = <SeasonLeaderboardEntry>[];

  for (final member in members) {
    final joinOffset = member.avatarSeed % 3; // 0..2
    final playedMatchdays = matchdays.skip(joinOffset).toList();

    final perDay = <MemberMatchdayScore>[];

    for (final md in playedMatchdays) {
      // Picks diversi per giornata (seed diversa)
      final picks = mockPicksForMember(
        '${member.id}_${md.dayNumber}',
        md.matches,
      );

      final day = CassandraScoringEngine.computeDayScore(
        matches: md.matches,
        picksByMatchId: picks,
        outcomesByMatchId: md.outcomesByMatchId,
      );

      perDay.add(
        MemberMatchdayScore(matchday: md, picksByMatchId: picks, day: day),
      );
    }

    final total = perDay.fold<double>(0, (sum, d) => sum + d.day.total);
    final avg = perDay.isEmpty ? 0.0 : total / perDay.length;

    final oddsValues = perDay
        .expand((d) => d.day.matchBreakdowns)
        .map((b) => b.playedOdds)
        .whereType<double>()
        .toList();

    final avgOdds = oddsValues.isEmpty
        ? null
        : oddsValues.reduce((a, b) => a + b) / oddsValues.length;

    entries.add(
      SeasonLeaderboardEntry(
        member: member,
        matchdays: perDay,
        totalPoints: total,
        averagePerMatchday: avg,
        averageOddsPlayed: avgOdds,
      ),
    );
  }

  return entries;
}
