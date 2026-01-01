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

class PredictionMatch {
  final String id;
  final String homeTeam;
  final String awayTeam;
  final DateTime kickoff;
  final Odds odds;

  const PredictionMatch({
    required this.id,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoff,
    required this.odds,
  });
}
