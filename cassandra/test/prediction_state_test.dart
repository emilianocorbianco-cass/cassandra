import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cassandra/app/state/prediction_state.dart';
import 'package:cassandra/features/predictions/models/pick_option.dart';
import 'package:cassandra/features/predictions/models/prediction_match.dart';
import 'package:cassandra/features/scoring/models/match_outcome.dart';
import 'package:cassandra/services/firestore/firestore_serializers.dart';

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

void main() {
  // ==========================================================================
  // Current user picks
  // ==========================================================================
  group('PredictionState – current user picks', () {
    test('initial state is empty', () {
      final s = PredictionState.inMemory();
      expect(s.currentUserPicksByMatchId, isEmpty);
    });

    test('setCurrentUserPick adds a pick and notifies', () {
      final s = PredictionState.inMemory();
      var notified = 0;
      s.addListener(() => notified++);

      s.setCurrentUserPick('m1', PickOption.home);
      expect(s.currentUserPicksByMatchId['m1'], PickOption.home);
      expect(notified, 1);
    });

    test('setCurrentUserPick with none removes', () {
      final s = PredictionState.inMemory();
      s.setCurrentUserPick('m1', PickOption.home);
      s.setCurrentUserPick('m1', PickOption.none);
      expect(s.currentUserPicksByMatchId.containsKey('m1'), isFalse);
    });

    test('clearCurrentUserPicks resets all picks', () {
      final s = PredictionState.inMemory();
      s.setCurrentUserPick('m1', PickOption.home);
      s.setCurrentUserPick('m2', PickOption.away);

      var notified = 0;
      s.addListener(() => notified++);
      s.clearCurrentUserPicks();

      expect(s.currentUserPicksByMatchId, isEmpty);
      expect(notified, 1);
    });

    test('overwriting a pick replaces value', () {
      final s = PredictionState.inMemory();
      s.setCurrentUserPick('m1', PickOption.home);
      s.setCurrentUserPick('m1', PickOption.draw);
      expect(s.currentUserPicksByMatchId['m1'], PickOption.draw);
    });
  });

  // ==========================================================================
  // Picks history
  // ==========================================================================
  group('PredictionState – picks history', () {
    test('saveCurrentUserPicksHistory persists and notifies', () {
      final s = PredictionState.inMemory();
      var notified = 0;
      s.addListener(() => notified++);

      s.saveCurrentUserPicksHistory(
        dayNumber: 20,
        picksByMatchId: {'m1': PickOption.home, 'm2': PickOption.draw},
      );

      expect(s.hasSavedPicksForMatchday(20), isTrue);
      expect(s.hasSavedPicksForMatchday(21), isFalse);
      expect(s.currentUserPicksForMatchday(20)['m1'], PickOption.home);
      expect(notified, 1);
    });

    test('clearCurrentUserPicksHistory empties', () {
      final s = PredictionState.inMemory();
      s.saveCurrentUserPicksHistory(
        dayNumber: 20,
        picksByMatchId: {'m1': PickOption.home},
      );
      s.clearCurrentUserPicksHistory();

      expect(s.hasSavedPicksForMatchday(20), isFalse);
      expect(s.currentUserPicksByMatchday, isEmpty);
    });

    test('currentUserPicksForMatchday returns empty map for missing day', () {
      final s = PredictionState.inMemory();
      expect(s.currentUserPicksForMatchday(99), isEmpty);
    });

    test('picksForCurrentUserForMatchday fallback to live picks', () {
      final s = PredictionState.inMemory();
      s.setCurrentUserPick('m1', PickOption.away);
      // No history for day 20 → should fallback to current picks
      final result = s.picksForCurrentUserForMatchday(20);
      expect(result['m1'], PickOption.away);
    });

    test('picksForCurrentUserForMatchday returns saved history', () {
      final s = PredictionState.inMemory();
      s.setCurrentUserPick('live-m', PickOption.home);
      s.saveCurrentUserPicksHistory(
        dayNumber: 20,
        picksByMatchId: {'saved-m': PickOption.draw},
      );

      final result = s.picksForCurrentUserForMatchday(20);
      expect(result['saved-m'], PickOption.draw);
      expect(result.containsKey('live-m'), isFalse);
    });

    test('picks history views are immutable', () {
      final s = PredictionState.inMemory();
      s.saveCurrentUserPicksHistory(
        dayNumber: 20,
        picksByMatchId: {'m1': PickOption.home},
      );

      final byDay = s.currentUserPicksByMatchday;
      expect(() => byDay[21] = {'m2': PickOption.away}, throwsUnsupportedError);
      expect(() => byDay[20]!['m2'] = PickOption.away, throwsUnsupportedError);
      final picks = s.currentUserPicksForMatchday(20);
      expect(() => picks['m3'] = PickOption.draw, throwsUnsupportedError);
    });
  });

  // ==========================================================================
  // Outcomes history
  // ==========================================================================
  group('PredictionState – outcomes history', () {
    test('saveOutcomesHistory stores outcomes', () {
      final s = PredictionState.inMemory();
      s.saveOutcomesHistory(
        dayNumber: 20,
        outcomesByMatchId: {'m1': MatchOutcome.home, 'm2': MatchOutcome.draw},
      );

      expect(s.hasSavedOutcomesForMatchday(20), isTrue);
      expect(s.outcomesForMatchday(20)['m1'], MatchOutcome.home);
    });

    test('clearOutcomesHistory empties', () {
      final s = PredictionState.inMemory();
      s.saveOutcomesHistory(
        dayNumber: 20,
        outcomesByMatchId: {'m1': MatchOutcome.home},
      );
      s.clearOutcomesHistory();

      expect(s.hasSavedOutcomesForMatchday(20), isFalse);
      expect(s.outcomesByMatchday, isEmpty);
    });

    test('outcomesForMatchday returns empty for missing day', () {
      final s = PredictionState.inMemory();
      expect(s.outcomesForMatchday(99), isEmpty);
    });

    test('outcomes history views are immutable', () {
      final s = PredictionState.inMemory();
      s.saveOutcomesHistory(
        dayNumber: 20,
        outcomesByMatchId: {'m1': MatchOutcome.home},
      );

      final byDay = s.outcomesByMatchday;
      expect(
        () => byDay[21] = {'m2': MatchOutcome.away},
        throwsUnsupportedError,
      );
      expect(
        () => byDay[20]!['m2'] = MatchOutcome.away,
        throwsUnsupportedError,
      );
      final outcomes = s.outcomesForMatchday(20);
      expect(() => outcomes['m3'] = MatchOutcome.draw, throwsUnsupportedError);
    });
  });

  // ==========================================================================
  // Matches history (in-memory)
  // ==========================================================================
  group('PredictionState – matches history', () {
    test('saveMatchesHistory stores matches', () async {
      final s = PredictionState.inMemory();
      final m = _makeMatch('m1');
      await s.saveMatchesHistory(matchdayNumber: 20, matches: [m]);

      expect(s.matchesForMatchday(20), isNotNull);
      expect(s.matchesForMatchday(20)!.length, 1);
      expect(s.matchesForMatchday(20)!.first.id, 'm1');
    });

    test('clearMatchesHistory empties', () async {
      final s = PredictionState.inMemory();
      await s.saveMatchesHistory(
        matchdayNumber: 20,
        matches: [_makeMatch('m1')],
      );
      await s.clearMatchesHistory();

      expect(s.matchesForMatchday(20), isNull);
      expect(s.matchesByMatchday, isEmpty);
    });

    test('matchesForMatchday returns null for missing day', () {
      final s = PredictionState.inMemory();
      expect(s.matchesForMatchday(99), isNull);
    });

    test('matches history views are immutable', () async {
      final s = PredictionState.inMemory();
      await s.saveMatchesHistory(
        matchdayNumber: 20,
        matches: [_makeMatch('m1')],
      );

      final byDay = s.matchesByMatchday;
      expect(() => byDay[21] = [_makeMatch('m2')], throwsUnsupportedError);
      expect(() => byDay[20]!.add(_makeMatch('m2')), throwsUnsupportedError);

      final matches = s.matchesForMatchday(20)!;
      expect(() => matches.add(_makeMatch('m3')), throwsUnsupportedError);
    });
  });

  // ==========================================================================
  // Matchday matches snapshots
  // ==========================================================================
  group('PredictionState – matchday matches snapshots', () {
    test('saveMatchdayMatchesSnapshot stores and notifies', () async {
      final s = PredictionState.inMemory();
      var notified = 0;
      s.addListener(() => notified++);

      final m = _makeMatch('m1');
      await s.saveMatchdayMatchesSnapshot(matchdayNumber: 20, matches: [m]);

      expect(s.hasSavedMatchesForMatchday(20), isTrue);
      expect(s.savedMatchesForMatchday(20)!.first.id, 'm1');
      expect(notified, 1);
    });

    test('hasSavedMatchesForMatchday false for missing day', () {
      final s = PredictionState.inMemory();
      expect(s.hasSavedMatchesForMatchday(99), isFalse);
    });

    test('savedMatchesForMatchday null for missing day', () {
      final s = PredictionState.inMemory();
      expect(s.savedMatchesForMatchday(99), isNull);
    });

    test('ensureMatchdayMatchesLoaded ignores corrupt JSON payload', () async {
      SharedPreferences.setMockInitialValues({
        'matchdayMatchesByDay.v1': '{not-json',
      });
      final prefs = await SharedPreferences.getInstance();
      final s = PredictionState.fromPrefs(prefs);

      await s.ensureMatchdayMatchesLoaded();

      expect(s.matchdayMatchesByDay, isEmpty);
      expect(s.hasSavedMatchesForMatchday(20), isFalse);
    });

    test(
      'ensureMatchdayMatchesLoaded keeps valid days and skips bad rows',
      () async {
        final validMatch = FirestoreSerializers.predictionMatchToMap(
          _makeMatch('m-valid'),
        );
        final payload = jsonEncode({
          '20': [
            validMatch,
            {'broken': true},
          ],
          'bad-day': [validMatch],
          '21': 'not-a-list',
        });
        SharedPreferences.setMockInitialValues({
          'matchdayMatchesByDay.v1': payload,
        });
        final prefs = await SharedPreferences.getInstance();
        final s = PredictionState.fromPrefs(prefs);

        await s.ensureMatchdayMatchesLoaded();

        expect(s.hasSavedMatchesForMatchday(20), isTrue);
        expect(s.savedMatchesForMatchday(20)!.single.id, 'm-valid');
        expect(s.matchdayMatchesByDay.containsKey(21), isFalse);
      },
    );
  });

  // ==========================================================================
  // Member picks
  // ==========================================================================
  group('PredictionState – member picks', () {
    test('setMemberPicksBulk stores picks', () {
      final s = PredictionState.inMemory();
      s.setMemberPicksBulk({
        'alice': {'m1': PickOption.home},
        'bob': {'m1': PickOption.away},
      });

      expect(s.memberPicksByMemberId['alice']!['m1'], PickOption.home);
      expect(s.memberPicksByMemberId['bob']!['m1'], PickOption.away);
    });

    test('setMemberPicksBulk with replace clears old', () {
      final s = PredictionState.inMemory();
      s.setMemberPicksBulk({
        'alice': {'m1': PickOption.home},
      });
      s.setMemberPicksBulk({
        'bob': {'m1': PickOption.draw},
      }, replace: true);

      expect(s.memberPicksByMemberId.containsKey('alice'), isFalse);
      expect(s.memberPicksByMemberId['bob']!['m1'], PickOption.draw);
    });

    test('clearMemberPicks all', () {
      final s = PredictionState.inMemory();
      s.setMemberPicksBulk({
        'alice': {'m1': PickOption.home},
      });
      s.clearMemberPicks();

      expect(s.memberPicksByMemberId, isEmpty);
    });

    test('clearMemberPicks selective by memberId', () {
      final s = PredictionState.inMemory();
      s.setMemberPicksBulk({
        'alice': {'m1': PickOption.home},
        'bob': {'m1': PickOption.away},
      });
      s.clearMemberPicks(memberId: 'alice');

      expect(s.memberPicksByMemberId.containsKey('alice'), isFalse);
      expect(s.memberPicksByMemberId.containsKey('bob'), isTrue);
    });

    test('setMemberPicksBulk removes member with empty picks', () {
      final s = PredictionState.inMemory();
      s.setMemberPicksBulk({
        'alice': {'m1': PickOption.home},
      });
      s.setMemberPicksBulk({'alice': <String, PickOption>{}});

      expect(s.memberPicksByMemberId.containsKey('alice'), isFalse);
    });
  });

  // ==========================================================================
  // Runtime cache
  // ==========================================================================
  group('PredictionState – runtime cache', () {
    test('initial cache state', () {
      final s = PredictionState.inMemory();
      expect(s.cachedPredictionMatches, isNull);
      expect(s.cachedPredictionMatchesAreReal, isFalse);
      expect(s.cachedPredictionMatchesUpdatedAt, isNull);
      expect(s.cachedRealOdds, isNull);
      expect(s.cachedSeasonStandings, isEmpty);
      expect(s.cachedSeasonStandingsUpdatedAt, isNull);
      expect(s.cachedPredictionOutcomesByMatchId, isEmpty);
    });

    test('setCachedPredictionMatches stores and notifies', () {
      final s = PredictionState.inMemory();
      var notified = 0;
      s.addListener(() => notified++);

      final ts = DateTime(2026, 3, 1);
      s.setCachedPredictionMatches(
        [_makeMatch('m1')],
        isReal: true,
        updatedAt: ts,
      );

      expect(s.cachedPredictionMatches!.length, 1);
      expect(s.cachedPredictionMatchesAreReal, isTrue);
      expect(s.cachedPredictionMatchesUpdatedAt, ts);
      expect(notified, 1);
    });

    test('clearCachedPredictionMatches resets', () {
      final s = PredictionState.inMemory();
      s.setCachedPredictionMatches([_makeMatch('m1')], isReal: true);
      s.clearCachedPredictionMatches();

      expect(s.cachedPredictionMatches, isNull);
      expect(s.cachedPredictionMatchesAreReal, isFalse);
    });

    test('setCachedPredictionOutcomesByMatchId stores', () {
      final s = PredictionState.inMemory();
      s.setCachedPredictionOutcomesByMatchId({'m1': MatchOutcome.home});
      expect(s.cachedPredictionOutcomesByMatchId['m1'], MatchOutcome.home);
    });

    test('clearCachedPredictionOutcomes resets', () {
      final s = PredictionState.inMemory();
      s.setCachedPredictionOutcomesByMatchId({'m1': MatchOutcome.home});
      s.clearCachedPredictionOutcomes();
      expect(s.cachedPredictionOutcomesByMatchId, isEmpty);
    });

    test('clearAllPredictionCache resets everything', () {
      final s = PredictionState.inMemory();
      s.setCachedPredictionMatches([_makeMatch('m1')], isReal: true);
      s.setCachedPredictionOutcomesByMatchId({'m1': MatchOutcome.home});
      s.clearAllPredictionCache();

      expect(s.cachedPredictionMatches, isNull);
      expect(s.cachedPredictionOutcomesByMatchId, isEmpty);
      expect(s.cachedSeasonStandings, isEmpty);
    });

    test('effectivePredictionOutcomesByMatchId delegates', () {
      final s = PredictionState.inMemory();
      s.setCachedPredictionOutcomesByMatchId({'m1': MatchOutcome.draw});
      expect(s.effectivePredictionOutcomesByMatchId['m1'], MatchOutcome.draw);
    });
  });

  // ==========================================================================
  // Recent matchday data
  // ==========================================================================
  group('PredictionState – recent matchday data', () {
    test('setRecentMatchdayDataBulk stores data', () {
      final s = PredictionState.inMemory();
      var notified = 0;
      s.addListener(() => notified++);

      s.setRecentMatchdayDataBulk(
        matchesByMatchday: {
          20: [_makeMatch('m1')],
        },
        outcomesByMatchday: {
          20: {'m1': MatchOutcome.home},
        },
      );

      expect(s.recentMatchesByMatchday[20]!.length, 1);
      expect(s.recentOutcomesByMatchday[20]!['m1'], MatchOutcome.home);
      expect(notified, 1);
    });

    test('setRecentMatchdayDataBulk replace clears old data', () {
      final s = PredictionState.inMemory();
      s.setRecentMatchdayDataBulk(
        matchesByMatchday: {
          20: [_makeMatch('m1')],
        },
        outcomesByMatchday: {},
      );
      s.setRecentMatchdayDataBulk(
        matchesByMatchday: {
          21: [_makeMatch('m2')],
        },
        outcomesByMatchday: {},
        replace: true,
      );

      expect(s.recentMatchesByMatchday.containsKey(20), isFalse);
      expect(s.recentMatchesByMatchday[21]!.first.id, 'm2');
    });

    test('recent matchday views are immutable', () {
      final s = PredictionState.inMemory();
      s.setRecentMatchdayDataBulk(
        matchesByMatchday: {
          20: [_makeMatch('m1')],
        },
        outcomesByMatchday: {
          20: {'m1': MatchOutcome.home},
        },
      );

      final recentMatches = s.recentMatchesByMatchday;
      expect(
        () => recentMatches[21] = [_makeMatch('m2')],
        throwsUnsupportedError,
      );
      expect(
        () => recentMatches[20]!.add(_makeMatch('m3')),
        throwsUnsupportedError,
      );

      final recentOutcomes = s.recentOutcomesByMatchday;
      expect(
        () => recentOutcomes[21] = {'m2': MatchOutcome.away},
        throwsUnsupportedError,
      );
      expect(
        () => recentOutcomes[20]!['m2'] = MatchOutcome.away,
        throwsUnsupportedError,
      );
    });

    test('pruneRecentMatchdayData keeps max 10 entries', () {
      final s = PredictionState.inMemory();
      final matches = <int, List<PredictionMatch>>{};
      for (var i = 1; i <= 15; i++) {
        matches[i] = [_makeMatch('m$i')];
      }
      s.setRecentMatchdayDataBulk(
        matchesByMatchday: matches,
        outcomesByMatchday: {},
      );

      // Should keep only the 10 most recent (highest day numbers)
      expect(s.recentMatchesByMatchday.length, 10);
      expect(s.recentMatchesByMatchday.containsKey(1), isFalse);
      expect(s.recentMatchesByMatchday.containsKey(6), isTrue);
      expect(s.recentMatchesByMatchday.containsKey(15), isTrue);
    });
  });

  // ==========================================================================
  // clearAllHistory
  // ==========================================================================
  group('PredictionState – clearAllHistory', () {
    test('clears all persisted data', () async {
      final s = PredictionState.inMemory();
      s.setCurrentUserPick('m1', PickOption.home);
      s.saveCurrentUserPicksHistory(
        dayNumber: 20,
        picksByMatchId: {'m1': PickOption.home},
      );
      s.saveOutcomesHistory(
        dayNumber: 20,
        outcomesByMatchId: {'m1': MatchOutcome.home},
      );
      s.setMemberPicksBulk({
        'alice': {'m1': PickOption.home},
      });

      var notified = 0;
      s.addListener(() => notified++);
      s.clearAllHistory();

      expect(s.currentUserPicksByMatchId, isEmpty);
      expect(s.currentUserPicksByMatchday, isEmpty);
      expect(s.outcomesByMatchday, isEmpty);
      expect(s.memberPicksByMemberId, isEmpty);
      expect(notified, 1);
    });
  });

  // ==========================================================================
  // Overwrite by day
  // ==========================================================================
  group('PredictionState – overwrite by day', () {
    test('saveCurrentUserPicksHistory for same day replaces previous', () {
      final s = PredictionState.inMemory();
      s.saveCurrentUserPicksHistory(
        dayNumber: 20,
        picksByMatchId: {'m1': PickOption.home},
      );
      s.saveCurrentUserPicksHistory(
        dayNumber: 20,
        picksByMatchId: {'m1': PickOption.draw, 'm2': PickOption.away},
      );
      expect(s.currentUserPicksForMatchday(20)['m1'], PickOption.draw);
      expect(s.currentUserPicksForMatchday(20)['m2'], PickOption.away);
    });

    test('saveOutcomesHistory for same day replaces previous', () {
      final s = PredictionState.inMemory();
      s.saveOutcomesHistory(
        dayNumber: 20,
        outcomesByMatchId: {'m1': MatchOutcome.home},
      );
      s.saveOutcomesHistory(
        dayNumber: 20,
        outcomesByMatchId: {'m1': MatchOutcome.draw},
      );
      expect(s.outcomesForMatchday(20)['m1'], MatchOutcome.draw);
    });
  });

  // ==========================================================================
  // clearAllHistory scope
  // ==========================================================================
  group('PredictionState – clearAllHistory scope', () {
    test('clears recent matchday data in addition to history', () {
      final s = PredictionState.inMemory();
      s.setRecentMatchdayDataBulk(
        matchesByMatchday: {
          20: [_makeMatch('m1')],
        },
        outcomesByMatchday: {
          20: {'m1': MatchOutcome.home},
        },
      );
      s.clearAllHistory();
      expect(s.recentMatchesByMatchday, isEmpty);
      expect(s.recentOutcomesByMatchday, isEmpty);
    });
  });

  // ==========================================================================
  // Merge-without-replace behavior
  // ==========================================================================
  group('PredictionState – merge without replace', () {
    test('setRecentMatchdayDataBulk without replace merges into existing', () {
      final s = PredictionState.inMemory();
      s.setRecentMatchdayDataBulk(
        matchesByMatchday: {
          20: [_makeMatch('m1')],
        },
        outcomesByMatchday: {
          20: {'m1': MatchOutcome.home},
        },
      );
      s.setRecentMatchdayDataBulk(
        matchesByMatchday: {
          21: [_makeMatch('m2')],
        },
        outcomesByMatchday: {
          21: {'m2': MatchOutcome.draw},
        },
      );
      expect(s.recentMatchesByMatchday.containsKey(20), isTrue);
      expect(s.recentMatchesByMatchday.containsKey(21), isTrue);
    });

    test('setMemberPicksBulk without replace merges into existing', () {
      final s = PredictionState.inMemory();
      s.setMemberPicksBulk({
        'alice': {'m1': PickOption.home},
      });
      s.setMemberPicksBulk({
        'bob': {'m1': PickOption.draw},
      });
      expect(s.memberPicksByMemberId.containsKey('alice'), isTrue);
      expect(s.memberPicksByMemberId['bob']!['m1'], PickOption.draw);
    });
  });

  // ==========================================================================
  // Snapshot edge cases
  // ==========================================================================
  group('PredictionState – snapshot edge cases', () {
    test('saveMatchdayMatchesSnapshot with empty list notifies but is not '
        'considered saved', () async {
      final s = PredictionState.inMemory();
      var notified = 0;
      s.addListener(() => notified++);

      await s.saveMatchdayMatchesSnapshot(matchdayNumber: 20, matches: []);

      // hasSavedMatchesForMatchday requires isNotEmpty, so empty ≡ missing
      expect(s.hasSavedMatchesForMatchday(20), isFalse);
      expect(s.savedMatchesForMatchday(20), isNull);
      expect(notified, 1);
    });
  });

  // ==========================================================================
  // FirestoreSerializers – PredictionMatch round-trip
  // ==========================================================================
  group('FirestoreSerializers – PredictionMatch round-trip', () {
    test('basic match without optional fields survives round-trip', () {
      final m = PredictionMatch(
        id: 'rt-1',
        homeTeam: 'TeamA',
        awayTeam: 'TeamB',
        kickoff: DateTime(2026, 3, 1, 20, 45),
        odds: _testOdds,
      );
      final map = FirestoreSerializers.predictionMatchToMap(m);
      final rt = FirestoreSerializers.predictionMatchFromMap(map);

      expect(rt.id, 'rt-1');
      expect(rt.odds.home, _testOdds.home);
      expect(rt.odds.draw, _testOdds.draw);
      expect(rt.odds.away, _testOdds.away);
      expect(rt.homeTeamLogo, isNull);
      expect(rt.homeGoals, isNull);
      expect(rt.statusShort, isNull);
      expect(rt.liveEvents, isEmpty);
    });

    test('logos, goals and statusShort survive round-trip', () {
      final m = PredictionMatch(
        id: 'rt-2',
        homeTeam: 'TeamC',
        awayTeam: 'TeamD',
        kickoff: DateTime(2026, 3, 2, 18, 0),
        homeTeamLogo: 'https://example.com/c.png',
        awayTeamLogo: 'https://example.com/d.png',
        homeGoals: 2,
        awayGoals: 1,
        statusShort: 'FT',
        odds: _testOdds,
      );
      final map = FirestoreSerializers.predictionMatchToMap(m);
      final rt = FirestoreSerializers.predictionMatchFromMap(map);

      expect(rt.homeTeamLogo, 'https://example.com/c.png');
      expect(rt.awayTeamLogo, 'https://example.com/d.png');
      expect(rt.homeGoals, 2);
      expect(rt.awayGoals, 1);
      expect(rt.statusShort, 'FT');
    });

    test('liveEvents survive round-trip', () {
      final m = PredictionMatch(
        id: 'rt-3',
        homeTeam: 'TeamE',
        awayTeam: 'TeamF',
        kickoff: DateTime(2026, 3, 3, 20, 0),
        odds: _testOdds,
        liveEvents: const [
          MatchLiveEvent(
            minute: 23,
            extraMinute: 5,
            type: 'Goal',
            detail: 'Normal Goal',
            teamName: 'TeamE',
            playerName: 'Player1',
            assistName: 'Player2',
          ),
        ],
      );
      final map = FirestoreSerializers.predictionMatchToMap(m);
      final rt = FirestoreSerializers.predictionMatchFromMap(map);

      expect(rt.liveEvents.length, 1);
      final ev = rt.liveEvents.first;
      expect(ev.minute, 23);
      expect(ev.extraMinute, 5);
      expect(ev.type, 'Goal');
      expect(ev.playerName, 'Player1');
      expect(ev.assistName, 'Player2');
    });
  });

  // ==========================================================================
  // Listener management
  // ==========================================================================
  group('PredictionState – listener management', () {
    test('multiple operations fire correct number of notifications', () {
      final s = PredictionState.inMemory();
      var count = 0;
      s.addListener(() => count++);

      s.setCurrentUserPick('m1', PickOption.home);
      s.setCurrentUserPick('m2', PickOption.away);
      s.clearCurrentUserPicks();

      expect(count, 3);
    });

    test('removing listener stops notifications', () {
      final s = PredictionState.inMemory();
      var count = 0;
      void listener() => count++;
      s.addListener(listener);

      s.setCurrentUserPick('m1', PickOption.home);
      expect(count, 1);

      s.removeListener(listener);
      s.setCurrentUserPick('m2', PickOption.away);
      expect(count, 1); // not incremented
    });
  });
}
