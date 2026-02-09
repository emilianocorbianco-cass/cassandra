import 'api_football_client.dart';
import 'models/api_football_fixture.dart';

class ApiFootballService {
  ApiFootballService(this._client);

  final ApiFootballClient _client;

  int? _cachedSerieALeagueId;

  int _seasonStartYear(DateTime nowLocal) {
    // Stagione Serie A: parte in estate.
    // Se siamo prima di luglio -> consideriamo stagione iniziata l'anno scorso.
    return nowLocal.month >= 7 ? nowLocal.year : nowLocal.year - 1;
  }

  Future<int> _resolveSerieALeagueId({required int season}) async {
    if (_cachedSerieALeagueId != null) return _cachedSerieALeagueId!;

    final json = await _client.getJson(
      'leagues',
      query: {
        'name': 'Serie A',
        'country': 'Italy',
        'season': '$season',
        'type': 'league',
      },
    );

    final response = json['response'];
    if (response is! List || response.isEmpty) {
      throw Exception(
        'API-FOOTBALL: league Serie A non trovato (season=$season).',
      );
    }

    final first = response.first;
    if (first is! Map) {
      throw Exception(
        'API-FOOTBALL: risposta leagues non valida (season=$season).',
      );
    }

    final league = first['league'];
    if (league is! Map) {
      throw Exception(
        'API-FOOTBALL: campo league mancante in leagues (season=$season).',
      );
    }

    final id = league['id'];
    if (id is! int) {
      throw Exception(
        'API-FOOTBALL: league.id non valido in leagues (season=$season).',
      );
    }

    _cachedSerieALeagueId = id;
    return id;
  }

  List<ApiFootballFixture> _fixturesFromJson(dynamic json) {
    final response = json['response'];
    if (response is! List) return const <ApiFootballFixture>[];

    return response
        .whereType<Map>()
        .map((e) => ApiFootballFixture.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Fixtures per una round specifica (es. "Regular Season - 20").
  Future<List<ApiFootballFixture>> getSerieAFixturesForRound({
    required String round,
  }) async {
    final season = _seasonStartYear(DateTime.now());
    final leagueId = await _resolveSerieALeagueId(season: season);

    final json = await _client.getJson(
      'fixtures',
      query: {
        'league': '$leagueId',
        'season': '$season',
        'round': round,
        'timezone': 'Europe/Rome',
      },
    );

    return _fixturesFromJson(json);
  }

  /// "Next" in Cassandra = la giornata corrente.
  ///
  /// Problema che risolve:
  /// - next=10 durante una giornata già iniziata può “mischiare” partite di round diverse
  ///   (es. posticipo giornata 20 + anticipo giornata 21).
  ///
  /// Strategia:
  /// 1) chiede next=1 solo per scoprire la round della prossima partita
  /// 2) poi chiede TUTTI i fixtures di quella round
  /// 3) fallback: se round non disponibile, torna al comportamento vecchio next=count
  Future<List<ApiFootballFixture>> getNextSerieAFixtures({
    int count = 10,
  }) async {
    final season = _seasonStartYear(DateTime.now());
    final leagueId = await _resolveSerieALeagueId(season: season);

    final preview = await _client.getJson(
      'fixtures',
      query: {
        'league': '$leagueId',
        'season': '$season',
        'next': '1',
        'timezone': 'Europe/Rome',
      },
    );

    String? round;
    final resp = preview['response'];
    if (resp is List && resp.isNotEmpty) {
      final first = resp.first;
      if (first is Map) {
        final league = first['league'];
        if (league is Map) {
          final r = league['round'];
          if (r is String && r.trim().isNotEmpty) {
            round = r.trim();
          }
        }
      }
    }

    if (round != null) {
      return getSerieAFixturesForRound(round: round);
    }

    // Fallback (vecchio comportamento): next=count
    final json = await _client.getJson(
      'fixtures',
      query: {
        'league': '$leagueId',
        'season': '$season',
        'next': '$count',
        'timezone': 'Europe/Rome',
      },
    );

    return _fixturesFromJson(json);
  }

  Future<List<ApiFootballFixture>> getLastSerieAFixtures({
    int count = 10,
  }) async {
    final season = _seasonStartYear(DateTime.now());
    final leagueId = await _resolveSerieALeagueId(season: season);

    final json = await _client.getJson(
      'fixtures',
      query: {
        'league': '$leagueId',
        'season': '$season',
        'last': '$count',
        'timezone': 'Europe/Rome',
      },
    );

    return _fixturesFromJson(json);
  }
}
