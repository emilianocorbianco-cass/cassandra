class ApiFootballStanding {
  ApiFootballStanding({
    required this.rank,
    required this.teamName,
    this.teamLogo,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.goalDiff,
    required this.points,
    this.form,
  });

  final int rank;
  final String teamName;
  final String? teamLogo;
  final int played;
  final int wins;
  final int draws;
  final int losses;
  final int goalsFor;
  final int goalsAgainst;
  final int goalDiff;
  final int points;
  final String? form;

  factory ApiFootballStanding.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

    final team = (json['team'] as Map?)?.cast<String, dynamic>() ?? {};
    final all = (json['all'] as Map?)?.cast<String, dynamic>() ?? {};
    final goals = (all['goals'] as Map?)?.cast<String, dynamic>() ?? {};

    return ApiFootballStanding(
      rank: asInt(json['rank']),
      teamName: team['name']?.toString() ?? '?',
      teamLogo: team['logo']?.toString(),
      played: asInt(all['played']),
      wins: asInt(all['win']),
      draws: asInt(all['draw']),
      losses: asInt(all['lose']),
      goalsFor: asInt(goals['for']),
      goalsAgainst: asInt(goals['against']),
      goalDiff: asInt(json['goalsDiff']),
      points: asInt(json['points']),
      form: json['form']?.toString(),
    );
  }

  factory ApiFootballStanding.fromMap(Map<String, dynamic> map) {
    int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

    return ApiFootballStanding(
      rank: asInt(map['rank']),
      teamName: map['teamName']?.toString() ?? '?',
      teamLogo: map['teamLogo']?.toString(),
      played: asInt(map['played']),
      wins: asInt(map['wins']),
      draws: asInt(map['draws']),
      losses: asInt(map['losses']),
      goalsFor: asInt(map['goalsFor']),
      goalsAgainst: asInt(map['goalsAgainst']),
      goalDiff: asInt(map['goalDiff']),
      points: asInt(map['points']),
      form: map['form']?.toString(),
    );
  }
}
