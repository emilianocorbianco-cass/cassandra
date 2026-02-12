/// Quote pre-match reali da API-Football (`GET /odds`).
///
/// Parsifica bookmaker JSON e ne estrae Match Winner (bet id=1)
/// e Double Chance (bet id=12).
class ApiFootballFixtureOdds {
  ApiFootballFixtureOdds({
    required this.fixtureId,
    this.home,
    this.draw,
    this.away,
    this.homeDraw,
    this.homeAway,
    this.drawAway,
  });

  final int fixtureId;

  /// Match Winner (bet id 1)
  final double? home;
  final double? draw;
  final double? away;

  /// Double Chance (bet id 12)
  final double? homeDraw;
  final double? homeAway;
  final double? drawAway;

  /// true se abbiamo almeno le 3 quote singole
  bool get hasMatchWinner => home != null && draw != null && away != null;

  bool get hasDoubleChance =>
      homeDraw != null && homeAway != null && drawAway != null;

  /// Costruisce da un singolo bookmaker JSON (elemento di `bookmakers[]`).
  ///
  /// ```json
  /// {
  ///   "id": 8,
  ///   "name": "Bet365",
  ///   "bets": [
  ///     { "id": 1, "name": "Match Winner", "values": [...] },
  ///     { "id": 12, "name": "Double Chance", "values": [...] }
  ///   ]
  /// }
  /// ```
  factory ApiFootballFixtureOdds.fromBookmakerJson(
    int fixtureId,
    Map<dynamic, dynamic> json,
  ) {
    final bets = json['bets'];
    if (bets is! List) {
      return ApiFootballFixtureOdds(fixtureId: fixtureId);
    }

    double? home, draw, away;
    double? homeDraw, homeAway, drawAway;

    for (final bet in bets) {
      if (bet is! Map) continue;
      final betId = bet['id'];
      final values = bet['values'];
      if (values is! List) continue;

      if (betId == 1) {
        // Match Winner: "Home", "Draw", "Away"
        for (final v in values) {
          if (v is! Map) continue;
          final label = v['value']?.toString();
          final odd = double.tryParse(v['odd']?.toString() ?? '');
          if (label == null || odd == null) continue;
          switch (label) {
            case 'Home':
              home = odd;
            case 'Draw':
              draw = odd;
            case 'Away':
              away = odd;
          }
        }
      } else if (betId == 12) {
        // Double Chance: "Home/Draw", "Home/Away", "Draw/Away"
        for (final v in values) {
          if (v is! Map) continue;
          final label = v['value']?.toString();
          final odd = double.tryParse(v['odd']?.toString() ?? '');
          if (label == null || odd == null) continue;
          switch (label) {
            case 'Home/Draw':
              homeDraw = odd;
            case 'Home/Away':
              homeAway = odd;
            case 'Draw/Away':
              drawAway = odd;
          }
        }
      }
    }

    return ApiFootballFixtureOdds(
      fixtureId: fixtureId,
      home: home,
      draw: draw,
      away: away,
      homeDraw: homeDraw,
      homeAway: homeAway,
      drawAway: drawAway,
    );
  }
}
