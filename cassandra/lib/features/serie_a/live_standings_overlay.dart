import '../../services/api_football/models/api_football_standing.dart';
import '../predictions/models/prediction_match.dart';

/// Overlays live/recently-finished match results on top of the official
/// API-Football standings so the table updates in real-time during matches.
///
/// For each match that is in progress or finished (but not yet reflected
/// in the standings), the team stats are adjusted: played, W/D/L, GF/GA,
/// goal diff, and points. The table is then re-sorted.
List<ApiFootballStanding> computeLiveStandings(
  List<ApiFootballStanding> baseStandings,
  List<PredictionMatch> currentMatches,
) {
  if (baseStandings.isEmpty) return baseStandings;

  // Collect matches that have started and have score data.
  final activeMatches = currentMatches.where((m) {
    final status = (m.statusShort ?? '').trim().toUpperCase();
    if (_notStarted.contains(status) || status.isEmpty) return false;
    return m.homeGoals != null && m.awayGoals != null;
  }).toList();

  if (activeMatches.isEmpty) return baseStandings;

  // Build a mutable copy keyed by normalized team name.
  final byTeam = <String, _MutableStanding>{};
  for (final s in baseStandings) {
    byTeam[s.teamName.toLowerCase()] = _MutableStanding.from(s);
  }

  for (final m in activeMatches) {
    final homeKey = m.homeTeam.toLowerCase();
    final awayKey = m.awayTeam.toLowerCase();
    final home = byTeam[homeKey];
    final away = byTeam[awayKey];
    if (home == null || away == null) continue;

    final hg = m.homeGoals!;
    final ag = m.awayGoals!;

    // Heuristic: if the team's played count already equals or exceeds the
    // max played in standings + 1, skip — the standings likely already
    // include this match.
    final maxPlayed = baseStandings
        .fold<int>(0, (prev, s) => s.played > prev ? s.played : prev);
    if (home.played > maxPlayed || away.played > maxPlayed) continue;

    // Check if this match seems already counted by comparing played counts
    // of both teams to the max. If both are already at max, the standings
    // might already include current round results, so skip.
    if (home.played >= maxPlayed && away.played >= maxPlayed) continue;

    // Apply delta for home team.
    home.played++;
    home.goalsFor += hg;
    home.goalsAgainst += ag;
    if (hg > ag) {
      home.wins++;
      home.points += 3;
    } else if (hg == ag) {
      home.draws++;
      home.points += 1;
    } else {
      home.losses++;
    }

    // Apply delta for away team.
    away.played++;
    away.goalsFor += ag;
    away.goalsAgainst += hg;
    if (ag > hg) {
      away.wins++;
      away.points += 3;
    } else if (ag == hg) {
      away.draws++;
      away.points += 1;
    } else {
      away.losses++;
    }
  }

  // Re-sort: points desc, then goal diff desc, then goals for desc.
  final sorted = byTeam.values.toList()
    ..sort((a, b) {
      final pts = b.points.compareTo(a.points);
      if (pts != 0) return pts;
      final gd = (b.goalsFor - b.goalsAgainst)
          .compareTo(a.goalsFor - a.goalsAgainst);
      if (gd != 0) return gd;
      return b.goalsFor.compareTo(a.goalsFor);
    });

  // Convert back to ApiFootballStanding with updated ranks.
  return [
    for (var i = 0; i < sorted.length; i++)
      sorted[i].toStanding(rank: i + 1),
  ];
}

const _notStarted = {'NS', 'TBD', 'PST', 'CANC'};

class _MutableStanding {
  String teamName;
  String? teamLogo;
  int played;
  int wins;
  int draws;
  int losses;
  int goalsFor;
  int goalsAgainst;
  int points;
  String? form;

  _MutableStanding._({
    required this.teamName,
    this.teamLogo,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.points,
    this.form,
  });

  factory _MutableStanding.from(ApiFootballStanding s) => _MutableStanding._(
    teamName: s.teamName,
    teamLogo: s.teamLogo,
    played: s.played,
    wins: s.wins,
    draws: s.draws,
    losses: s.losses,
    goalsFor: s.goalsFor,
    goalsAgainst: s.goalsAgainst,
    points: s.points,
    form: s.form,
  );

  ApiFootballStanding toStanding({required int rank}) => ApiFootballStanding(
    rank: rank,
    teamName: teamName,
    teamLogo: teamLogo,
    played: played,
    wins: wins,
    draws: draws,
    losses: losses,
    goalsFor: goalsFor,
    goalsAgainst: goalsAgainst,
    goalDiff: goalsFor - goalsAgainst,
    points: points,
    form: form,
  );
}
