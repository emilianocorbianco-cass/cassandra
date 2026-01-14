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
}
