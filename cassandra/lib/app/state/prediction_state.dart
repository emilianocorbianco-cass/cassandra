import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/predictions/models/pick_option.dart';
import '../../features/predictions/models/prediction_match.dart';
import '../../features/scoring/models/match_outcome.dart';
import '../../services/api_football/models/api_football_odds.dart';
import '../../services/api_football/models/api_football_standing.dart';
import '../../services/firestore/firestore_serializers.dart';
import '../config/storage_keys.dart';

/// Stato dei pronostici, estratto da AppState per isolamento e testabilità.
///
/// Gestisce: picks correnti, storico picks/outcomes/matches per matchday,
/// member picks, cache runtime (fixtures, outcomes, standings, odds),
/// recent matchday data.
class PredictionState extends ChangeNotifier {
  static const int _kMaxMatchdayHistoryEntries = 64;
  static const int _kMaxMemberPickEntries = 240;

  // ===== SharedPreferences keys =====
  static const _kCurrentUserPicksByMatchIdV1 =
      StorageKeys.currentUserPicksByMatchIdV1;
  static const _kCurrentUserPicksByMatchday =
      StorageKeys.currentUserPicksByMatchdayV1;
  static const _kPredictionOutcomesByMatchday =
      StorageKeys.predictionOutcomesByMatchdayV1;
  static const _kMemberPicksByMemberIdV1 = StorageKeys.memberPicksByMemberIdV1;
  static const _kMatchdayMatchesByDayV1 = StorageKeys.matchdayMatchesByDayV1;

  final SharedPreferences? _prefs;

  PredictionState._({required SharedPreferences? prefs}) : _prefs = prefs;

  /// Crea dallo storage persistente (usato da AppState.load).
  factory PredictionState.fromPrefs(SharedPreferences? prefs) {
    return PredictionState._(prefs: prefs);
  }

  /// In-memory (per i test).
  factory PredictionState.inMemory() {
    return PredictionState._(prefs: null);
  }

  // ======================================================================
  // CURRENT USER PICKS (live, giornata corrente)
  // ======================================================================

  bool _currentUserPicksLoaded = false;
  Map<String, PickOption> currentUserPicksByMatchId =
      const <String, PickOption>{};

  void ensureCurrentUserPicksLoaded() {
    if (_currentUserPicksLoaded) return;
    _currentUserPicksLoaded = true;

    final raw = _prefs?.getString(_kCurrentUserPicksByMatchIdV1);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final map = <String, PickOption>{};
      for (final entry in decoded.entries) {
        final k = entry.key;
        final v = entry.value;
        if (k is! String || v is! String) continue;
        try {
          final pick = PickOption.values.byName(v);
          if (pick != PickOption.none) map[k] = pick;
        } catch (_) {
          // Per-entry enum parse: unknown value skipped so one corrupt pick
          // does not discard the whole live-picks map. High-volume during
          // schema evolution; outer catch at line 78 logs structural errors.
        }
      }
      currentUserPicksByMatchId = Map.unmodifiable(map);
    } catch (e, st) {
      debugPrint('[picks] corrupt current-user picks in storage: $e\n$st');
    }
  }

  void setCurrentUserPick(String matchId, PickOption pick) {
    ensureCurrentUserPicksLoaded();

    final next = Map<String, PickOption>.of(currentUserPicksByMatchId);
    if (pick == PickOption.none) {
      next.remove(matchId);
    } else {
      next[matchId] = pick;
    }

    currentUserPicksByMatchId = Map.unmodifiable(next);
    notifyListeners();
    unawaited(_persistCurrentUserPicks());
  }

  void clearCurrentUserPicks() {
    _currentUserPicksLoaded = true;
    currentUserPicksByMatchId = const <String, PickOption>{};
    notifyListeners();
    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(prefs.remove(_kCurrentUserPicksByMatchIdV1));
  }

  Future<void> _persistCurrentUserPicks() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final map = <String, String>{
      for (final e in currentUserPicksByMatchId.entries) e.key: e.value.name,
    };
    await prefs.setString(_kCurrentUserPicksByMatchIdV1, jsonEncode(map));
  }

  // ======================================================================
  // PICKS HISTORY (per matchday)
  // ======================================================================

  bool _currentUserPicksHistoryLoaded = false;
  final Map<int, Map<String, PickOption>> _currentUserPicksByMatchday = {};

  Map<int, Map<String, PickOption>> get currentUserPicksByMatchday =>
      Map<int, Map<String, PickOption>>.unmodifiable(
        _currentUserPicksByMatchday.map(
          (day, picks) =>
              MapEntry(day, Map<String, PickOption>.unmodifiable(picks)),
        ),
      );

  bool hasSavedPicksForMatchday(int dayNumber) {
    final m = _currentUserPicksByMatchday[dayNumber];
    return m != null && m.isNotEmpty;
  }

  Map<String, PickOption> currentUserPicksForMatchday(int dayNumber) {
    final saved = _currentUserPicksByMatchday[dayNumber];
    if (saved == null) return const {};
    return Map<String, PickOption>.unmodifiable(saved);
  }

  void ensureCurrentUserPicksHistoryLoaded() {
    if (_currentUserPicksHistoryLoaded) return;
    _currentUserPicksHistoryLoaded = true;

    final raw = _prefs?.getString(_kCurrentUserPicksByMatchday);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      for (final entry in decoded.entries) {
        final day = int.tryParse(entry.key.toString());
        if (day == null) continue;
        final v = entry.value;
        if (v is! Map) continue;

        final picks = <String, PickOption>{};
        for (final e2 in v.entries) {
          final matchId = e2.key.toString();
          final s = e2.value;
          if (s is! String) continue;
          try {
            picks[matchId] = PickOption.values.byName(s);
          } catch (_) {
            // Per-entry enum parse: unknown value skipped so one corrupt pick
            // does not discard the whole matchday history entry.
          }
        }
        if (picks.isNotEmpty) {
          _currentUserPicksByMatchday[day] = Map.unmodifiable(picks);
        }
      }
    } catch (e, st) {
      debugPrint('[picks] corrupt picks-history in storage: $e\n$st');
    }
  }

  void saveCurrentUserPicksHistory({
    required int dayNumber,
    required Map<String, PickOption> picksByMatchId,
  }) {
    ensureCurrentUserPicksHistoryLoaded();
    _currentUserPicksByMatchday[dayNumber] =
        Map<String, PickOption>.unmodifiable(
          Map<String, PickOption>.from(picksByMatchId),
        );
    _pruneOldestByDay(_currentUserPicksByMatchday);
    _persistCurrentUserPicksHistoryToPrefs();
    notifyListeners();
  }

  void _persistCurrentUserPicksHistoryToPrefs() {
    final out = <String, Object?>{};
    for (final e in _currentUserPicksByMatchday.entries) {
      out[e.key.toString()] = {
        for (final p in e.value.entries) p.key: p.value.name,
      };
    }
    try {
      _prefs?.setString(_kCurrentUserPicksByMatchday, jsonEncode(out));
    } catch (e, st) {
      debugPrint('[picks] failed to persist picks-history: $e\n$st');
    }
  }

  void clearCurrentUserPicksHistory() {
    _currentUserPicksByMatchday.clear();
    try {
      _prefs?.remove(_kCurrentUserPicksByMatchday);
    } catch (e, st) {
      debugPrint('[picks] failed to remove picks-history: $e\n$st');
    }
    notifyListeners();
  }

  /// Clear picks for a single matchday (local only).
  void clearPicksForMatchday(int dayNumber) {
    _currentUserPicksByMatchday.remove(dayNumber);
    _persistCurrentUserPicksHistoryToPrefs();
    notifyListeners();
  }

  /// Ritorna i pick per una giornata: storico se disponibile, altrimenti live.
  Map<String, PickOption> picksForCurrentUserForMatchday(int matchdayNumber) {
    final saved = _currentUserPicksByMatchday[matchdayNumber];
    if (saved != null) return Map<String, PickOption>.unmodifiable(saved);
    return currentUserPicksByMatchId;
  }

  // ======================================================================
  // OUTCOMES HISTORY (per matchday)
  // ======================================================================

  bool _outcomesHistoryLoaded = false;
  Map<int, Map<String, MatchOutcome>> _outcomesByMatchday =
      const <int, Map<String, MatchOutcome>>{};

  Map<int, Map<String, MatchOutcome>> get outcomesByMatchday =>
      Map<int, Map<String, MatchOutcome>>.unmodifiable(
        _outcomesByMatchday.map(
          (day, outcomes) =>
              MapEntry(day, Map<String, MatchOutcome>.unmodifiable(outcomes)),
        ),
      );

  bool hasSavedOutcomesForMatchday(int dayNumber) {
    final m = _outcomesByMatchday[dayNumber];
    return m != null && m.isNotEmpty;
  }

  Map<String, MatchOutcome> outcomesForMatchday(int dayNumber) {
    final saved = _outcomesByMatchday[dayNumber];
    if (saved == null) return const {};
    return Map<String, MatchOutcome>.unmodifiable(saved);
  }

  void ensureOutcomesHistoryLoaded() {
    if (_outcomesHistoryLoaded) return;
    _outcomesHistoryLoaded = true;

    final raw = _prefs?.getString(_kPredictionOutcomesByMatchday);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final parsed = <int, Map<String, MatchOutcome>>{};
      for (final entry in decoded.entries) {
        final day = int.tryParse(entry.key.toString());
        if (day == null) continue;
        final v = entry.value;
        if (v is! Map) continue;

        final outcomes = <String, MatchOutcome>{};
        for (final e2 in v.entries) {
          final matchId = e2.key.toString();
          final s = e2.value;
          if (s is! String) continue;
          try {
            outcomes[matchId] = MatchOutcome.values.byName(s);
          } catch (_) {
            // Per-entry enum parse: unknown value skipped so one corrupt outcome
            // does not discard the whole matchday outcomes history entry.
          }
        }
        if (outcomes.isNotEmpty) {
          parsed[day] = Map<String, MatchOutcome>.unmodifiable(outcomes);
        }
      }
      _outcomesByMatchday = Map.unmodifiable(parsed);
    } catch (e, st) {
      debugPrint('[picks] corrupt outcomes-history in storage: $e\n$st');
    }
  }

  void saveOutcomesHistory({
    required int dayNumber,
    required Map<String, MatchOutcome> outcomesByMatchId,
  }) {
    ensureOutcomesHistoryLoaded();
    final next = Map<int, Map<String, MatchOutcome>>.of(_outcomesByMatchday);
    next[dayNumber] = Map<String, MatchOutcome>.unmodifiable(
      Map<String, MatchOutcome>.from(outcomesByMatchId),
    );
    _pruneOldestByDay(next);
    _outcomesByMatchday = Map.unmodifiable(next);

    final out = <String, Object?>{};
    for (final e in _outcomesByMatchday.entries) {
      out[e.key.toString()] = {
        for (final o in e.value.entries) o.key: o.value.name,
      };
    }
    try {
      _prefs?.setString(_kPredictionOutcomesByMatchday, jsonEncode(out));
    } catch (e, st) {
      debugPrint('[picks] failed to persist outcomes-history: $e\n$st');
    }
    notifyListeners();
  }

  void clearOutcomesHistory() {
    _outcomesByMatchday = const <int, Map<String, MatchOutcome>>{};
    try {
      _prefs?.remove(_kPredictionOutcomesByMatchday);
    } catch (e, st) {
      debugPrint('[picks] failed to remove outcomes-history: $e\n$st');
    }
    notifyListeners();
  }

  // ======================================================================
  // MATCHES HISTORY (per matchday, in-memory)
  // ======================================================================

  Map<int, List<PredictionMatch>> _matchesByMatchday =
      const <int, List<PredictionMatch>>{};

  Map<int, List<PredictionMatch>> get matchesByMatchday =>
      Map<int, List<PredictionMatch>>.unmodifiable(
        _matchesByMatchday.map(
          (day, matches) =>
              MapEntry(day, List<PredictionMatch>.unmodifiable(matches)),
        ),
      );

  List<PredictionMatch>? matchesForMatchday(int matchdayNumber) =>
      _matchesByMatchday[matchdayNumber] == null
      ? null
      : List<PredictionMatch>.unmodifiable(_matchesByMatchday[matchdayNumber]!);

  void ensureMatchesHistoryLoaded() {
    // no-op (in-memory only)
  }

  Future<void> saveMatchesHistory({
    required int matchdayNumber,
    required List<PredictionMatch> matches,
  }) async {
    final next = Map<int, List<PredictionMatch>>.of(_matchesByMatchday);
    next[matchdayNumber] = List<PredictionMatch>.unmodifiable(matches);
    _pruneOldestByDay(next);
    _matchesByMatchday = Map.unmodifiable(next);
    notifyListeners();
  }

  Future<void> clearMatchesHistory() async {
    _matchesByMatchday = const <int, List<PredictionMatch>>{};
    notifyListeners();
  }

  // ======================================================================
  // MATCHDAY MATCHES SNAPSHOTS (persistiti via JSON)
  // ======================================================================

  Map<int, List<PredictionMatch>> _matchdayMatchesByDay = {};

  Map<int, List<PredictionMatch>> get matchdayMatchesByDay =>
      Map<int, List<PredictionMatch>>.unmodifiable(
        _matchdayMatchesByDay.map(
          (day, matches) =>
              MapEntry(day, List<PredictionMatch>.unmodifiable(matches)),
        ),
      );

  Future<void> ensureMatchdayMatchesLoaded() async {
    if (_matchdayMatchesByDay.isNotEmpty) return;
    final prefs = _prefs;
    if (prefs == null) return;

    final raw = prefs.getString(_kMatchdayMatchesByDayV1);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = <int, List<PredictionMatch>>{};

      for (final e in decoded.entries) {
        final day = int.tryParse(e.key.toString());
        if (day == null) continue;
        final rawList = e.value;
        if (rawList is! List) continue;

        final matches = <PredictionMatch>[];
        for (final rawMatch in rawList) {
          if (rawMatch is! Map) continue;
          try {
            final json = Map<String, dynamic>.from(rawMatch);
            matches.add(FirestoreSerializers.predictionMatchFromMap(json));
          } catch (error, stackTrace) {
            debugPrint(
              '[picks] corrupt match snapshot for day $day, skipping entry: '
              '$error\n$stackTrace',
            );
          }
        }
        if (matches.isNotEmpty) {
          map[day] = List<PredictionMatch>.unmodifiable(matches);
        }
      }
      _pruneOldestByDay(map);
      _matchdayMatchesByDay = map;
    } catch (error, stackTrace) {
      debugPrint(
        '[picks] corrupt matchday-matches snapshots in storage: '
        '$error\n$stackTrace',
      );
    }
  }

  bool hasSavedMatchesForMatchday(int matchdayNumber) {
    return _matchdayMatchesByDay.containsKey(matchdayNumber) &&
        _matchdayMatchesByDay[matchdayNumber]!.isNotEmpty;
  }

  List<PredictionMatch>? savedMatchesForMatchday(int matchdayNumber) {
    final v = _matchdayMatchesByDay[matchdayNumber];
    if (v == null || v.isEmpty) return null;
    return List<PredictionMatch>.unmodifiable(v);
  }

  Future<void> saveMatchdayMatchesSnapshot({
    required int matchdayNumber,
    required List<PredictionMatch> matches,
  }) async {
    await ensureMatchdayMatchesLoaded();
    _matchdayMatchesByDay[matchdayNumber] = List<PredictionMatch>.of(matches);
    _pruneOldestByDay(_matchdayMatchesByDay);

    final encoded = <String, dynamic>{
      for (final e in _matchdayMatchesByDay.entries)
        e.key.toString(): e.value
            .map(FirestoreSerializers.predictionMatchToMap)
            .toList(),
    };
    final prefs = _prefs;
    if (prefs != null) {
      await prefs.setString(_kMatchdayMatchesByDayV1, jsonEncode(encoded));
    }
    notifyListeners();
  }

  // ======================================================================
  // MEMBER PICKS (simulati, persistiti in locale)
  // ======================================================================

  bool _memberPicksLoaded = false;
  Map<String, Map<String, PickOption>> memberPicksByMemberId =
      const <String, Map<String, PickOption>>{};

  void ensureMemberPicksLoaded() {
    if (_memberPicksLoaded) return;
    _memberPicksLoaded = true;

    final raw = _prefs?.getString(_kMemberPicksByMemberIdV1);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final outer = <String, Map<String, PickOption>>{};
      for (final outerEntry in decoded.entries) {
        final memberId = outerEntry.key;
        final v = outerEntry.value;
        if (memberId is! String || v is! Map) continue;

        final inner = <String, PickOption>{};
        for (final innerEntry in v.entries) {
          final matchId = innerEntry.key;
          final pickName = innerEntry.value;
          if (matchId is! String || pickName is! String) continue;
          try {
            final pick = PickOption.values.byName(pickName);
            if (pick != PickOption.none) inner[matchId] = pick;
          } catch (_) {
            // Per-entry enum parse: unknown value skipped so one corrupt pick
            // does not discard the whole member's pick map.
          }
        }
        if (inner.isNotEmpty) {
          outer[memberId] = Map.unmodifiable(inner);
        }
      }
      _pruneOldestMembers(outer);
      memberPicksByMemberId = Map.unmodifiable(outer);
    } catch (e, st) {
      debugPrint('[picks] corrupt member-picks in storage: $e\n$st');
    }
  }

  void setMemberPicksBulk(
    Map<String, Map<String, PickOption>> picksByMemberId, {
    bool replace = false,
  }) {
    ensureMemberPicksLoaded();

    final next = <String, Map<String, PickOption>>{
      if (!replace) ...memberPicksByMemberId,
    };

    for (final entry in picksByMemberId.entries) {
      final memberId = entry.key;
      final picks = entry.value;
      if (picks.isEmpty) {
        next.remove(memberId);
      } else {
        next[memberId] = Map.unmodifiable(Map<String, PickOption>.of(picks));
      }
    }

    _pruneOldestMembers(next);
    memberPicksByMemberId = Map.unmodifiable(next);
    notifyListeners();
    unawaited(_persistMemberPicks());
  }

  void clearMemberPicks({String? memberId}) {
    ensureMemberPicksLoaded();

    if (memberId == null) {
      memberPicksByMemberId = const <String, Map<String, PickOption>>{};
    } else {
      final next = Map<String, Map<String, PickOption>>.of(
        memberPicksByMemberId,
      );
      next.remove(memberId);
      memberPicksByMemberId = Map.unmodifiable(next);
    }

    notifyListeners();

    final prefs = _prefs;
    if (prefs == null) return;
    if (memberId == null) {
      unawaited(prefs.remove(_kMemberPicksByMemberIdV1));
    } else {
      unawaited(_persistMemberPicks());
    }
  }

  Future<void> _persistMemberPicks() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final outer = <String, Map<String, String>>{
      for (final outerEntry in memberPicksByMemberId.entries)
        outerEntry.key: {
          for (final innerEntry in outerEntry.value.entries)
            innerEntry.key: innerEntry.value.name,
        },
    };
    await prefs.setString(_kMemberPicksByMemberIdV1, jsonEncode(outer));
  }

  // ======================================================================
  // RUNTIME CACHE: Prediction matches, outcomes, standings, odds
  // ======================================================================

  Map<String, MatchOutcome> cachedPredictionOutcomesByMatchId = {};

  List<PredictionMatch>? _cachedPredictionMatches;
  bool _cachedPredictionMatchesAreReal = false;
  DateTime? _cachedPredictionMatchesUpdatedAt;

  Map<int, ApiFootballFixtureOdds>? _cachedRealOdds;
  List<ApiFootballStanding> _cachedSeasonStandings =
      const <ApiFootballStanding>[];
  DateTime? _cachedSeasonStandingsUpdatedAt;
  String _cachedSeasonStandingsSignature = '';

  // --- Getters ---

  List<PredictionMatch>? get cachedPredictionMatches =>
      _cachedPredictionMatches;
  bool get cachedPredictionMatchesAreReal => _cachedPredictionMatchesAreReal;
  DateTime? get cachedPredictionMatchesUpdatedAt =>
      _cachedPredictionMatchesUpdatedAt;
  Map<int, ApiFootballFixtureOdds>? get cachedRealOdds => _cachedRealOdds;
  List<ApiFootballStanding> get cachedSeasonStandings => _cachedSeasonStandings;
  DateTime? get cachedSeasonStandingsUpdatedAt =>
      _cachedSeasonStandingsUpdatedAt;

  Map<String, MatchOutcome> get effectivePredictionOutcomesByMatchId =>
      cachedPredictionOutcomesByMatchId;

  // --- Setters ---

  void setCachedRealOdds(Map<int, ApiFootballFixtureOdds> odds) {
    _cachedRealOdds = Map.unmodifiable(odds);
  }

  void setCachedPredictionMatches(
    List<PredictionMatch> matches, {
    required bool isReal,
    DateTime? updatedAt,
  }) {
    _cachedPredictionMatches = List.unmodifiable(matches);
    cachedPredictionOutcomesByMatchId = {};
    _cachedPredictionMatchesAreReal = isReal;
    _cachedPredictionMatchesUpdatedAt = updatedAt ?? DateTime.now();
    notifyListeners();
  }

  void clearCachedPredictionMatches() {
    _cachedPredictionMatches = null;
    cachedPredictionOutcomesByMatchId = {};
    _cachedPredictionMatchesAreReal = false;
    _cachedPredictionMatchesUpdatedAt = null;
    notifyListeners();
  }

  void clearCachedPredictionOutcomes() {
    cachedPredictionOutcomesByMatchId = {};
    notifyListeners();
  }

  void setCachedPredictionOutcomesByMatchId(
    Map<String, MatchOutcome> outcomes,
  ) {
    cachedPredictionOutcomesByMatchId = Map.unmodifiable(outcomes);
    notifyListeners();
  }

  String _standingsSignature(List<ApiFootballStanding> standings) {
    if (standings.isEmpty) return '';
    return standings
        .map((s) => '${s.rank}:${s.teamName}:${s.points}:${s.form ?? ''}')
        .join('|');
  }

  void setCachedSeasonStandings(
    List<ApiFootballStanding> standings, {
    DateTime? updatedAt,
  }) {
    final sig = _standingsSignature(standings);
    if (updatedAt == null && _cachedSeasonStandingsSignature == sig) return;

    final ts = updatedAt ?? DateTime.now();
    if (_cachedSeasonStandingsSignature == sig &&
        _cachedSeasonStandingsUpdatedAt == ts) {
      return;
    }

    _cachedSeasonStandings = List<ApiFootballStanding>.unmodifiable(standings);
    _cachedSeasonStandingsUpdatedAt = ts;
    _cachedSeasonStandingsSignature = sig;
    notifyListeners();
  }

  void clearAllPredictionCache() {
    _cachedPredictionMatches = null;
    _cachedPredictionMatchesAreReal = false;
    _cachedPredictionMatchesUpdatedAt = null;
    cachedPredictionOutcomesByMatchId = {};
    _cachedSeasonStandings = const <ApiFootballStanding>[];
    _cachedSeasonStandingsUpdatedAt = null;
    _cachedSeasonStandingsSignature = '';
    notifyListeners();
  }

  // ======================================================================
  // RECENT MATCHDAY DATA (runtime, non persistito)
  // ======================================================================

  Map<int, List<PredictionMatch>> _recentMatchesByMatchday =
      const <int, List<PredictionMatch>>{};
  Map<int, Map<String, MatchOutcome>> _recentOutcomesByMatchday =
      const <int, Map<String, MatchOutcome>>{};

  Map<int, List<PredictionMatch>> get recentMatchesByMatchday =>
      Map<int, List<PredictionMatch>>.unmodifiable(
        _recentMatchesByMatchday.map(
          (day, matches) =>
              MapEntry(day, List<PredictionMatch>.unmodifiable(matches)),
        ),
      );
  Map<int, Map<String, MatchOutcome>> get recentOutcomesByMatchday =>
      Map<int, Map<String, MatchOutcome>>.unmodifiable(
        _recentOutcomesByMatchday.map(
          (day, outcomes) =>
              MapEntry(day, Map<String, MatchOutcome>.unmodifiable(outcomes)),
        ),
      );

  void _pruneRecentMatchdayData({int maxEntries = 10}) {
    final allDays = <int>{
      ..._recentMatchesByMatchday.keys,
      ..._recentOutcomesByMatchday.keys,
    }.toList()..sort((a, b) => b.compareTo(a));
    if (allDays.length <= maxEntries) return;

    final keepDays = allDays.take(maxEntries).toSet();
    _recentMatchesByMatchday = Map.unmodifiable({
      for (final e in _recentMatchesByMatchday.entries)
        if (keepDays.contains(e.key)) e.key: e.value,
    });
    _recentOutcomesByMatchday = Map.unmodifiable({
      for (final e in _recentOutcomesByMatchday.entries)
        if (keepDays.contains(e.key)) e.key: e.value,
    });
  }

  void _pruneOldestByDay<T>(
    Map<int, T> map, {
    int maxEntries = _kMaxMatchdayHistoryEntries,
  }) {
    if (map.length <= maxEntries) return;
    final ordered = map.keys.toList()..sort((a, b) => a.compareTo(b));
    final removeCount = ordered.length - maxEntries;
    for (var i = 0; i < removeCount; i++) {
      map.remove(ordered[i]);
    }
  }

  void _pruneOldestMembers(
    Map<String, Map<String, PickOption>> map, {
    int maxEntries = _kMaxMemberPickEntries,
  }) {
    if (map.length <= maxEntries) return;
    final removeCount = map.length - maxEntries;
    final keys = map.keys.take(removeCount).toList(growable: false);
    for (final key in keys) {
      map.remove(key);
    }
  }

  void setRecentMatchdayDataBulk({
    required Map<int, List<PredictionMatch>> matchesByMatchday,
    required Map<int, Map<String, MatchOutcome>> outcomesByMatchday,
    bool replace = false,
  }) {
    var nextMatches = replace
        ? <int, List<PredictionMatch>>{}
        : Map<int, List<PredictionMatch>>.of(_recentMatchesByMatchday);
    var nextOutcomes = replace
        ? <int, Map<String, MatchOutcome>>{}
        : Map<int, Map<String, MatchOutcome>>.of(_recentOutcomesByMatchday);

    if (replace) {
      nextMatches = <int, List<PredictionMatch>>{};
      nextOutcomes = <int, Map<String, MatchOutcome>>{};
    }

    for (final e in matchesByMatchday.entries) {
      nextMatches[e.key] = List<PredictionMatch>.unmodifiable(e.value);
    }
    for (final e in outcomesByMatchday.entries) {
      nextOutcomes[e.key] = Map<String, MatchOutcome>.unmodifiable(e.value);
    }
    _recentMatchesByMatchday = Map.unmodifiable(nextMatches);
    _recentOutcomesByMatchday = Map.unmodifiable(nextOutcomes);
    _pruneRecentMatchdayData();
    notifyListeners();
  }

  // ======================================================================
  // CLEAR ALL
  // ======================================================================

  void clearAllHistory() {
    ensureCurrentUserPicksLoaded();
    ensureCurrentUserPicksHistoryLoaded();
    ensureOutcomesHistoryLoaded();
    ensureMemberPicksLoaded();

    currentUserPicksByMatchId = const <String, PickOption>{};
    _currentUserPicksByMatchday.clear();
    _outcomesByMatchday = const <int, Map<String, MatchOutcome>>{};
    _matchesByMatchday = const <int, List<PredictionMatch>>{};
    _recentMatchesByMatchday = const <int, List<PredictionMatch>>{};
    _recentOutcomesByMatchday = const <int, Map<String, MatchOutcome>>{};
    memberPicksByMemberId = const <String, Map<String, PickOption>>{};

    _prefs?.remove(_kCurrentUserPicksByMatchIdV1);
    _prefs?.remove(_kCurrentUserPicksByMatchday);
    _prefs?.remove(_kPredictionOutcomesByMatchday);
    _prefs?.remove(_kMemberPicksByMemberIdV1);

    notifyListeners();
  }

  @override
  void dispose() {
    currentUserPicksByMatchId = const <String, PickOption>{};
    _currentUserPicksByMatchday.clear();
    _outcomesByMatchday = const <int, Map<String, MatchOutcome>>{};
    _matchesByMatchday = const <int, List<PredictionMatch>>{};
    _matchdayMatchesByDay.clear();
    memberPicksByMemberId = const <String, Map<String, PickOption>>{};
    _cachedPredictionMatches = null;
    _cachedPredictionMatchesAreReal = false;
    _cachedPredictionMatchesUpdatedAt = null;
    cachedPredictionOutcomesByMatchId = const <String, MatchOutcome>{};
    _cachedRealOdds = null;
    _cachedSeasonStandings = const <ApiFootballStanding>[];
    _cachedSeasonStandingsUpdatedAt = null;
    _cachedSeasonStandingsSignature = '';
    _recentMatchesByMatchday = const <int, List<PredictionMatch>>{};
    _recentOutcomesByMatchday = const <int, Map<String, MatchOutcome>>{};
    super.dispose();
  }
}
