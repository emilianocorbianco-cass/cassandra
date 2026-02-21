import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/services/firestore/firestore_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Dummy group IDs: 'g0', 'g1', …, 'g(n-1)'.
List<String> _groups(int n) => List.generate(n, (i) => 'g$i');

/// Builds a [FirestoreService] whose chunk hook appends every invocation to
/// [log] and (optionally) calls [onChunk] so individual tests can simulate
/// failures.
FirestoreService _service({
  required List<(int, List<String>)> log,
  Future<void> Function(int chunkIndex, List<String> groupIds)? onChunk,
}) {
  return FirestoreService.forGroupSyncTest(
    chunkHook: (chunkIndex, groupIds) async {
      log.add((chunkIndex, List.unmodifiable(groupIds)));
      if (onChunk != null) await onChunk(chunkIndex, groupIds);
    },
    retryDelay: Duration.zero,
  );
}

/// Convenience wrapper that calls [updateGroupMemberProfileInGroups] with
/// sensible defaults so individual tests only specify what they care about.
Future<void> _sync(
  FirestoreService svc,
  List<String> groupIds, {
  String uid = 'u1',
}) => svc.updateGroupMemberProfileInGroups(
  uid: uid,
  groupIds: groupIds,
  displayName: 'Test User',
  teamName: 'Milan',
  avatarSeed: 1,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // Empty / blank inputs — no hook calls expected
  // =========================================================================

  group('updateGroupMemberProfileInGroups – empty / blank inputs', () {
    test('empty groupIds list → hook never called', () async {
      final log = <(int, List<String>)>[];
      final svc = _service(log: log);
      await _sync(svc, []);
      expect(log, isEmpty);
    });

    test('blank uid → hook never called', () async {
      final log = <(int, List<String>)>[];
      final svc = _service(log: log);
      await svc.updateGroupMemberProfileInGroups(
        uid: '   ',
        groupIds: ['g1'],
        displayName: 'X',
        teamName: 'Y',
        avatarSeed: 0,
      );
      expect(log, isEmpty);
    });

    test('all-blank groupIds → hook never called', () async {
      final log = <(int, List<String>)>[];
      final svc = _service(log: log);
      await _sync(svc, ['  ', '', '\t']);
      expect(log, isEmpty);
    });
  });

  // =========================================================================
  // Happy path — chunk structure
  // =========================================================================

  group('updateGroupMemberProfileInGroups – chunk structure', () {
    test('single group → one chunk, chunkIndex 0, groupId preserved', () async {
      final log = <(int, List<String>)>[];
      final svc = _service(log: log);
      await _sync(svc, ['g1']);

      expect(log.length, 1);
      expect(log[0].$1, 0); // chunkIndex
      expect(log[0].$2, ['g1']);
    });

    test('duplicates are deduplicated before chunking', () async {
      final log = <(int, List<String>)>[];
      final svc = _service(log: log);
      // 'g1', 'g2', ' g2 ' (with whitespace) — all resolve to 2 unique IDs
      await _sync(svc, ['g1', 'g2', 'g1', 'g2', ' g2 ']);

      expect(log.length, 1);
      expect(log[0].$2.toSet(), {'g1', 'g2'});
      expect(log[0].$2.length, 2);
    });

    test('350 groups → exactly one chunk', () async {
      final log = <(int, List<String>)>[];
      final svc = _service(log: log);
      await _sync(svc, _groups(350));

      expect(log.length, 1);
      expect(log[0].$2.length, 350);
    });

    test('351 groups → two chunks (350 + 1)', () async {
      final log = <(int, List<String>)>[];
      final svc = _service(log: log);
      await _sync(svc, _groups(351));

      expect(log.length, 2);
      expect(log[0].$1, 0);
      expect(log[0].$2.length, 350);
      expect(log[1].$1, 1);
      expect(log[1].$2.length, 1);
    });

    test('400 groups → two chunks (350 + 50)', () async {
      final log = <(int, List<String>)>[];
      final svc = _service(log: log);
      await _sync(svc, _groups(400));

      expect(log.length, 2);
      expect(log[0].$2.length, 350);
      expect(log[1].$2.length, 50);
    });

    test('700 groups → two chunks (350 + 350)', () async {
      final log = <(int, List<String>)>[];
      final svc = _service(log: log);
      await _sync(svc, _groups(700));

      expect(log.length, 2);
      expect(log[0].$2.length, 350);
      expect(log[1].$2.length, 350);
    });

    test('multi-chunk: chunks committed in order, groups contiguous', () async {
      final log = <(int, List<String>)>[];
      final svc = _service(log: log);
      await _sync(svc, _groups(400));

      expect(log.length, 2);
      // First group in chunk 0 must be 'g0'; last group in chunk 1 must be 'g399'.
      expect(log[0].$2.first, 'g0');
      expect(log[1].$2.last, 'g399');
      // Combined coverage = all 400 unique IDs.
      final allIds = {...log[0].$2, ...log[1].$2};
      expect(allIds.length, 400);
    });
  });

  // =========================================================================
  // Retry — transient failures
  // =========================================================================

  group('updateGroupMemberProfileInGroups – transient failure retry', () {
    test('single transient failure → succeeds on 2nd attempt', () async {
      final log = <(int, List<String>)>[];
      var callCount = 0;
      final svc = _service(
        log: log,
        onChunk: (_, _) async {
          callCount++;
          if (callCount == 1) throw Exception('transient network error');
        },
      );

      await expectLater(_sync(svc, ['g1']), completes);
      // log accumulates every invocation including retries
      expect(callCount, 2); // 1 fail + 1 success
    });

    test('two transient failures → succeeds on 3rd attempt', () async {
      var callCount = 0;
      final log = <(int, List<String>)>[];
      final svc = _service(
        log: log,
        onChunk: (_, _) async {
          callCount++;
          if (callCount <= 2) throw Exception('transient error');
        },
      );

      await expectLater(_sync(svc, ['g1']), completes);
      expect(callCount, 3); // 2 fails + 1 success
    });

    test('transient on chunk 0 → recovers; chunk 1 is unaffected', () async {
      final callCounts = <int, int>{};
      final svc = FirestoreService.forGroupSyncTest(
        chunkHook: (chunkIndex, groupIds) async {
          callCounts[chunkIndex] = (callCounts[chunkIndex] ?? 0) + 1;
          // Fail chunk 0 only on the first attempt
          if (chunkIndex == 0 && callCounts[chunkIndex]! == 1) {
            throw Exception('transient on chunk 0');
          }
        },
        retryDelay: Duration.zero,
      );

      await expectLater(_sync(svc, _groups(351)), completes);
      expect(callCounts[0], 2); // 1 fail + 1 success
      expect(callCounts[1], 1); // not retried
    });
  });

  // =========================================================================
  // Permanent failure — exception propagation and message quality
  // =========================================================================

  group('updateGroupMemberProfileInGroups – permanent failure', () {
    test('permanent failure throws Exception (never silent)', () async {
      final svc = FirestoreService.forGroupSyncTest(
        chunkHook: (_, _) async => throw Exception('always fails'),
        retryDelay: Duration.zero,
      );

      await expectLater(_sync(svc, ['g1']), throwsA(isA<Exception>()));
    });

    test('hook called exactly 3 times (max attempts) before throw', () async {
      var callCount = 0;
      final svc = FirestoreService.forGroupSyncTest(
        chunkHook: (_, _) async {
          callCount++;
          throw Exception('always fails');
        },
        retryDelay: Duration.zero,
      );

      try {
        await _sync(svc, ['g1']);
        fail('Expected an Exception');
      } catch (_) {}

      expect(callCount, 3);
    });

    test('exception message names the operation', () async {
      final svc = FirestoreService.forGroupSyncTest(
        chunkHook: (_, _) async => throw Exception('db down'),
        retryDelay: Duration.zero,
      );

      await expectLater(
        _sync(svc, ['g1']),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('updateGroupMemberProfileInGroups'),
          ),
        ),
      );
    });

    test('exception message contains "permanently failed"', () async {
      final svc = FirestoreService.forGroupSyncTest(
        chunkHook: (_, _) async => throw Exception('db down'),
        retryDelay: Duration.zero,
      );

      await expectLater(
        _sync(svc, ['g1']),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('permanently failed'),
          ),
        ),
      );
    });

    test('exception message includes the failing group ID', () async {
      const groupId = 'group-abc-123';
      final svc = FirestoreService.forGroupSyncTest(
        chunkHook: (_, _) async => throw Exception('db down'),
        retryDelay: Duration.zero,
      );

      await expectLater(
        _sync(svc, [groupId]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains(groupId),
          ),
        ),
      );
    });

    test('partial progress: chunk 0 succeeds, chunk 1 permanently fails — '
        'exception propagated and chunk 0 was committed', () async {
      final committedChunks = <int>[];
      final svc = FirestoreService.forGroupSyncTest(
        chunkHook: (chunkIndex, groupIds) async {
          if (chunkIndex == 1) throw Exception('chunk 1 always fails');
          committedChunks.add(chunkIndex);
        },
        retryDelay: Duration.zero,
      );

      await expectLater(_sync(svc, _groups(351)), throwsA(isA<Exception>()));

      // Chunk 0 was committed before chunk 1 failed.
      expect(committedChunks, contains(0));
      expect(committedChunks, isNot(contains(1)));
    });

    test('chunk index and total are correct in exception message', () async {
      // 2 chunks total (351 groups). Fail only chunk 1 (index 1).
      final svc = FirestoreService.forGroupSyncTest(
        chunkHook: (chunkIndex, groupIds) async {
          if (chunkIndex == 1) throw Exception('chunk 1 down');
        },
        retryDelay: Duration.zero,
      );

      await expectLater(
        _sync(svc, _groups(351)),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            // "chunk 2/2" — 1-based index 2 of total 2
            allOf(contains('2/2'), contains('permanently failed')),
          ),
        ),
      );
    });
  });
}
