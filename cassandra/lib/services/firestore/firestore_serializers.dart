import '../../features/predictions/models/prediction_match.dart';
import '../../domain/serie_a/team_name_normalizer.dart';

/// Serializzatori condivisi per convertire modelli di dominio <-> Firestore maps.
/// Estratti da AppState per riuso in FirestoreService.
class FirestoreSerializers {
  FirestoreSerializers._();

  static DateTime _parseKickoffLocal(String raw) =>
      DateTime.parse(raw).toLocal();

  static int? _asNullableInt(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  static Map<String, dynamic> predictionMatchToMap(PredictionMatch m) {
    return {
      'id': m.id,
      'kickoff': m.kickoff.toIso8601String(),
      'home': normalizeSerieATeamName(m.homeTeam),
      'away': normalizeSerieATeamName(m.awayTeam),
      if (m.homeTeamLogo != null) 'homeLogo': m.homeTeamLogo,
      if (m.awayTeamLogo != null) 'awayLogo': m.awayTeamLogo,
      if (m.homeGoals != null) 'homeGoals': m.homeGoals,
      if (m.awayGoals != null) 'awayGoals': m.awayGoals,
      if (m.statusShort != null && m.statusShort!.isNotEmpty)
        'statusShort': m.statusShort,
      if (m.liveEvents.isNotEmpty)
        'events': m.liveEvents
            .map(
              (e) => {
                'minute': e.minute,
                if (e.extraMinute != null) 'extraMinute': e.extraMinute,
                'type': e.type,
                if (e.detail != null && e.detail!.isNotEmpty)
                  'detail': e.detail,
                if (e.teamName != null && e.teamName!.isNotEmpty)
                  'teamName': e.teamName,
                if (e.playerName != null && e.playerName!.isNotEmpty)
                  'playerName': e.playerName,
                if (e.assistName != null && e.assistName!.isNotEmpty)
                  'assistName': e.assistName,
              },
            )
            .toList(),
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
    final rawStatus = j['statusShort']?.toString().trim();
    final rawEvents = (j['events'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
    return PredictionMatch(
      id: j['id'] as String,
      kickoff: _parseKickoffLocal(j['kickoff'] as String),
      homeTeam: normalizeSerieATeamName(j['home'] as String),
      awayTeam: normalizeSerieATeamName(j['away'] as String),
      homeTeamLogo: j['homeLogo'] as String?,
      awayTeamLogo: j['awayLogo'] as String?,
      homeGoals: _asNullableInt(j['homeGoals']),
      awayGoals: _asNullableInt(j['awayGoals']),
      statusShort: (rawStatus == null || rawStatus.isEmpty) ? null : rawStatus,
      liveEvents: rawEvents
          .map((e) {
            return MatchLiveEvent(
              minute: _asNullableInt(e['minute']) ?? 0,
              extraMinute: _asNullableInt(e['extraMinute']),
              type: e['type']?.toString() ?? 'unknown',
              detail: e['detail']?.toString(),
              teamName: e['teamName']?.toString(),
              playerName: e['playerName']?.toString(),
              assistName: e['assistName']?.toString(),
            );
          })
          .toList(growable: false),
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
