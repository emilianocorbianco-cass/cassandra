import 'package:flutter/foundation.dart';

import 'api_football_client.dart';
import 'models/api_football_fixture.dart';
import 'models/api_football_odds.dart';
import 'models/api_football_standing.dart';

class ApiFootballService {
  ApiFootballService(this._client);

  final ApiFootballClient _client;

  /// Bookmaker preferiti (ordine di priorità).
  static const _preferredBookmakerIds = [
    8,
    6,
    11,
    1,
  ]; // Bet365, Bwin, 1xBet, 10Bet

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

  /// Classifica Serie A corrente.
  Future<List<ApiFootballStanding>> getSerieAStandings() async {
    final season = _seasonStartYear(DateTime.now());
    final leagueId = await _resolveSerieALeagueId(season: season);

    final json = await _client.getJson(
      'standings',
      query: {'league': '$leagueId', 'season': '$season'},
    );

    final response = json['response'];
    if (response is! List || response.isEmpty) return const [];

    final first = response.first;
    if (first is! Map) return const [];

    final league = first['league'];
    if (league is! Map) return const [];

    final standings = league['standings'];
    if (standings is! List || standings.isEmpty) return const [];

    // Il primo array = Serie A regular season
    final group = standings.first;
    if (group is! List) return const [];

    return group
        .whereType<Map>()
        .map((e) => ApiFootballStanding.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Fixtures Serie A per round (matchday) specifico.
  /// Utile per evitare che i recuperi di round vecchi "sporchino" la giornata corrente.
  Future<List<ApiFootballFixture>> getSerieAFixturesByRound({
    required int round,
  }) async {
    final season = _seasonStartYear(DateTime.now());
    final leagueId = await _resolveSerieALeagueId(season: season);

    final json = await _client.getJson(
      'fixtures',
      query: {
        'league': '$leagueId',
        'season': '$season',
        'round': 'Regular Season - $round',
        'timezone': 'Europe/Rome',
      },
    );

    return _fixturesFromJson(json);
  }

  /// Recupera le quote pre-match reali per una lista di fixture ID.
  ///
  /// Ritorna mappa fixtureId → [ApiFootballFixtureOdds].
  /// Best-effort: se una fixture fallisce, continua con le altre.
  Future<Map<int, ApiFootballFixtureOdds>> getOddsForFixtures(
    List<int> fixtureIds,
  ) async {
    final result = <int, ApiFootballFixtureOdds>{};
    for (final id in fixtureIds) {
      try {
        final json = await _client.getJson('odds', query: {'fixture': '$id'});
        final response = json['response'];
        if (response is! List || response.isEmpty) continue;
        final entry = response.first;
        if (entry is! Map) continue;
        final bookmakers = entry['bookmakers'];
        if (bookmakers is! List || bookmakers.isEmpty) continue;

        // Cerca bookmaker preferito, fallback al primo disponibile
        Map<dynamic, dynamic>? chosen;
        for (final prefId in _preferredBookmakerIds) {
          chosen = bookmakers
              .whereType<Map>()
              .where((b) => b['id'] == prefId)
              .firstOrNull;
          if (chosen != null) break;
        }
        final firstBookmaker = bookmakers.first;
        if (chosen == null && firstBookmaker is Map) {
          chosen = firstBookmaker;
        }
        if (chosen == null) continue;

        result[id] = ApiFootballFixtureOdds.fromBookmakerJson(id, chosen);
      } catch (e) {
        debugPrint('[odds] Failed for fixture $id: $e');
      }
    }
    if (kDebugMode && result.isNotEmpty) {
      debugPrint('[odds] loaded for ${result.length} fixtures');
    }
    return result;
  }
}
