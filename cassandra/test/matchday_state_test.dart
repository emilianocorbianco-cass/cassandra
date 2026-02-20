import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/app/state/matchday_state.dart';
import 'package:cassandra/domain/matchday/matchday_recovery_rules.dart';

MatchdayProgress _makeProgress({
  bool primaryDone = false,
  bool finalDone = false,
  int totalFixtures = 10,
  int playedFixtures = 10,
  int voidFixtures = 0,
  bool isLocked = true,
}) =>
    MatchdayProgress(
      lockAt: DateTime(2026, 3, 1, 14, 0),
      isLocked: isLocked,
      primaryDone: primaryDone,
      finalDone: finalDone,
      totalFixtures: totalFixtures,
      playedFixtures: playedFixtures,
      voidFixtures: voidFixtures,
    );

void main() {
  // ==========================================================================
  // Matchday cursor
  // ==========================================================================
  group('MatchdayState – cursor', () {
    test('default cursor is 20', () {
      final s = MatchdayState.inMemory();
      expect(s.cassandraMatchdayCursor, 20);
    });

    test('setCassandraMatchdayCursor updates value and notifies', () async {
      final s = MatchdayState.inMemory();
      var notified = 0;
      s.addListener(() => notified++);

      await s.setCassandraMatchdayCursor(25);
      expect(s.cassandraMatchdayCursor, 25);
      expect(notified, 1);
    });

    test('setCassandraMatchdayCursor ignores zero or negative', () async {
      final s = MatchdayState.inMemory();
      await s.setCassandraMatchdayCursor(10);
      await s.setCassandraMatchdayCursor(0);
      expect(s.cassandraMatchdayCursor, 10);
      await s.setCassandraMatchdayCursor(-5);
      expect(s.cassandraMatchdayCursor, 10);
    });

    test('bumpCassandraMatchdayCursor increments by 1', () async {
      final s = MatchdayState.inMemory();
      await s.setCassandraMatchdayCursor(15);
      await s.bumpCassandraMatchdayCursor();
      expect(s.cassandraMatchdayCursor, 16);
    });

    test('setCassandraMatchdayCursor resets uiMatchdayNumber', () async {
      final s = MatchdayState.inMemory();
      s.setUiMatchdayNumber(30);
      expect(s.uiMatchdayNumber, 30);
      await s.setCassandraMatchdayCursor(10);
      // uiMatchdayNumber falls back to cursor when null
      expect(s.uiMatchdayNumber, 10);
    });
  });

  // ==========================================================================
  // Matchday finalization
  // ==========================================================================
  group('MatchdayState – finalization', () {
    test('initial state: no matchdays finalized', () {
      final s = MatchdayState.inMemory();
      expect(s.isMatchdayFinalized(1), isFalse);
      expect(s.isMatchdayFinalized(20), isFalse);
    });

    test('markMatchdayFinalized returns true on first mark', () async {
      final s = MatchdayState.inMemory();
      var notified = 0;
      s.addListener(() => notified++);

      final result = await s.markMatchdayFinalized(5);
      expect(result, isTrue);
      expect(s.isMatchdayFinalized(5), isTrue);
      expect(notified, 1);
    });

    test('markMatchdayFinalized is idempotent', () async {
      final s = MatchdayState.inMemory();
      await s.markMatchdayFinalized(5);
      final result = await s.markMatchdayFinalized(5);
      expect(result, isFalse);
    });

    test('markMatchdayFinalized rejects zero or negative', () async {
      final s = MatchdayState.inMemory();
      expect(await s.markMatchdayFinalized(0), isFalse);
      expect(await s.markMatchdayFinalized(-1), isFalse);
    });

    test('multiple matchdays can be finalized independently', () async {
      final s = MatchdayState.inMemory();
      await s.markMatchdayFinalized(3);
      await s.markMatchdayFinalized(7);
      expect(s.isMatchdayFinalized(3), isTrue);
      expect(s.isMatchdayFinalized(7), isTrue);
      expect(s.isMatchdayFinalized(5), isFalse);
    });
  });

  // ==========================================================================
  // Auto-bump
  // ==========================================================================
  group('MatchdayState – auto-bump', () {
    test('lastAutoBumpFromMatchday is null initially (in-memory)', () {
      final s = MatchdayState.inMemory();
      expect(s.lastAutoBumpFromMatchday, isNull);
    });

    test('maybeAutoBumpCassandraMatchdayCursor returns false without prefs',
        () async {
      final s = MatchdayState.inMemory();
      final result = await s.maybeAutoBumpCassandraMatchdayCursor(
        fromMatchday: 10,
      );
      expect(result, isFalse);
    });
  });

  // ==========================================================================
  // Origin kickoffs
  // ==========================================================================
  group('MatchdayState – origin kickoffs', () {
    test('registerOriginKickoff stores kickoff', () {
      final s = MatchdayState.inMemory();
      final kickoff = DateTime(2026, 3, 1, 18, 0);
      s.registerOriginKickoff(matchId: 'm1', kickoff: kickoff);

      final result = s.originKickoffFor(
        matchId: 'm1',
        fallbackKickoff: DateTime(2026, 1, 1),
      );
      expect(result.year, 2026);
      expect(result.month, 3);
      expect(result.day, 1);
    });

    test('originKickoffFor returns fallback for unknown matchId', () {
      final s = MatchdayState.inMemory();
      final fallback = DateTime(2026, 6, 15, 20, 0);
      final result = s.originKickoffFor(
        matchId: 'unknown',
        fallbackKickoff: fallback,
      );
      expect(result, fallback);
    });

    test('registerOriginKickoff does not overwrite existing', () {
      final s = MatchdayState.inMemory();
      final first = DateTime(2026, 3, 1, 18, 0);
      final second = DateTime(2026, 4, 1, 20, 0);

      s.registerOriginKickoff(matchId: 'm1', kickoff: first);
      s.registerOriginKickoff(matchId: 'm1', kickoff: second);

      final result = s.originKickoffFor(
        matchId: 'm1',
        fallbackKickoff: DateTime(2026, 1, 1),
      );
      expect(result.month, 3); // first kickoff preserved
    });

    test('persistOriginKickoffs does not throw in-memory', () async {
      final s = MatchdayState.inMemory();
      s.registerOriginKickoff(
        matchId: 'm1',
        kickoff: DateTime(2026, 3, 1, 18, 0),
      );
      await s.persistOriginKickoffs(); // no SharedPreferences, should be no-op
    });
  });

  // ==========================================================================
  // UI matchday number
  // ==========================================================================
  group('MatchdayState – uiMatchdayNumber', () {
    test('defaults to cassandraMatchdayCursor', () {
      final s = MatchdayState.inMemory();
      expect(s.uiMatchdayNumber, s.cassandraMatchdayCursor);
    });

    test('setUiMatchdayNumber overrides and notifies', () {
      final s = MatchdayState.inMemory();
      var notified = 0;
      s.addListener(() => notified++);

      s.setUiMatchdayNumber(30);
      expect(s.uiMatchdayNumber, 30);
      expect(notified, 1);
    });

    test('setUiMatchdayNumber(null) falls back to cursor', () async {
      final s = MatchdayState.inMemory();
      await s.setCassandraMatchdayCursor(12);
      s.setUiMatchdayNumber(30);
      expect(s.uiMatchdayNumber, 30);

      s.setUiMatchdayNumber(null);
      expect(s.uiMatchdayNumber, 12);
    });
  });

  // ==========================================================================
  // Matchday progress
  // ==========================================================================
  group('MatchdayState – progress', () {
    test('initial state: no progress stored', () {
      final s = MatchdayState.inMemory();
      expect(s.matchdayProgressFor(1), isNull);
    });

    test('setMatchdayProgress stores progress and notifies', () {
      final s = MatchdayState.inMemory();
      var notified = 0;
      s.addListener(() => notified++);

      final progress = _makeProgress(primaryDone: true);
      s.setMatchdayProgress(matchdayNumber: 10, progress: progress);

      expect(s.matchdayProgressFor(10), progress);
      expect(s.uiMatchdayNumber, 10);
      expect(notified, greaterThan(0));
    });

    test('setMatchdayProgress updates uiMatchdayNumber', () {
      final s = MatchdayState.inMemory();
      s.setMatchdayProgress(
        matchdayNumber: 15,
        progress: _makeProgress(),
      );
      expect(s.uiMatchdayNumber, 15);
    });

    test('clearMatchdayProgress removes and notifies', () {
      final s = MatchdayState.inMemory();
      final progress = _makeProgress();
      s.setMatchdayProgress(matchdayNumber: 10, progress: progress);

      var notified = 0;
      s.addListener(() => notified++);

      s.clearMatchdayProgress(10);
      expect(s.matchdayProgressFor(10), isNull);
      expect(notified, 1);
    });

    test('clearMatchdayProgress for non-existent is a no-op', () {
      final s = MatchdayState.inMemory();
      var notified = 0;
      s.addListener(() => notified++);

      s.clearMatchdayProgress(99);
      expect(notified, 0);
    });

    test('clearMatchdayProgress resets uiMatchdayNumber if matching', () async {
      final s = MatchdayState.inMemory();
      await s.setCassandraMatchdayCursor(5);

      s.setMatchdayProgress(
        matchdayNumber: 10,
        progress: _makeProgress(),
      );
      expect(s.uiMatchdayNumber, 10);

      s.clearMatchdayProgress(10);
      // falls back to cursor
      expect(s.uiMatchdayNumber, 5);
    });

    test('auto-advance triggers when primaryDone + valid + on cursor', () async {
      final s = MatchdayState.inMemory();
      await s.setCassandraMatchdayCursor(10);

      final progress = _makeProgress(
        primaryDone: true,
        playedFixtures: 8,
      );
      s.setMatchdayProgress(
        matchdayNumber: 10,
        progress: progress,
      );

      // Wait for microtask to complete
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      expect(s.cassandraMatchdayCursor, 11);
    });

    test('auto-advance does not trigger if allowAutoAdvance is false',
        () async {
      final s = MatchdayState.inMemory();
      await s.setCassandraMatchdayCursor(10);

      final progress = _makeProgress(
        primaryDone: true,
        playedFixtures: 8,
      );
      s.setMatchdayProgress(
        matchdayNumber: 10,
        progress: progress,
        allowAutoAdvance: false,
      );

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      expect(s.cassandraMatchdayCursor, 10);
    });

    test('auto-advance does not trigger for non-cursor matchday', () async {
      final s = MatchdayState.inMemory();
      await s.setCassandraMatchdayCursor(10);

      s.setMatchdayProgress(
        matchdayNumber: 9, // not the cursor
        progress: _makeProgress(primaryDone: true, playedFixtures: 8),
      );

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      expect(s.cassandraMatchdayCursor, 10); // unchanged
    });

    test('auto-advance does not trigger if fewer than 6 played', () async {
      final s = MatchdayState.inMemory();
      await s.setCassandraMatchdayCursor(10);

      s.setMatchdayProgress(
        matchdayNumber: 10,
        progress: _makeProgress(primaryDone: true, playedFixtures: 5),
      );

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      expect(s.cassandraMatchdayCursor, 10); // unchanged
    });

    test('auto-advance only triggers once per matchday', () async {
      final s = MatchdayState.inMemory();
      await s.setCassandraMatchdayCursor(10);

      final progress = _makeProgress(primaryDone: true, playedFixtures: 8);
      s.setMatchdayProgress(matchdayNumber: 10, progress: progress);

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      expect(s.cassandraMatchdayCursor, 11);

      // Set cursor back and repeat — auto-advance should not re-trigger for day 10
      await s.setCassandraMatchdayCursor(10);
      s.setMatchdayProgress(matchdayNumber: 10, progress: progress);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      expect(s.cassandraMatchdayCursor, 10); // no second auto-advance
    });
  });

  // ==========================================================================
  // Listener management
  // ==========================================================================
  group('MatchdayState – listeners', () {
    test('addListener / removeListener works', () {
      final s = MatchdayState.inMemory();
      var count = 0;
      void listener() => count++;

      s.addListener(listener);
      s.setUiMatchdayNumber(5);
      expect(count, 1);

      s.removeListener(listener);
      s.setUiMatchdayNumber(6);
      expect(count, 1); // no more notifications
    });
  });
}
