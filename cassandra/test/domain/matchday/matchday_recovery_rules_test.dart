import 'package:flutter_test/flutter_test.dart';
import 'package:cassandra/domain/matchday/matchday_recovery_rules.dart';

class _Fx {
  final int id;
  final DateTime kickoff;
  final DateTime origin;
  final String st;

  const _Fx({
    required this.id,
    required this.kickoff,
    required this.origin,
    required this.st,
  });
}

void main() {
  group('matchday_recovery_rules', () {
    test('planned recuperi: primaryDone true prima di finalDone', () {
      // Esempio stile G16:
      // cluster 1: 6 partite 20-21 dic
      // cluster 2: 4 partite 14-15 gen (posticipi programmati)
      final dec20_1800 = DateTime(2025, 12, 20, 18, 0);
      final dec21_2045 = DateTime(2025, 12, 21, 20, 45);
      final jan14_1830 = DateTime(2026, 1, 14, 18, 30);
      final jan15_2045 = DateTime(2026, 1, 15, 20, 45);

      final fixtures = <_Fx>[
        // Cluster 1 - finito
        _Fx(id: 1, kickoff: dec20_1800, origin: dec20_1800, st: 'FT'),
        _Fx(
          id: 2,
          kickoff: dec20_1800.add(const Duration(hours: 2)),
          origin: dec20_1800.add(const Duration(hours: 2)),
          st: 'FT',
        ),
        _Fx(
          id: 3,
          kickoff: dec20_1800.add(const Duration(hours: 20)),
          origin: dec20_1800.add(const Duration(hours: 20)),
          st: 'FT',
        ),
        _Fx(
          id: 4,
          kickoff: dec20_1800.add(const Duration(hours: 21)),
          origin: dec20_1800.add(const Duration(hours: 21)),
          st: 'FT',
        ),
        _Fx(
          id: 5,
          kickoff: dec20_1800.add(const Duration(hours: 24)),
          origin: dec20_1800.add(const Duration(hours: 24)),
          st: 'FT',
        ),
        _Fx(id: 6, kickoff: dec21_2045, origin: dec21_2045, st: 'FT'),

        // Cluster 2 - non ancora giocato
        _Fx(id: 7, kickoff: jan14_1830, origin: jan14_1830, st: 'NS'),
        _Fx(
          id: 8,
          kickoff: jan14_1830.add(const Duration(hours: 2)),
          origin: jan14_1830.add(const Duration(hours: 2)),
          st: 'NS',
        ),
        _Fx(
          id: 9,
          kickoff: jan14_1830.add(const Duration(days: 1)),
          origin: jan14_1830.add(const Duration(days: 1)),
          st: 'NS',
        ),
        _Fx(id: 10, kickoff: jan15_2045, origin: jan15_2045, st: 'NS'),
      ];

      final nowAfterCluster1 = DateTime(2025, 12, 21, 23, 30);

      final p = computeMatchdayProgress<_Fx>(
        fixtures,
        now: nowAfterCluster1,
        kickoff: (f) => f.kickoff,
        originKickoff: (f) => f.origin,
        statusShort: (f) => f.st,
      );

      expect(p.primaryDone, isTrue);
      expect(p.finalDone, isFalse);

      // Lock: 30 min prima del primo kickoff (20 dic 18:00 => 17:30)
      expect(p.lockAt, DateTime(2025, 12, 20, 17, 30));
      expect(p.isLocked, isTrue);

      // Played count: solo le 6 FT.
      expect(p.playedFixtures, 6);
      expect(p.isValidMatchday, isTrue);
    });

    test('final giocata oltre 48h dal kickoff originario => nulla', () {
      final origin = DateTime(2026, 1, 1, 18, 0);
      final playedLate = DateTime(2026, 1, 10, 20, 45);
      final fx = _Fx(id: 1, kickoff: playedLate, origin: origin, st: 'FT');

      final p = computeMatchdayProgress<_Fx>(
        [fx],
        now: DateTime(2026, 1, 10, 23, 0),
        kickoff: (f) => f.kickoff,
        originKickoff: (f) => f.origin,
        statusShort: (f) => f.st,
      );

      expect(p.finalDone, isTrue);
      expect(p.playedFixtures, 0);
      expect(p.voidFixtures, 1);
      expect(p.isValidMatchday, isFalse);
    });

    test('sudden postpone: void dopo 48h dal kickoff originario', () {
      final origin = DateTime(2026, 1, 1, 18, 0);
      final fx = _Fx(id: 1, kickoff: origin, origin: origin, st: 'PST');

      final now = DateTime(2026, 1, 3, 19, 0); // > 49h

      final p = computeMatchdayProgress<_Fx>(
        [fx],
        now: now,
        kickoff: (f) => f.kickoff,
        originKickoff: (f) => f.origin,
        statusShort: (f) => f.st,
      );

      expect(p.finalDone, isTrue);
      expect(p.playedFixtures, 0);
      expect(p.voidFixtures, 1);
      expect(p.isValidMatchday, isFalse);
    });

    test('bonus scaling: correct -> 0..10 rispetto a played', () {
      expect(scaleCorrectToTen(correct: 6, playedFixtures: 6), 10);
      expect(scaleCorrectToTen(correct: 3, playedFixtures: 6), 5);
      expect(scaleCorrectToTen(correct: 0, playedFixtures: 6), 0);
      expect(scaleCorrectToTen(correct: 1, playedFixtures: 9), 1);
    });
  });

  // ===== clusterByKickoff (additional) =====

  group('clusterByKickoff', () {
    test('empty list returns empty clusters', () {
      final result = clusterByKickoff<_Fx>([], kickoff: (f) => f.kickoff);
      expect(result, isEmpty);
    });

    test('single fixture returns one cluster', () {
      final fixtures = [
        _Fx(
          id: 1,
          kickoff: DateTime(2026, 3, 1, 18),
          origin: DateTime(2026, 3, 1, 18),
          st: 'NS',
        ),
      ];
      final result = clusterByKickoff(fixtures, kickoff: (f) => f.kickoff);
      expect(result, hasLength(1));
      expect(result[0], hasLength(1));
    });

    test('matches close together form one cluster', () {
      final base = DateTime(2026, 3, 1, 15);
      final fixtures = [
        _Fx(id: 1, kickoff: base, origin: base, st: 'FT'),
        _Fx(
          id: 2,
          kickoff: base.add(const Duration(hours: 3)),
          origin: base.add(const Duration(hours: 3)),
          st: 'FT',
        ),
        _Fx(
          id: 3,
          kickoff: base.add(const Duration(hours: 5, minutes: 45)),
          origin: base.add(const Duration(hours: 5, minutes: 45)),
          st: 'FT',
        ),
      ];
      final result = clusterByKickoff(fixtures, kickoff: (f) => f.kickoff);
      expect(result, hasLength(1));
      expect(result[0], hasLength(3));
    });

    test('custom gap threshold splits closer matches', () {
      final base = DateTime(2026, 3, 1, 15);
      final fixtures = [
        _Fx(id: 1, kickoff: base, origin: base, st: 'FT'),
        _Fx(
          id: 2,
          kickoff: base.add(const Duration(hours: 5)),
          origin: base.add(const Duration(hours: 5)),
          st: 'FT',
        ),
      ];
      // 5h gap, threshold at 4h -> two clusters
      final result = clusterByKickoff(
        fixtures,
        kickoff: (f) => f.kickoff,
        gapThreshold: const Duration(hours: 4),
      );
      expect(result, hasLength(2));
    });
  });

  // ===== resolveFixture (additional) =====

  group('resolveFixture (additional)', () {
    test('AET status within 48h -> finalResult', () {
      final origin = DateTime(2026, 3, 1, 18);
      final fx = _Fx(id: 1, kickoff: origin, origin: origin, st: 'AET');
      final result = resolveFixture(
        fx,
        now: origin.add(const Duration(hours: 3)),
        kickoff: (f) => f.kickoff,
        statusShort: (f) => f.st,
        originKickoff: (f) => f.origin,
      );
      expect(result, FixtureResolution.finalResult);
    });

    test('PEN status within 48h -> finalResult', () {
      final origin = DateTime(2026, 3, 1, 18);
      final fx = _Fx(id: 1, kickoff: origin, origin: origin, st: 'PEN');
      final result = resolveFixture(
        fx,
        now: origin.add(const Duration(hours: 3)),
        kickoff: (f) => f.kickoff,
        statusShort: (f) => f.st,
        originKickoff: (f) => f.origin,
      );
      expect(result, FixtureResolution.finalResult);
    });

    test('CANC at any time -> voidNull', () {
      final origin = DateTime(2026, 3, 1, 18);
      final fx = _Fx(id: 1, kickoff: origin, origin: origin, st: 'CANC');
      // Even before kickoff
      final result = resolveFixture(
        fx,
        now: origin.subtract(const Duration(hours: 5)),
        kickoff: (f) => f.kickoff,
        statusShort: (f) => f.st,
        originKickoff: (f) => f.origin,
      );
      expect(result, FixtureResolution.voidNull);
    });

    test('FT delayed start within 48h -> finalResult', () {
      final origin = DateTime(2026, 3, 1, 18);
      final delayed = origin.add(const Duration(hours: 26));
      final fx = _Fx(id: 1, kickoff: delayed, origin: origin, st: 'FT');
      final result = resolveFixture(
        fx,
        now: delayed.add(const Duration(hours: 3)),
        kickoff: (f) => f.kickoff,
        statusShort: (f) => f.st,
        originKickoff: (f) => f.origin,
      );
      expect(result, FixtureResolution.finalResult);
    });

    test('boundary: exactly at 48h deadline with NS -> pending', () {
      final origin = DateTime(2026, 3, 1, 18);
      final fx = _Fx(id: 1, kickoff: origin, origin: origin, st: 'NS');
      // Exactly at deadline (not after)
      final result = resolveFixture(
        fx,
        now: origin.add(const Duration(hours: 48)),
        kickoff: (f) => f.kickoff,
        statusShort: (f) => f.st,
        originKickoff: (f) => f.origin,
      );
      // now.isAfter(deadline) with deadline = origin + 48h, now == deadline → false
      expect(result, FixtureResolution.pending);
    });

    test('one second past 48h deadline with NS -> voidNull', () {
      final origin = DateTime(2026, 3, 1, 18);
      final fx = _Fx(id: 1, kickoff: origin, origin: origin, st: 'NS');
      final result = resolveFixture(
        fx,
        now: origin.add(const Duration(hours: 48, seconds: 1)),
        kickoff: (f) => f.kickoff,
        statusShort: (f) => f.st,
        originKickoff: (f) => f.origin,
      );
      expect(result, FixtureResolution.voidNull);
    });
  });

  // ===== computeMatchdayProgress (additional) =====

  group('computeMatchdayProgress (additional)', () {
    test('all CANC -> finalDone, 0 played, all void', () {
      final base = DateTime(2026, 3, 1, 15);
      final fixtures = List.generate(
        10,
        (i) => _Fx(id: i, kickoff: base, origin: base, st: 'CANC'),
      );
      final progress = computeMatchdayProgress(
        fixtures,
        now: base.add(const Duration(hours: 5)),
        kickoff: (f) => f.kickoff,
        originKickoff: (f) => f.origin,
        statusShort: (f) => f.st,
      );
      expect(progress.finalDone, isTrue);
      expect(progress.playedFixtures, 0);
      expect(progress.voidFixtures, 10);
      expect(progress.isValidMatchday, isFalse);
    });

    test('mix of FT and pending -> not finalDone', () {
      final base = DateTime(2026, 3, 1, 15);
      final fixtures = [
        _Fx(id: 1, kickoff: base, origin: base, st: 'FT'),
        _Fx(
          id: 2,
          kickoff: base.add(const Duration(hours: 3)),
          origin: base.add(const Duration(hours: 3)),
          st: 'NS',
        ),
      ];
      final progress = computeMatchdayProgress(
        fixtures,
        now: base.add(const Duration(hours: 5)),
        kickoff: (f) => f.kickoff,
        originKickoff: (f) => f.origin,
        statusShort: (f) => f.st,
      );
      expect(progress.primaryDone, isFalse);
      expect(progress.finalDone, isFalse);
      expect(progress.playedFixtures, 1);
    });
  });

  // ===== scaleCorrectToTen (additional) =====

  group('scaleCorrectToTen (additional)', () {
    test('0 played -> 0 regardless of correct', () {
      expect(scaleCorrectToTen(correct: 5, playedFixtures: 0), 0);
    });

    test('negative played -> 0', () {
      expect(scaleCorrectToTen(correct: 5, playedFixtures: -1), 0);
    });

    test('all correct in 10 matches -> 10', () {
      expect(scaleCorrectToTen(correct: 10, playedFixtures: 10), 10);
    });

    test('clamps to max 10 even if correct > played', () {
      expect(scaleCorrectToTen(correct: 15, playedFixtures: 10), 10);
    });
  });

  // ===== status helpers =====

  group('status helpers', () {
    test('FT, AET, PEN are final', () {
      expect(defaultIsFinalStatus('FT'), isTrue);
      expect(defaultIsFinalStatus('AET'), isTrue);
      expect(defaultIsFinalStatus('PEN'), isTrue);
    });

    test('NS, 1H, 2H, HT are not final', () {
      expect(defaultIsFinalStatus('NS'), isFalse);
      expect(defaultIsFinalStatus('1H'), isFalse);
      expect(defaultIsFinalStatus('2H'), isFalse);
      expect(defaultIsFinalStatus('HT'), isFalse);
      expect(defaultIsFinalStatus('PST'), isFalse);
    });

    test('CANC is immediately void', () {
      expect(defaultIsImmediatelyVoidStatus('CANC'), isTrue);
    });

    test('other statuses are not immediately void', () {
      expect(defaultIsImmediatelyVoidStatus('FT'), isFalse);
      expect(defaultIsImmediatelyVoidStatus('NS'), isFalse);
      expect(defaultIsImmediatelyVoidStatus('PST'), isFalse);
    });
  });
}
