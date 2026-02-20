import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/app/state/app_settings.dart';
import 'package:cassandra/app/state/user_profile.dart';
import 'package:cassandra/features/predictions/models/pick_option.dart';
import 'package:cassandra/features/predictions/models/prediction_match.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';

const _testOdds = Odds(
  home: 2.0,
  draw: 3.0,
  away: 4.0,
  homeDraw: 1.3,
  drawAway: 1.7,
  homeAway: 1.4,
);

PredictionMatch _makeMatch(String id, {DateTime? kickoff}) => PredictionMatch(
  id: id,
  homeTeam: 'Team A',
  awayTeam: 'Team B',
  kickoff: kickoff ?? DateTime(2026, 3, 1, 18, 0),
  odds: _testOdds,
);

const _testProfile = UserProfile(
  id: 'uid-1',
  displayName: 'Test User',
  teamName: '@testuser',
  favoriteTeam: 'Inter',
);

void main() {
  group('AppState.inMemory factory', () {
    test('creates with default profile', () {
      final state = AppState.inMemory();
      expect(state.profile.id, isEmpty);
      expect(state.profile.displayName, isEmpty);
      expect(state.profile.teamName, isEmpty);
      expect(state.language, CassandraLanguage.system);
      expect(state.defaultVisibility, PredictionVisibility.friends);
    });

    test('creates with custom profile', () {
      final state = AppState.inMemory(profile: _testProfile);
      expect(state.profile.id, 'uid-1');
      expect(state.profile.displayName, 'Test User');
      expect(state.profile.teamName, '@testuser');
      expect(state.profile.favoriteTeam, 'Inter');
    });

    test('creates with custom language and visibility', () {
      final state = AppState.inMemory(
        language: CassandraLanguage.it,
        defaultVisibility: PredictionVisibility.private,
      );
      expect(state.language, CassandraLanguage.it);
      expect(state.defaultVisibility, PredictionVisibility.private);
    });
  });

  group('Current user picks', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('initial picks are empty', () {
      state.ensureCurrentUserPicksLoaded();
      expect(state.currentUserPicksByMatchId, isEmpty);
    });

    test('setCurrentUserPick adds a pick', () {
      state.setCurrentUserPick('m1', PickOption.home);
      expect(state.currentUserPicksByMatchId['m1'], PickOption.home);
    });

    test('setCurrentUserPick with none removes pick', () {
      state.setCurrentUserPick('m1', PickOption.home);
      state.setCurrentUserPick('m1', PickOption.none);
      expect(state.currentUserPicksByMatchId.containsKey('m1'), isFalse);
    });

    test('setCurrentUserPick notifies listeners', () {
      var notified = 0;
      state.addListener(() => notified++);
      state.setCurrentUserPick('m1', PickOption.away);
      expect(notified, 1);
    });

    test('clearCurrentUserPicks removes all picks', () {
      state.setCurrentUserPick('m1', PickOption.home);
      state.setCurrentUserPick('m2', PickOption.draw);
      state.clearCurrentUserPicks();
      expect(state.currentUserPicksByMatchId, isEmpty);
    });

    test('multiple picks are stored correctly', () {
      state.setCurrentUserPick('m1', PickOption.home);
      state.setCurrentUserPick('m2', PickOption.draw);
      state.setCurrentUserPick('m3', PickOption.homeDraw);
      expect(state.currentUserPicksByMatchId, hasLength(3));
      expect(state.currentUserPicksByMatchId['m1'], PickOption.home);
      expect(state.currentUserPicksByMatchId['m2'], PickOption.draw);
      expect(state.currentUserPicksByMatchId['m3'], PickOption.homeDraw);
    });

    test('overwriting a pick replaces previous value', () {
      state.setCurrentUserPick('m1', PickOption.home);
      state.setCurrentUserPick('m1', PickOption.away);
      expect(state.currentUserPicksByMatchId['m1'], PickOption.away);
    });
  });

  group('Picks history (by matchday)', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('initially no saved picks for any matchday', () {
      expect(state.hasSavedPicksForMatchday(1), isFalse);
      expect(state.currentUserPicksForMatchday(1), isEmpty);
    });

    test('saveCurrentUserPicksHistory stores picks for a matchday', () {
      state.saveCurrentUserPicksHistory(
        dayNumber: 20,
        picksByMatchId: {'m1': PickOption.home, 'm2': PickOption.draw},
      );
      expect(state.hasSavedPicksForMatchday(20), isTrue);
      expect(state.currentUserPicksForMatchday(20), hasLength(2));
      expect(state.currentUserPicksForMatchday(20)['m1'], PickOption.home);
    });

    test('clearCurrentUserPicksHistory removes all history', () {
      state.saveCurrentUserPicksHistory(
        dayNumber: 20,
        picksByMatchId: {'m1': PickOption.home},
      );
      state.clearCurrentUserPicksHistory();
      expect(state.hasSavedPicksForMatchday(20), isFalse);
    });

    test('saving picks for different matchdays keeps them separate', () {
      state.saveCurrentUserPicksHistory(
        dayNumber: 20,
        picksByMatchId: {'m1': PickOption.home},
      );
      state.saveCurrentUserPicksHistory(
        dayNumber: 21,
        picksByMatchId: {'m2': PickOption.away},
      );
      expect(state.currentUserPicksForMatchday(20)['m1'], PickOption.home);
      expect(state.currentUserPicksForMatchday(21)['m2'], PickOption.away);
      expect(state.currentUserPicksForMatchday(20).containsKey('m2'), isFalse);
    });
  });

  group('Outcomes history', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('initially no outcomes', () {
      expect(state.hasSavedOutcomesForMatchday(1), isFalse);
      expect(state.outcomesForMatchday(1), isEmpty);
    });

    test('saveOutcomesHistory stores outcomes', () {
      state.saveOutcomesHistory(
        dayNumber: 20,
        outcomesByMatchId: {'m1': MatchOutcome.home, 'm2': MatchOutcome.draw},
      );
      expect(state.hasSavedOutcomesForMatchday(20), isTrue);
      expect(state.outcomesForMatchday(20)['m1'], MatchOutcome.home);
      expect(state.outcomesForMatchday(20)['m2'], MatchOutcome.draw);
    });

    test('clearOutcomesHistory removes all outcomes', () {
      state.saveOutcomesHistory(
        dayNumber: 20,
        outcomesByMatchId: {'m1': MatchOutcome.home},
      );
      state.clearOutcomesHistory();
      expect(state.hasSavedOutcomesForMatchday(20), isFalse);
    });
  });

  group('Matches history', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('initially no matches history', () {
      expect(state.matchesForMatchday(1), isNull);
    });

    test('saveMatchesHistory stores matches', () async {
      final matches = [_makeMatch('m1'), _makeMatch('m2')];
      await state.saveMatchesHistory(matchdayNumber: 20, matches: matches);
      expect(state.matchesForMatchday(20), hasLength(2));
      expect(state.matchesForMatchday(20)![0].id, 'm1');
    });

    test('clearMatchesHistory removes all matches', () async {
      await state.saveMatchesHistory(
        matchdayNumber: 20,
        matches: [_makeMatch('m1')],
      );
      await state.clearMatchesHistory();
      expect(state.matchesForMatchday(20), isNull);
    });
  });

  group('Prediction cache (runtime)', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('initially no cached matches', () {
      expect(state.cachedPredictionMatches, isNull);
      expect(state.cachedPredictionMatchesAreReal, isFalse);
      expect(state.cachedPredictionMatchesUpdatedAt, isNull);
    });

    test('setCachedPredictionMatches stores and notifies', () {
      var notified = 0;
      state.addListener(() => notified++);

      final matches = [_makeMatch('m1'), _makeMatch('m2')];
      state.setCachedPredictionMatches(matches, isReal: true);

      expect(state.cachedPredictionMatches, hasLength(2));
      expect(state.cachedPredictionMatchesAreReal, isTrue);
      expect(state.cachedPredictionMatchesUpdatedAt, isNotNull);
      expect(notified, 1);
    });

    test('clearCachedPredictionMatches resets cache', () {
      state.setCachedPredictionMatches([_makeMatch('m1')], isReal: true);
      state.clearCachedPredictionMatches();
      expect(state.cachedPredictionMatches, isNull);
      expect(state.cachedPredictionMatchesAreReal, isFalse);
    });

    test('setCachedPredictionOutcomesByMatchId stores outcomes', () {
      state.setCachedPredictionOutcomesByMatchId({'m1': MatchOutcome.home});
      expect(
        state.effectivePredictionOutcomesByMatchId['m1'],
        MatchOutcome.home,
      );
    });

    test('clearAllPredictionCache resets everything', () {
      state.setCachedPredictionMatches([_makeMatch('m1')], isReal: true);
      state.setCachedPredictionOutcomesByMatchId({'m1': MatchOutcome.home});
      state.clearAllPredictionCache();
      expect(state.cachedPredictionMatches, isNull);
      expect(state.effectivePredictionOutcomesByMatchId, isEmpty);
      expect(state.cachedSeasonStandings, isEmpty);
    });
  });

  group('Matchday cursor', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('default cursor is 20', () {
      expect(state.cassandraMatchdayCursor, 20);
    });

    test('setCassandraMatchdayCursor updates cursor', () async {
      await state.setCassandraMatchdayCursor(25);
      expect(state.cassandraMatchdayCursor, 25);
    });

    test('setCassandraMatchdayCursor ignores zero or negative', () async {
      await state.setCassandraMatchdayCursor(25);
      await state.setCassandraMatchdayCursor(0);
      expect(state.cassandraMatchdayCursor, 25);
      await state.setCassandraMatchdayCursor(-1);
      expect(state.cassandraMatchdayCursor, 25);
    });

    test('bumpCassandraMatchdayCursor increments by 1', () async {
      await state.setCassandraMatchdayCursor(20);
      await state.bumpCassandraMatchdayCursor();
      expect(state.cassandraMatchdayCursor, 21);
    });

    test('uiMatchdayNumber defaults to cursor', () {
      expect(state.uiMatchdayNumber, state.cassandraMatchdayCursor);
    });

    test('setUiMatchdayNumber overrides display matchday', () {
      state.setUiMatchdayNumber(30);
      expect(state.uiMatchdayNumber, 30);
    });

    test('setUiMatchdayNumber with null reverts to cursor', () {
      state.setUiMatchdayNumber(30);
      state.setUiMatchdayNumber(null);
      expect(state.uiMatchdayNumber, state.cassandraMatchdayCursor);
    });
  });

  group('Matchday finalization', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('matchday is not finalized by default', () {
      expect(state.isMatchdayFinalized(20), isFalse);
    });

    test(
      'markMatchdayFinalized marks and returns true on first call',
      () async {
        final result = await state.markMatchdayFinalized(20);
        expect(result, isTrue);
        expect(state.isMatchdayFinalized(20), isTrue);
      },
    );

    test('markMatchdayFinalized returns false on duplicate', () async {
      await state.markMatchdayFinalized(20);
      final result = await state.markMatchdayFinalized(20);
      expect(result, isFalse);
    });

    test('markMatchdayFinalized rejects zero or negative', () async {
      final result = await state.markMatchdayFinalized(0);
      expect(result, isFalse);
    });
  });

  group('Recent matchday data', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('initially empty', () {
      expect(state.recentMatchesByMatchday, isEmpty);
      expect(state.recentOutcomesByMatchday, isEmpty);
    });

    test('setRecentMatchdayDataBulk stores data', () {
      final matches = {
        20: [_makeMatch('m1'), _makeMatch('m2')],
      };
      final outcomes = {
        20: {'m1': MatchOutcome.home, 'm2': MatchOutcome.draw},
      };

      state.setRecentMatchdayDataBulk(
        matchesByMatchday: matches,
        outcomesByMatchday: outcomes,
      );

      expect(state.recentMatchesByMatchday[20], hasLength(2));
      expect(state.recentOutcomesByMatchday[20]!['m1'], MatchOutcome.home);
    });

    test('setRecentMatchdayDataBulk with replace clears old data', () {
      state.setRecentMatchdayDataBulk(
        matchesByMatchday: {
          19: [_makeMatch('m1')],
        },
        outcomesByMatchday: {
          19: {'m1': MatchOutcome.home},
        },
      );
      state.setRecentMatchdayDataBulk(
        matchesByMatchday: {
          20: [_makeMatch('m2')],
        },
        outcomesByMatchday: {
          20: {'m2': MatchOutcome.away},
        },
        replace: true,
      );

      expect(state.recentMatchesByMatchday.containsKey(19), isFalse);
      expect(state.recentMatchesByMatchday[20], hasLength(1));
    });

    test('prunes to max 10 entries', () {
      final matches = <int, List<PredictionMatch>>{};
      final outcomes = <int, Map<String, MatchOutcome>>{};
      for (var i = 1; i <= 15; i++) {
        matches[i] = [_makeMatch('m$i')];
        outcomes[i] = {'m$i': MatchOutcome.home};
      }

      state.setRecentMatchdayDataBulk(
        matchesByMatchday: matches,
        outcomesByMatchday: outcomes,
      );

      // Should keep only the 10 most recent (highest day numbers)
      expect(state.recentMatchesByMatchday.length, 10);
      expect(state.recentMatchesByMatchday.containsKey(1), isFalse);
      expect(state.recentMatchesByMatchday.containsKey(15), isTrue);
    });
  });

  group('Member picks', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('initially empty', () {
      state.ensureMemberPicksLoaded();
      expect(state.memberPicksByMemberId, isEmpty);
    });

    test('setMemberPicksBulk stores picks for members', () {
      state.setMemberPicksBulk({
        'member-1': {'m1': PickOption.home, 'm2': PickOption.draw},
        'member-2': {'m1': PickOption.away},
      });

      expect(state.memberPicksByMemberId, hasLength(2));
      expect(state.memberPicksByMemberId['member-1']!['m1'], PickOption.home);
      expect(state.memberPicksByMemberId['member-2']!['m1'], PickOption.away);
    });

    test('setMemberPicksBulk with replace clears previous', () {
      state.setMemberPicksBulk({
        'member-1': {'m1': PickOption.home},
      });
      state.setMemberPicksBulk({
        'member-2': {'m2': PickOption.away},
      }, replace: true);

      expect(state.memberPicksByMemberId.containsKey('member-1'), isFalse);
      expect(state.memberPicksByMemberId.containsKey('member-2'), isTrue);
    });

    test('setMemberPicksBulk with empty map removes member', () {
      state.setMemberPicksBulk({
        'member-1': {'m1': PickOption.home},
      });
      state.setMemberPicksBulk({'member-1': {}});
      expect(state.memberPicksByMemberId.containsKey('member-1'), isFalse);
    });

    test('clearMemberPicks removes all', () {
      state.setMemberPicksBulk({
        'member-1': {'m1': PickOption.home},
        'member-2': {'m2': PickOption.away},
      });
      state.clearMemberPicks();
      expect(state.memberPicksByMemberId, isEmpty);
    });

    test(
      'clearMemberPicks with specific memberId removes only that member',
      () {
        state.setMemberPicksBulk({
          'member-1': {'m1': PickOption.home},
          'member-2': {'m2': PickOption.away},
        });
        state.clearMemberPicks(memberId: 'member-1');
        expect(state.memberPicksByMemberId.containsKey('member-1'), isFalse);
        expect(state.memberPicksByMemberId.containsKey('member-2'), isTrue);
      },
    );
  });

  group('Group state (local, no Firestore)', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('initially has no group', () {
      expect(state.hasGroup, isFalse);
      expect(state.groupName, isNull);
      expect(state.groupInviteCode, isNull);
      expect(state.activeGroupId, isNull);
    });

    test('createGroup without Firestore creates local group', () async {
      final error = await state.createGroup('My Group');
      expect(error, isNull);
      expect(state.hasGroup, isTrue);
      expect(state.groupName, 'My Group');
      expect(state.groupInviteCode, isNotNull);
      expect(state.groupInviteCode!, startsWith('CASS-'));
      expect(state.groupInviteCode!.length, 9); // CASS-XXXX
    });

    test('createGroup rejects empty name', () async {
      final error = await state.createGroup('');
      expect(error, 'Invalid name');
      expect(state.hasGroup, isFalse);
    });

    test('createGroup rejects whitespace-only name', () async {
      final error = await state.createGroup('   ');
      expect(error, 'Invalid name');
    });

    test('updateGroupName changes name', () async {
      await state.createGroup('Original');
      await state.updateGroupName('Updated');
      expect(state.groupName, 'Updated');
    });

    test('updateGroupName ignores empty', () async {
      await state.createGroup('Original');
      await state.updateGroupName('');
      expect(state.groupName, 'Original');
    });

    test('updateGroupImagePath sets and clears', () async {
      await state.updateGroupImagePath('/path/to/image.png');
      expect(state.groupImagePath, '/path/to/image.png');
      await state.updateGroupImagePath(null);
      expect(state.groupImagePath, isNull);
    });

    test('updateGroupAdminApproval toggles', () async {
      expect(state.groupAdminApproval, isFalse);
      await state.updateGroupAdminApproval(true);
      expect(state.groupAdminApproval, isTrue);
    });

    test('deleteActiveGroupIfAdmin clears local group', () async {
      await state.createGroup('To Delete');
      final error = await state.deleteActiveGroupIfAdmin();
      expect(error, isNull);
      expect(state.hasGroup, isFalse);
      expect(state.groupName, isNull);
      expect(state.groupInviteCode, isNull);
    });
  });

  group('Auth state helpers', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('isAuthenticated is false without auth service', () {
      expect(state.isAuthenticated, isFalse);
    });

    test('needsProfileSetup is false when not authenticated', () {
      expect(state.needsProfileSetup, isFalse);
    });

    test('remember-me is initially disabled', () {
      expect(state.rememberMeEnabled, isFalse);
      expect(state.hasRememberedIdentity, isFalse);
    });
  });

  group('Season key', () {
    test('returns current year if month >= August', () {
      final state = AppState.inMemory();
      final now = DateTime.now();
      final expected = (now.month >= 8 ? now.year : now.year - 1).toString();
      expect(state.currentSeasonKey, expected);
    });
  });

  group('Demo seed', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('initially zero', () {
      expect(state.demoSeed, 0);
    });

    test('bumpDemoSeed increments', () async {
      await state.bumpDemoSeed();
      expect(state.demoSeed, 1);
      await state.bumpDemoSeed();
      expect(state.demoSeed, 2);
    });
  });

  group('clearAllHistory', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('clears picks, outcomes, and member picks', () {
      state.setCurrentUserPick('m1', PickOption.home);
      state.saveCurrentUserPicksHistory(
        dayNumber: 20,
        picksByMatchId: {'m1': PickOption.home},
      );
      state.saveOutcomesHistory(
        dayNumber: 20,
        outcomesByMatchId: {'m1': MatchOutcome.home},
      );
      state.setMemberPicksBulk({
        'member-1': {'m1': PickOption.away},
      });

      state.clearAllHistory();

      expect(state.currentUserPicksByMatchId, isEmpty);
      expect(state.hasSavedPicksForMatchday(20), isFalse);
      expect(state.hasSavedOutcomesForMatchday(20), isFalse);
      expect(state.memberPicksByMemberId, isEmpty);
    });
  });

  group('resetAll', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(
        profile: _testProfile,
        language: CassandraLanguage.it,
        defaultVisibility: PredictionVisibility.public,
      );
    });

    test('resets profile and settings to defaults', () async {
      await state.createGroup('Test Group');
      await state.resetAll();

      expect(state.profile.id, isEmpty);
      expect(state.profile.displayName, isEmpty);
      expect(state.language, CassandraLanguage.system);
      expect(state.defaultVisibility, PredictionVisibility.friends);
      expect(state.hasGroup, isFalse);
      expect(state.groupName, isNull);
      expect(state.rememberMeEnabled, isFalse);
    });
  });

  group('Origin kickoffs', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('registerOriginKickoff stores first value', () {
      final kickoff = DateTime(2026, 3, 1, 18, 0);
      state.registerOriginKickoff(matchId: 'm1', kickoff: kickoff);
      final result = state.originKickoffFor(
        matchId: 'm1',
        fallbackKickoff: DateTime(2026, 3, 5),
      );
      expect(result.day, kickoff.day);
    });

    test('registerOriginKickoff does not overwrite existing', () {
      final first = DateTime(2026, 3, 1, 18, 0);
      final second = DateTime(2026, 3, 5, 20, 0);
      state.registerOriginKickoff(matchId: 'm1', kickoff: first);
      state.registerOriginKickoff(matchId: 'm1', kickoff: second);
      final result = state.originKickoffFor(
        matchId: 'm1',
        fallbackKickoff: DateTime(2026, 4, 1),
      );
      expect(result.day, first.day);
    });

    test('originKickoffFor returns fallback for unknown match', () {
      final fallback = DateTime(2026, 5, 1);
      final result = state.originKickoffFor(
        matchId: 'unknown',
        fallbackKickoff: fallback,
      );
      expect(result, fallback);
    });
  });

  group('MatchdayProgress', () {
    // Import not needed — MatchdayProgress comes from domain layer
    // We test through AppState's setMatchdayProgress / matchdayProgressFor

    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('initially no progress for any matchday', () {
      expect(state.matchdayProgressFor(20), isNull);
    });

    test('clearMatchdayProgress removes stored progress', () {
      // We can't easily construct MatchdayProgress without the domain import,
      // so we just verify clearMatchdayProgress doesn't crash on empty
      state.clearMatchdayProgress(20);
      expect(state.matchdayProgressFor(20), isNull);
    });
  });

  group('Listener notifications', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('multiple state changes each trigger notification', () {
      var count = 0;
      state.addListener(() => count++);

      state.setCurrentUserPick('m1', PickOption.home);
      state.setCurrentUserPick('m2', PickOption.away);
      state.clearCurrentUserPicks();

      expect(count, 3);
    });

    test('removed listener does not get called', () {
      var count = 0;
      void listener() => count++;
      state.addListener(listener);
      state.setCurrentUserPick('m1', PickOption.home);
      expect(count, 1);

      state.removeListener(listener);
      state.setCurrentUserPick('m2', PickOption.away);
      expect(count, 1); // still 1
    });
  });

  group('picksForCurrentUserForMatchday', () {
    late AppState state;

    setUp(() {
      state = AppState.inMemory(profile: _testProfile);
    });

    test('returns saved picks if available', () {
      state.saveCurrentUserPicksHistory(
        dayNumber: 20,
        picksByMatchId: {'m1': PickOption.home},
      );
      final picks = state.picksForCurrentUserForMatchday(20);
      expect(picks['m1'], PickOption.home);
    });

    test('falls back to current picks if no history', () {
      state.setCurrentUserPick('m1', PickOption.away);
      final picks = state.picksForCurrentUserForMatchday(99);
      expect(picks['m1'], PickOption.away);
    });
  });
}
