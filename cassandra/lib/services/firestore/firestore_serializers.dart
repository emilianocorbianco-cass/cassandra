import '../../features/predictions/models/prediction_match.dart';

/// Serializzatori condivisi per convertire modelli di dominio <-> Firestore maps.
/// Estratti da AppState per riuso in FirestoreService.
class FirestoreSerializers {
  FirestoreSerializers._();

  static Map<String, dynamic> predictionMatchToMap(PredictionMatch m) {
    return {
      'id': m.id,
      'kickoff': m.kickoff.toIso8601String(),
      'home': m.homeTeam,
      'away': m.awayTeam,
      if (m.homeTeamLogo != null) 'homeLogo': m.homeTeamLogo,
      if (m.awayTeamLogo != null) 'awayLogo': m.awayTeamLogo,
      'odds': {
        'home': m.odds.home,
        'draw': m.odds.draw,
        'away': m.odds.away,
        'homeDraw': m.odds.homeDraw,
        'drawAway': m.odds.drawAway,
        'homeAway': m.odds.homeAway,
      },
    };
  }

  static PredictionMatch predictionMatchFromMap(Map<String, dynamic> j) {
    final odds = j['odds'] as Map<String, dynamic>;
    return PredictionMatch(
      id: j['id'] as String,
      kickoff: DateTime.parse(j['kickoff'] as String),
      homeTeam: j['home'] as String,
      awayTeam: j['away'] as String,
      homeTeamLogo: j['homeLogo'] as String?,
      awayTeamLogo: j['awayLogo'] as String?,
      odds: Odds(
        home: (odds['home'] as num).toDouble(),
        draw: (odds['draw'] as num).toDouble(),
        away: (odds['away'] as num).toDouble(),
        homeDraw: (odds['homeDraw'] as num).toDouble(),
        drawAway: (odds['drawAway'] as num).toDouble(),
        homeAway: (odds['homeAway'] as num).toDouble(),
      ),
    );
  }
}
