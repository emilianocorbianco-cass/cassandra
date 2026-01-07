import 'api_football_client.dart';
import 'models/api_football_fixture.dart';

class ApiFootballService {
  ApiFootballService(this._client);

  final ApiFootballClient _client;
  int? _cachedSerieALeagueId;

  int _seasonStartYear(DateTime nowLocal) {
    // stagione tipicamente parte d'estate: anno di inizio
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
      throw Exception('Serie A non trovata (season=$season)');
    }

    final first = response.first;
    if (first is! Map) {
      throw Exception('Formato risposta leagues inatteso');
    }

    final league = (first['league'] as Map?)?.cast<String, dynamic>() ?? {};
    final idRaw = league['id'];
    final id = idRaw is int ? idRaw : (idRaw is num ? idRaw.toInt() : null);

    if (id == null) throw Exception('league.id mancante');

    _cachedSerieALeagueId = id;
    return id;
  }

  Future<List<ApiFootballFixture>> getNextSerieAFixtures({
    int count = 10,
  }) async {
    final season = _seasonStartYear(DateTime.now());
    final leagueId = await _resolveSerieALeagueId(season: season);

    final json = await _client.getJson(
      'fixtures',
      query: {
        'league': '$leagueId',
        'season': '$season',
        'next': '$count',
        'timezone': 'Europe/Rome',
      },
    );

    final response = json['response'];
    if (response is! List) return [];

    return response
        .whereType<Map>()
        .map((e) => ApiFootballFixture.fromJson(e.cast<String, dynamic>()))
        .toList();
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

    final response = json['response'];
    if (response is! List) return [];

    return response
        .whereType<Map>()
        .map((e) => ApiFootballFixture.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
}
