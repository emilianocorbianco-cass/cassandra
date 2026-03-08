class Odds {
  final double home; // 1
  final double draw; // X
  final double away; // 2

  final double homeDraw; // 1X
  final double drawAway; // X2
  final double homeAway; // 12

  const Odds({
    required this.home,
    required this.draw,
    required this.away,
    required this.homeDraw,
    required this.drawAway,
    required this.homeAway,
  });
}

class MatchLiveEvent {
  final int minute;
  final int? extraMinute;
  final String type;
  final String? detail;
  final String? teamName;
  final String? playerName;
  final String? assistName;

  const MatchLiveEvent({
    required this.minute,
    required this.type,
    this.extraMinute,
    this.detail,
    this.teamName,
    this.playerName,
    this.assistName,
  });
}

class PredictionMatch {
  final String id;
  final String homeTeam;
  final String awayTeam;
  final DateTime kickoff;
  final Odds odds;
  final String? homeTeamLogo;
  final String? awayTeamLogo;
  final int? homeGoals;
  final int? awayGoals;
  final String? statusShort;
  final int? elapsed;
  final List<MatchLiveEvent> liveEvents;

  const PredictionMatch({
    required this.id,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoff,
    required this.odds,
    this.homeTeamLogo,
    this.awayTeamLogo,
    this.homeGoals,
    this.awayGoals,
    this.statusShort,
    this.elapsed,
    this.liveEvents = const [],
  });
}
