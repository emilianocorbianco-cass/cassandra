import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cassandra/services/api_football/api_football_client.dart';
import 'package:cassandra/services/api_football/api_football_service.dart';
import 'package:cassandra/services/api_football/models/api_football_odds.dart';

// Creates a client wired to [handler].
ApiFootballClient _client(
  Future<http.Response> Function(http.Request) handler,
) => ApiFootballClient(apiKey: 'test-key', httpClient: MockClient(handler));

Map<String, dynamic> _oddsBody(List<Map<String, dynamic>> bookmakers) => {
  'response': [
    {'bookmakers': bookmakers},
  ],
  'errors': <String, dynamic>{},
};

Map<String, dynamic> _bookmaker(
  int id, {
  List<Map<String, dynamic>> bets = const [],
}) => {'id': id, 'bets': bets};

Map<String, dynamic> _matchWinnerBet({
  String home = '2.00',
  String draw = '3.50',
  String away = '3.75',
}) => {
  'id': 1,
  'values': [
    {'value': 'Home', 'odd': home},
    {'value': 'Draw', 'odd': draw},
    {'value': 'Away', 'odd': away},
  ],
};

Map<String, dynamic> _doubleChanceBet({
  String homeDraw = '1.30',
  String homeAway = '1.25',
  String drawAway = '1.85',
}) => {
  'id': 12,
  'values': [
    {'value': 'Home/Draw', 'odd': homeDraw},
    {'value': 'Home/Away', 'odd': homeAway},
    {'value': 'Draw/Away', 'odd': drawAway},
  ],
};

void main() {
  group('ApiFootballFixtureOdds.fromBookmakerJson', () {
    test('parses full match winner and double chance', () {
      final json = _bookmaker(8, bets: [_matchWinnerBet(), _doubleChanceBet()]);
      final odds = ApiFootballFixtureOdds.fromBookmakerJson(42, json);

      expect(odds.fixtureId, 42);
      expect(odds.home, 2.00);
      expect(odds.draw, 3.50);
      expect(odds.away, 3.75);
      expect(odds.homeDraw, 1.30);
      expect(odds.homeAway, 1.25);
      expect(odds.drawAway, 1.85);
      expect(odds.hasMatchWinner, isTrue);
      expect(odds.hasDoubleChance, isTrue);
    });

    test('returns empty odds when bets key is missing', () {
      final odds = ApiFootballFixtureOdds.fromBookmakerJson(1, {'id': 8});
      expect(odds.hasMatchWinner, isFalse);
      expect(odds.hasDoubleChance, isFalse);
    });

    test('returns empty odds when bets is not a list', () {
      final odds = ApiFootballFixtureOdds.fromBookmakerJson(1, {
        'id': 8,
        'bets': 'bad',
      });
      expect(odds.hasMatchWinner, isFalse);
    });

    test('only match winner when double chance bet is absent', () {
      final json = _bookmaker(8, bets: [_matchWinnerBet()]);
      final odds = ApiFootballFixtureOdds.fromBookmakerJson(7, json);
      expect(odds.hasMatchWinner, isTrue);
      expect(odds.hasDoubleChance, isFalse);
    });

    test('skips values with unparseable odd string', () {
      final json = _bookmaker(
        8,
        bets: [
          {
            'id': 1,
            'values': [
              {'value': 'Home', 'odd': 'N/A'},
              {'value': 'Draw', 'odd': '3.40'},
              {'value': 'Away', 'odd': '3.60'},
            ],
          },
        ],
      );
      final odds = ApiFootballFixtureOdds.fromBookmakerJson(5, json);
      expect(odds.home, isNull);
      expect(odds.draw, 3.40);
      expect(odds.hasMatchWinner, isFalse); // home is null
    });

    test('ignores unknown bet ids', () {
      final json = _bookmaker(
        8,
        bets: [
          {
            'id': 99,
            'values': [
              {'value': 'Home', 'odd': '1.50'},
            ],
          },
        ],
      );
      final odds = ApiFootballFixtureOdds.fromBookmakerJson(3, json);
      expect(odds.hasMatchWinner, isFalse);
      expect(odds.hasDoubleChance, isFalse);
    });

    test('skips non-map entries in bets list', () {
      final json = {
        'bets': ['not-a-map', 42],
      };
      final odds = ApiFootballFixtureOdds.fromBookmakerJson(2, json);
      expect(odds.hasMatchWinner, isFalse);
    });
  });

  group('ApiFootballService.getOddsForFixtures', () {
    test('returns parsed odds for a fixture', () async {
      final bm = _bookmaker(8, bets: [_matchWinnerBet(home: '2.10')]);
      final client = _client(
        (_) async => http.Response(jsonEncode(_oddsBody([bm])), 200),
      );
      final svc = ApiFootballService(client);
      final result = await svc.getOddsForFixtures([10]);

      expect(result[10], isNotNull);
      expect(result[10]!.home, 2.10);
    });

    test('prefers bookmaker with higher priority in preferred list', () async {
      // Preferred order: [8, 6, 11, 1]. Response has id=1 (10Bet, index 3)
      // and id=6 (Bwin, index 1). Should pick Bwin.
      final bet10Bet = _matchWinnerBet(home: '1.50');
      final betBwin = _matchWinnerBet(home: '2.20');
      final body = jsonEncode(
        _oddsBody([
          _bookmaker(1, bets: [bet10Bet]),
          _bookmaker(6, bets: [betBwin]),
        ]),
      );
      final client = _client((_) async => http.Response(body, 200));
      final svc = ApiFootballService(client);
      final result = await svc.getOddsForFixtures([20]);

      expect(result[20]!.home, 2.20); // Bwin's value
    });

    test('falls back to first bookmaker when none preferred', () async {
      final bm = _bookmaker(999, bets: [_matchWinnerBet(home: '1.80')]);
      final client = _client(
        (_) async => http.Response(jsonEncode(_oddsBody([bm])), 200),
      );
      final svc = ApiFootballService(client);
      final result = await svc.getOddsForFixtures([30]);

      expect(result[30]!.home, 1.80);
    });

    test('skips fixture when response list is empty', () async {
      final client = _client(
        (_) async =>
            http.Response(jsonEncode({'response': [], 'errors': {}}), 200),
      );
      final svc = ApiFootballService(client);
      final result = await svc.getOddsForFixtures([40]);
      expect(result, isEmpty);
    });

    test('continues best-effort when one fixture fails', () async {
      // Fixture 50: 404 (non-retryable, caught by getOddsForFixtures).
      // Fixture 51: succeeds.
      var calls = 0;
      final client = _client((_) async {
        calls++;
        if (calls == 1) return http.Response('not found', 404);
        final bm = _bookmaker(8, bets: [_matchWinnerBet(home: '2.10')]);
        return http.Response(jsonEncode(_oddsBody([bm])), 200);
      });
      final svc = ApiFootballService(client);
      final result = await svc.getOddsForFixtures([50, 51]);

      expect(result.containsKey(50), isFalse);
      expect(result[51]!.home, 2.10);
      expect(calls, 2); // 1 call per fixture, no retries on 404
    });

    test(
      'returns empty map and makes no HTTP calls for empty fixture list',
      () async {
        var calls = 0;
        final client = _client((_) async {
          calls++;
          return http.Response('{}', 200);
        });
        final svc = ApiFootballService(client);
        final result = await svc.getOddsForFixtures([]);

        expect(result, isEmpty);
        expect(calls, 0);
      },
    );

    test('skips fixture when response entry has no bookmakers key', () async {
      // Response has a fixture item but 'bookmakers' key is absent.
      final body = jsonEncode({
        'response': [
          {'id': 99},
        ],
        'errors': <String, dynamic>{},
      });
      final client = _client((_) async => http.Response(body, 200));
      final svc = ApiFootballService(client);
      final result = await svc.getOddsForFixtures([60]);

      expect(result, isEmpty);
    });
  });
}
