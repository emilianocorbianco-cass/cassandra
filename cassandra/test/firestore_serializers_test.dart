import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/services/firestore/firestore_serializers.dart';
import 'package:cassandra/features/predictions/models/prediction_match.dart';

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

const _validOdds = Odds(
  home: 2.0,
  draw: 3.25,
  away: 3.5,
  homeDraw: 1.4,
  drawAway: 1.6,
  homeAway: 1.5,
);

/// Minimal valid map accepted by predictionMatchFromMap.
Map<String, dynamic> _validMap({
  String id = 'm1',
  String kickoff = '2026-03-01T18:00:00.000',
  String home = 'Inter',
  String away = 'Juventus',
  Map<String, dynamic>? odds,
}) => {
  'id': id,
  'kickoff': kickoff,
  'home': home,
  'away': away,
  'odds':
      odds ??
      {
        'home': _validOdds.home,
        'draw': _validOdds.draw,
        'away': _validOdds.away,
        'homeDraw': _validOdds.homeDraw,
        'drawAway': _validOdds.drawAway,
        'homeAway': _validOdds.homeAway,
      },
};

void main() {
  // =========================================================================
  // FirestoreSerializers.predictionMatchFromMap — happy path (backward compat)
  // =========================================================================

  group('predictionMatchFromMap – valid payloads', () {
    test('minimal valid map deserializes correctly', () {
      final m = FirestoreSerializers.predictionMatchFromMap(_validMap());
      expect(m.id, 'm1');
      expect(m.odds.home, 2.0);
      expect(m.odds.draw, 3.25);
      expect(m.odds.away, 3.5);
      expect(m.odds.homeDraw, 1.4);
      expect(m.odds.drawAway, 1.6);
      expect(m.odds.homeAway, 1.5);
      expect(m.homeTeamLogo, isNull);
      expect(m.awayTeamLogo, isNull);
      expect(m.homeGoals, isNull);
      expect(m.awayGoals, isNull);
      expect(m.statusShort, isNull);
      expect(m.liveEvents, isEmpty);
    });

    test('round-trips through toMap → fromMap', () {
      final original = PredictionMatch(
        id: 'rt-42',
        homeTeam: 'Milan',
        awayTeam: 'Napoli',
        kickoff: DateTime(2026, 4, 5, 20, 45),
        odds: _validOdds,
        homeTeamLogo: 'https://example.com/milan.png',
        awayTeamLogo: 'https://example.com/napoli.png',
        homeGoals: 1,
        awayGoals: 0,
        statusShort: 'FT',
      );
      final map = FirestoreSerializers.predictionMatchToMap(original);
      final rt = FirestoreSerializers.predictionMatchFromMap(map);

      expect(rt.id, original.id);
      expect(rt.odds.home, original.odds.home);
      expect(rt.odds.draw, original.odds.draw);
      expect(rt.homeGoals, 1);
      expect(rt.awayGoals, 0);
      expect(rt.statusShort, 'FT');
      expect(rt.homeTeamLogo, original.homeTeamLogo);
    });

    test('integer odds are accepted and converted to double', () {
      final m = FirestoreSerializers.predictionMatchFromMap(
        _validMap(
          odds: {
            'home': 2,
            'draw': 3,
            'away': 4,
            'homeDraw': 1,
            'drawAway': 1,
            'homeAway': 1,
          },
        ),
      );
      expect(m.odds.home, 2.0);
      expect(m.odds.home, isA<double>());
    });

    test('absent optional fields do not crash', () {
      // Only the four required + odds; all optional fields omitted.
      final m = FirestoreSerializers.predictionMatchFromMap(_validMap());
      expect(m.statusShort, isNull);
      expect(m.homeGoals, isNull);
      expect(m.liveEvents, isEmpty);
    });

    test('live events round-trip', () {
      final original = PredictionMatch(
        id: 'ev-1',
        homeTeam: 'Roma',
        awayTeam: 'Lazio',
        kickoff: DateTime(2026, 3, 15, 18, 0),
        odds: _validOdds,
        liveEvents: const [
          MatchLiveEvent(
            minute: 45,
            extraMinute: 2,
            type: 'Goal',
            teamName: 'Roma',
            playerName: 'Totti',
          ),
        ],
      );
      final map = FirestoreSerializers.predictionMatchToMap(original);
      final rt = FirestoreSerializers.predictionMatchFromMap(map);

      expect(rt.liveEvents.length, 1);
      expect(rt.liveEvents.first.minute, 45);
      expect(rt.liveEvents.first.extraMinute, 2);
      expect(rt.liveEvents.first.type, 'Goal');
    });
  });

  // =========================================================================
  // predictionMatchFromMap — malformed payloads → FormatException, not TypeError
  // =========================================================================

  group('predictionMatchFromMap – required field "id"', () {
    test('null id throws FormatException', () {
      final map = _validMap()..['id'] = null;
      expect(
        () => FirestoreSerializers.predictionMatchFromMap(map),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('"id"'),
          ),
        ),
      );
    });

    test('non-String id throws FormatException', () {
      final map = _validMap()..['id'] = 42;
      expect(
        () => FirestoreSerializers.predictionMatchFromMap(map),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('predictionMatchFromMap – required field "kickoff"', () {
    test('null kickoff throws FormatException', () {
      final map = _validMap()..['kickoff'] = null;
      expect(
        () => FirestoreSerializers.predictionMatchFromMap(map),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('"kickoff"'),
          ),
        ),
      );
    });

    test('non-String kickoff throws FormatException', () {
      final map = _validMap()..['kickoff'] = 1234567890;
      expect(
        () => FirestoreSerializers.predictionMatchFromMap(map),
        throwsA(isA<FormatException>()),
      );
    });

    test('malformed date string throws FormatException', () {
      final map = _validMap(kickoff: 'not-a-date');
      expect(
        () => FirestoreSerializers.predictionMatchFromMap(map),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('ISO 8601'),
          ),
        ),
      );
    });
  });

  group('predictionMatchFromMap – required field "home"', () {
    test('null home throws FormatException', () {
      final map = _validMap()..['home'] = null;
      expect(
        () => FirestoreSerializers.predictionMatchFromMap(map),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('"home"'),
          ),
        ),
      );
    });

    test('numeric home throws FormatException, not TypeError', () {
      final map = _validMap()..['home'] = 99;
      expect(
        () => FirestoreSerializers.predictionMatchFromMap(map),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('predictionMatchFromMap – required field "away"', () {
    test('null away throws FormatException', () {
      final map = _validMap()..['away'] = null;
      expect(
        () => FirestoreSerializers.predictionMatchFromMap(map),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('"away"'),
          ),
        ),
      );
    });
  });

  group('predictionMatchFromMap – required field "odds"', () {
    test('null odds block throws FormatException', () {
      final map = _validMap()..['odds'] = null;
      expect(
        () => FirestoreSerializers.predictionMatchFromMap(map),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('"odds"'),
          ),
        ),
      );
    });

    test('odds as String throws FormatException', () {
      final map = _validMap()..['odds'] = 'not-a-map';
      expect(
        () => FirestoreSerializers.predictionMatchFromMap(map),
        throwsA(isA<FormatException>()),
      );
    });

    test('null odds.home throws FormatException', () {
      final map = _validMap(
        odds: {
          'home': null,
          'draw': 3.0,
          'away': 4.0,
          'homeDraw': 1.3,
          'drawAway': 1.7,
          'homeAway': 1.4,
        },
      );
      expect(
        () => FirestoreSerializers.predictionMatchFromMap(map),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('home'),
          ),
        ),
      );
    });

    test('string odds.draw throws FormatException, not TypeError', () {
      final map = _validMap(
        odds: {
          'home': 2.0,
          'draw': 'three-point-two-five',
          'away': 4.0,
          'homeDraw': 1.3,
          'drawAway': 1.7,
          'homeAway': 1.4,
        },
      );
      expect(
        () => FirestoreSerializers.predictionMatchFromMap(map),
        throwsA(isA<FormatException>()),
      );
    });

    test('missing odds.homeDraw key throws FormatException', () {
      final map = _validMap(
        odds: {
          'home': 2.0,
          'draw': 3.0,
          'away': 4.0,
          // homeDraw absent
          'drawAway': 1.7,
          'homeAway': 1.4,
        },
      );
      expect(
        () => FirestoreSerializers.predictionMatchFromMap(map),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('homeDraw'),
          ),
        ),
      );
    });
  });

  // =========================================================================
  // FormatException message quality checks
  // =========================================================================

  group('predictionMatchFromMap – exception message quality', () {
    test('missing id message names the field', () {
      final map = _validMap()..remove('id');
      try {
        FirestoreSerializers.predictionMatchFromMap(map);
        fail('Expected FormatException');
      } on FormatException catch (e) {
        expect(e.message, contains('id'));
        expect(e.message, contains('PredictionMatch'));
      }
    });

    test('bad kickoff message mentions ISO 8601', () {
      final map = _validMap(kickoff: '32/13/2026');
      try {
        FirestoreSerializers.predictionMatchFromMap(map);
        fail('Expected FormatException');
      } on FormatException catch (e) {
        expect(e.message, contains('ISO 8601'));
      }
    });

    test('null odds.away message names the sub-field', () {
      final map = _validMap(
        odds: {
          'home': 2.0,
          'draw': 3.0,
          'away': null,
          'homeDraw': 1.3,
          'drawAway': 1.7,
          'homeAway': 1.4,
        },
      );
      try {
        FirestoreSerializers.predictionMatchFromMap(map);
        fail('Expected FormatException');
      } on FormatException catch (e) {
        expect(e.message, contains('away'));
      }
    });
  });
}
