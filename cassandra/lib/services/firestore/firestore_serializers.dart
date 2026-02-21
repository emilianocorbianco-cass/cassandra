import '../../features/predictions/models/prediction_match.dart';
import '../../domain/serie_a/team_name_normalizer.dart';

/// Serializzatori condivisi per convertire modelli di dominio <-> Firestore maps.
/// Estratti da AppState per riuso in FirestoreService.
class FirestoreSerializers {
  FirestoreSerializers._();

  // ---------------------------------------------------------------------------
  // Private parsing helpers
  // ---------------------------------------------------------------------------

  static int? _asNullableInt(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  /// Returns [raw] as a [String], or throws [FormatException] if it is null or
  /// not a String — converting what would otherwise be a silent TypeError into
  /// a catchable, descriptive error.
  static String _requireString(Object? raw, String field) {
    if (raw is String) return raw;
    if (raw == null) {
      throw FormatException(
        'PredictionMatch: required field "$field" is missing',
      );
    }
    throw FormatException(
      'PredictionMatch: field "$field" is not a String '
      '(got ${raw.runtimeType})',
    );
  }

  /// Parses the kickoff field, converting both missing-value and
  /// bad-date-format into [FormatException] instead of TypeError /
  /// uncaught FormatException.
  static DateTime _requireKickoff(Object? raw) {
    final s = _requireString(raw, 'kickoff');
    try {
      return DateTime.parse(s).toLocal();
    } on FormatException {
      throw FormatException(
        'PredictionMatch: field "kickoff" is not a valid ISO 8601 date: "$s"',
      );
    }
  }

  /// Returns [raw] as `Map<String, dynamic>`, or throws [FormatException].
  /// Accepts Firestore-style `LinkedHashMap` subtypes transparently.
  static Map<String, dynamic> _requireOddsMap(Object? raw) {
    if (raw == null) {
      throw const FormatException(
        'PredictionMatch: required field "odds" is missing',
      );
    }
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      try {
        return Map<String, dynamic>.from(raw);
      } catch (_) {}
    }
    throw FormatException(
      'PredictionMatch: field "odds" is not a Map (got ${raw.runtimeType})',
    );
  }

  /// Converts [raw] to a [double] for an odds field, or throws
  /// [FormatException] — never TypeError.
  static double _requireOddDouble(Object? raw, String field) {
    if (raw is num) return raw.toDouble();
    if (raw == null) {
      throw FormatException(
        'PredictionMatch: required odds field "$field" is missing',
      );
    }
    throw FormatException(
      'PredictionMatch: odds field "$field" is not numeric '
      '(got ${raw.runtimeType})',
    );
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

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

  /// Deserializes a [PredictionMatch] from a Firestore map.
  ///
  /// Throws [FormatException] (never [TypeError]) when required structural
  /// fields (id, kickoff, home, away, odds) are missing or have the wrong type.
  static PredictionMatch predictionMatchFromMap(Map<String, dynamic> j) {
    final id = _requireString(j['id'], 'id');
    final kickoff = _requireKickoff(j['kickoff']);
    final home = _requireString(j['home'], 'home');
    final away = _requireString(j['away'], 'away');
    final oddsMap = _requireOddsMap(j['odds']);

    final rawStatus = j['statusShort']?.toString().trim();
    final rawEvents = (j['events'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);

    return PredictionMatch(
      id: id,
      kickoff: kickoff,
      homeTeam: normalizeSerieATeamName(home),
      awayTeam: normalizeSerieATeamName(away),
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
        home: _requireOddDouble(oddsMap['home'], 'home'),
        draw: _requireOddDouble(oddsMap['draw'], 'draw'),
        away: _requireOddDouble(oddsMap['away'], 'away'),
        homeDraw: _requireOddDouble(oddsMap['homeDraw'], 'homeDraw'),
        drawAway: _requireOddDouble(oddsMap['drawAway'], 'drawAway'),
        homeAway: _requireOddDouble(oddsMap['homeAway'], 'homeAway'),
      ),
    );
  }
}
