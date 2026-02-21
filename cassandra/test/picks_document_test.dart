import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/services/firestore/models/picks_document.dart';

PicksDocument _doc({
  required String docId,
  String uid = 'u1',
  String seasonKey = '2024',
  int dayNumber = 1,
  String? groupId,
  required DateTime submittedAt,
}) => PicksDocument(
  docId: docId,
  uid: uid,
  seasonKey: seasonKey,
  dayNumber: dayNumber,
  groupId: groupId,
  picksByMatchId: const {},
  submittedAt: submittedAt,
  visibility: 'friends',
);

void main() {
  group('PicksScoreCache', () {
    test('fromMap round-trips through toMap', () {
      final src = {
        'baseTotal': 3.5,
        'bonusPoints': 2,
        'total': 5.5,
        'correctCount': 4,
        'averageOddsPlayed': 1.8,
      };
      final cache = PicksScoreCache.fromMap(src);
      expect(cache.baseTotal, 3.5);
      expect(cache.bonusPoints, 2);
      expect(cache.total, 5.5);
      expect(cache.correctCount, 4);
      expect(cache.averageOddsPlayed, 1.8);

      final map = cache.toMap();
      expect(map['baseTotal'], 3.5);
      expect(map['bonusPoints'], 2);
      expect(map['total'], 5.5);
      expect(map['correctCount'], 4);
      expect(map['averageOddsPlayed'], 1.8);
    });

    test('fromMap uses defaults for missing keys', () {
      final cache = PicksScoreCache.fromMap({});
      expect(cache.baseTotal, 0.0);
      expect(cache.bonusPoints, 0);
      expect(cache.total, 0.0);
      expect(cache.correctCount, 0);
      expect(cache.averageOddsPlayed, isNull);
    });

    test('fromMap accepts int values for double fields', () {
      final cache = PicksScoreCache.fromMap({
        'baseTotal': 2,
        'bonusPoints': 1,
        'total': 3,
        'correctCount': 5,
      });
      expect(cache.baseTotal, 2.0);
      expect(cache.total, 3.0);
    });

    test('toMap omits averageOddsPlayed when null', () {
      final cache = PicksScoreCache(
        baseTotal: 1,
        bonusPoints: 0,
        total: 1,
        correctCount: 1,
      );
      expect(cache.toMap().containsKey('averageOddsPlayed'), isFalse);
    });

    test('toMap includes averageOddsPlayed when zero', () {
      const cache = PicksScoreCache(
        baseTotal: 0,
        bonusPoints: 0,
        total: 0,
        correctCount: 0,
        averageOddsPlayed: 0.0,
      );
      expect(cache.toMap().containsKey('averageOddsPlayed'), isTrue);
      expect(cache.toMap()['averageOddsPlayed'], 0.0);
    });

    test('fromMap preserves negative scores', () {
      final cache = PicksScoreCache.fromMap({
        'baseTotal': -5.5,
        'bonusPoints': -2,
        'total': -7.5,
        'correctCount': 0,
      });
      expect(cache.baseTotal, -5.5);
      expect(cache.bonusPoints, -2);
      expect(cache.total, -7.5);
    });
  });

  group('deduplicatePicks', () {
    test('empty input returns empty list', () {
      expect(deduplicatePicks([]), isEmpty);
    });

    test('single doc is returned unchanged', () {
      final doc = _doc(docId: 'a', submittedAt: DateTime(2024));
      expect(deduplicatePicks([doc]), [doc]);
    });

    test('keeps doc with later submittedAt', () {
      final older = _doc(docId: 'a', submittedAt: DateTime(2024, 1, 1));
      final newer = _doc(docId: 'b', submittedAt: DateTime(2024, 1, 2));
      final result = deduplicatePicks([older, newer]);
      expect(result.length, 1);
      expect(result.first.docId, 'b');
    });

    test('earlier doc wins when it has later submittedAt', () {
      final earlySubmit = _doc(docId: 'a', submittedAt: DateTime(2024, 1, 2));
      final lateSubmit = _doc(docId: 'b', submittedAt: DateTime(2024, 1, 1));
      final result = deduplicatePicks([earlySubmit, lateSubmit]);
      expect(result.length, 1);
      expect(result.first.docId, 'a');
    });

    test('tiebreaks by docId when submittedAt is equal', () {
      final t = DateTime(2024);
      final docA = _doc(docId: 'a', submittedAt: t);
      final docB = _doc(docId: 'b', submittedAt: t);
      final result = deduplicatePicks([docA, docB]);
      expect(result.length, 1);
      expect(result.first.docId, 'b'); // 'b' > 'a'
    });

    test('different dayNumbers produce distinct keys', () {
      final doc1 = _doc(docId: 'a', dayNumber: 1, submittedAt: DateTime(2024));
      final doc2 = _doc(docId: 'b', dayNumber: 2, submittedAt: DateTime(2024));
      expect(deduplicatePicks([doc1, doc2]).length, 2);
    });

    test('different uids produce distinct keys', () {
      final doc1 = _doc(docId: 'a', uid: 'u1', submittedAt: DateTime(2024));
      final doc2 = _doc(docId: 'b', uid: 'u2', submittedAt: DateTime(2024));
      expect(deduplicatePicks([doc1, doc2]).length, 2);
    });

    test('different seasonKeys produce distinct keys', () {
      final doc1 = _doc(
        docId: 'a',
        seasonKey: '2023',
        submittedAt: DateTime(2024),
      );
      final doc2 = _doc(
        docId: 'b',
        seasonKey: '2024',
        submittedAt: DateTime(2024),
      );
      expect(deduplicatePicks([doc1, doc2]).length, 2);
    });

    test(
      'null groupId and whitespace-only groupId are treated as same key',
      () {
        final withNull = _doc(
          docId: 'a',
          groupId: null,
          submittedAt: DateTime(2024, 1, 1),
        );
        final withWhitespace = _doc(
          docId: 'b',
          groupId: '  ',
          submittedAt: DateTime(2024, 1, 2),
        );
        // Both resolve to '' after trim; newer wins.
        final result = deduplicatePicks([withNull, withWhitespace]);
        expect(result.length, 1);
        expect(result.first.docId, 'b');
      },
    );

    test('different groupIds are distinct keys', () {
      final noGroup = _doc(
        docId: 'a',
        groupId: null,
        submittedAt: DateTime(2024),
      );
      final withGroup = _doc(
        docId: 'b',
        groupId: 'g1',
        submittedAt: DateTime(2024),
      );
      expect(deduplicatePicks([noGroup, withGroup]).length, 2);
    });

    test('three docs for same key — latest wins', () {
      final t = DateTime(2024, 1, 1);
      final docs = [
        _doc(docId: 'x', submittedAt: t),
        _doc(docId: 'y', submittedAt: t.add(const Duration(hours: 1))),
        _doc(docId: 'z', submittedAt: t.add(const Duration(hours: 2))),
      ];
      final result = deduplicatePicks(docs);
      expect(result.length, 1);
      expect(result.first.docId, 'z');
    });

    test('large batch with same key keeps doc with latest submittedAt', () {
      final base = DateTime(2024, 1, 1);
      final docs = [
        for (var i = 0; i < 20; i++)
          _doc(
            docId: 'doc$i',
            submittedAt: base.add(Duration(minutes: i)),
          ),
      ];
      final result = deduplicatePicks(docs);
      expect(result.length, 1);
      expect(result.first.docId, 'doc19');
    });

    test('reverse insertion order yields the same winner', () {
      final t = DateTime(2024, 1, 1);
      // Insert in reverse chronological order — 'c' still wins (latest time)
      final docs = [
        _doc(docId: 'c', submittedAt: t.add(const Duration(hours: 2))),
        _doc(docId: 'b', submittedAt: t.add(const Duration(hours: 1))),
        _doc(docId: 'a', submittedAt: t),
      ];
      final result = deduplicatePicks(docs);
      expect(result.length, 1);
      expect(result.first.docId, 'c');
    });

    test('multiple groups are independently deduped', () {
      final t = DateTime(2024);
      final docs = [
        _doc(docId: 'g1-old', groupId: 'g1', submittedAt: t),
        _doc(
          docId: 'g1-new',
          groupId: 'g1',
          submittedAt: t.add(const Duration(hours: 1)),
        ),
        _doc(docId: 'g2-only', groupId: 'g2', submittedAt: t),
        _doc(docId: 'no-group', groupId: null, submittedAt: t),
      ];
      final result = deduplicatePicks(docs);
      expect(result.length, 3);
      final byGroup = {for (final d in result) d.groupId ?? '': d};
      expect(byGroup['g1']!.docId, 'g1-new');
      expect(byGroup['g2']!.docId, 'g2-only');
      expect(byGroup['']!.docId, 'no-group');
    });

    test('same-timestamp tiebreak picks lexicographically highest docId', () {
      final t = DateTime(2024);
      final docs = [
        _doc(docId: 'aaa', submittedAt: t),
        _doc(docId: 'zzz', submittedAt: t),
        _doc(docId: 'mmm', submittedAt: t),
      ];
      final result = deduplicatePicks(docs);
      expect(result.length, 1);
      expect(result.first.docId, 'zzz');
    });
  });
}
