class ApiFootballFixture {
  ApiFootballFixture({
    required this.fixtureId,
    required this.kickoffUtc,
    required this.homeName,
    required this.awayName,
    required this.statusShort,
    this.homeGoals,
    this.awayGoals,
    this.round,
  });

  final int fixtureId;
  final DateTime kickoffUtc;

  final String homeName;
  final String awayName;

  final String statusShort;
  final int? homeGoals;
  final int? awayGoals;

  final String? round;

  factory ApiFootballFixture.fromJson(Map<String, dynamic> json) {
    final fixture = (json['fixture'] as Map?)?.cast<String, dynamic>() ?? {};
    final teams = (json['teams'] as Map?)?.cast<String, dynamic>() ?? {};
    final goals = (json['goals'] as Map?)?.cast<String, dynamic>() ?? {};
    final league = (json['league'] as Map?)?.cast<String, dynamic>() ?? {};

    int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
    int? asNullableInt(dynamic v) =>
        v is int ? v : (v is num ? v.toInt() : null);

    final fixtureId = asInt(fixture['id']);
    final kickoff =
        DateTime.tryParse(fixture['date']?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    final home = (teams['home'] as Map?)?.cast<String, dynamic>() ?? {};
    final away = (teams['away'] as Map?)?.cast<String, dynamic>() ?? {};

    final status = (fixture['status'] as Map?)?.cast<String, dynamic>() ?? {};

    return ApiFootballFixture(
      fixtureId: fixtureId,
      kickoffUtc: kickoff,
      homeName: home['name']?.toString() ?? 'Home',
      awayName: away['name']?.toString() ?? 'Away',
      statusShort: status['short']?.toString() ?? '',
      homeGoals: asNullableInt(goals['home']),
      awayGoals: asNullableInt(goals['away']),
      round: league['round']?.toString(),
    );
  }
}
