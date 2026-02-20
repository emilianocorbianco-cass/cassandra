import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/predictions/models/pick_option.dart';
import '../../features/predictions/models/prediction_match.dart';
import '../../features/scoring/models/match_outcome.dart';
import '../../services/api_football/models/api_football_odds.dart';
import '../../services/api_football/models/api_football_standing.dart';
import '../../domain/serie_a/team_name_normalizer.dart';

/// Stato dei pronostici, estratto da AppState per isolamento e testabilità.
///
/// Gestisce: picks correnti, storico picks/outcomes/matches per matchday,
/// member picks, cache runtime (fixtures, outcomes, standings, odds),
/// recent matchday data.
class PredictionState extends ChangeNotifier {
  // ===== SharedPreferences keys =====
  static const _kCurrentUserPicksByMatchIdV1 =
      'cassandra.current_user_picks_by_match_id_v1';
  static const _kCurrentUserPicksByMatchday = 'picks.currentUser.byMatchday.v1';
  static const _kPredictionOutcomesByMatchday = 'outcomes.byMatchday.v1';
  static const _kMemberPicksByMemberIdV1 =
      'cassandra.member_picks_by_member_id_v1';
  static const _kMatchdayMatchesByDayV1 = 'matchdayMatchesByDay.v1';

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
        } catch (_) {}
      }
      currentUserPicksByMatchId = Map.unmodifiable(map);
    } catch (_) {}
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
      _currentUserPicksByMatchday;

  bool hasSavedPicksForMatchday(int dayNumber) {
    final m = _currentUserPicksByMatchday[dayNumber];
    return m != null && m.isNotEmpty;
  }

  Map<String, PickOption> currentUserPicksForMatchday(int dayNumber) {
    return _currentUserPicksByMatchday[dayNumber] ?? const {};
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
          } catch (_) {}
        }
        if (picks.isNotEmpty) _currentUserPicksByMatchday[day] = picks;
      }
    } catch (_) {}
  }

  void saveCurrentUserPicksHistory({
    required int dayNumber,
    required Map<String, PickOption> picksByMatchId,
  }) {
    ensureCurrentUserPicksHistoryLoaded();
    _currentUserPicksByMatchday[dayNumber] = Map<String, PickOption>.from(
      picksByMatchId,
    );
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
    } catch (_) {}
  }

  void clearCurrentUserPicksHistory() {
    _currentUserPicksByMatchday.clear();
    try {
      _prefs?.remove(_kCurrentUserPicksByMatchday);
    } catch (_) {}
    notifyListeners();
  }

  /// Ritorna i pick per una giornata: storico se disponibile, altrimenti live.
  Map<String, PickOption> picksForCurrentUserForMatchday(int matchdayNumber) {
    final saved = _currentUserPicksByMatchday[matchdayNumber];
    if (saved != null) return saved;
    return currentUserPicksByMatchId;
  }

  // ======================================================================
  // OUTCOMES HISTORY (per matchday)
  // ======================================================================

  bool _outcomesHistoryLoaded = false;
  Map<int, Map<String, MatchOutcome>> _outcomesByMatchday =
      const <int, Map<String, MatchOutcome>>{};

  Map<int, Map<String, MatchOutcome>> get outcomesByMatchday =>
      _outcomesByMatchday;

  bool hasSavedOutcomesForMatchday(int dayNumber) {
    final m = _outcomesByMatchday[dayNumber];
    return m != null && m.isNotEmpty;
  }

  Map<String, MatchOutcome> outcomesForMatchday(int dayNumber) {
    return _outcomesByMatchday[dayNumber] ?? const {};
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
          } catch (_) {}
        }
        if (outcomes.isNotEmpty) {
          parsed[day] = Map<String, MatchOutcome>.unmodifiable(outcomes);
        }
      }
      _outcomesByMatchday = Map.unmodifiable(parsed);
    } catch (_) {}
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
    _outcomesByMatchday = Map.unmodifiable(next);

    final out = <String, Object?>{};
    for (final e in _outcomesByMatchday.entries) {
      out[e.key.toString()] = {
        for (final o in e.value.entries) o.key: o.value.name,
      };
    }
    try {
      _prefs?.setString(_kPredictionOutcomesByMatchday, jsonEncode(out));
    } catch (_) {}
    notifyListeners();
  }

  void clearOutcomesHistory() {
    _outcomesByMatchday = const <int, Map<String, MatchOutcome>>{};
    try {
      _prefs?.remove(_kPredictionOutcomesByMatchday);
    } catch (_) {}
    notifyListeners();
  }

  // ======================================================================
  // MATCHES HISTORY (per matchday, in-memory)
  // ======================================================================

  Map<int, List<PredictionMatch>> _matchesByMatchday =
      const <int, List<PredictionMatch>>{};

  Map<int, List<PredictionMatch>> get matchesByMatchday => _matchesByMatchday;

  List<PredictionMatch>? matchesForMatchday(int matchdayNumber) =>
      _matchesByMatchday[matchdayNumber];

  void ensureMatchesHistoryLoaded() {
    // no-op (in-memory only)
  }

  Future<void> saveMatchesHistory({
    required int matchdayNumber,
    required List<PredictionMatch> matches,
  }) async {
    final next = Map<int, List<PredictionMatch>>.of(_matchesByMatchday);
    next[matchdayNumber] = List<PredictionMatch>.unmodifiable(matches);
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
      _matchdayMatchesByDay;

  Future<void> ensureMatchdayMatchesLoaded() async {
    if (_matchdayMatchesByDay.isNotEmpty) return;
    final prefs = _prefs;
    if (prefs == null) return;

    final raw = prefs.getString(_kMatchdayMatchesByDayV1);
    if (raw == null || raw.isEmpty) return;

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final map = <int, List<PredictionMatch>>{};

    for (final e in decoded.entries) {
      final day = int.tryParse(e.key);
      if (day == null) continue;
      final list = (e.value as List).cast<Map<String, dynamic>>();
      map[day] = list.map(_predictionMatchFromSnapshot).toList();
    }
    _matchdayMatchesByDay = map;
  }

  bool hasSavedMatchesForMatchday(int matchdayNumber) {
    return _matchdayMatchesByDay.containsKey(matchdayNumber) &&
        _matchdayMatchesByDay[matchdayNumber]!.isNotEmpty;
  }

  List<PredictionMatch>? savedMatchesForMatchday(int matchdayNumber) {
    final v = _matchdayMatchesByDay[matchdayNumber];
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> saveMatchdayMatchesSnapshot({
    required int matchdayNumber,
    required List<PredictionMatch> matches,
  }) async {
    await ensureMatchdayMatchesLoaded();
    _matchdayMatchesByDay[matchdayNumber] = List<PredictionMatch>.of(matches);

    final encoded = <String, dynamic>{
      for (final e in _matchdayMatchesByDay.entries)
        e.key.toString(): e.value.map(_predictionMatchToSnapshot).toList(),
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
          } catch (_) {}
        }
        if (inner.isNotEmpty) {
          outer[memberId] = Map.unmodifiable(inner);
        }
      }
      memberPicksByMemberId = Map.unmodifiable(outer);
    } catch (_) {}
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
      _recentMatchesByMatchday;
  Map<int, Map<String, MatchOutcome>> get recentOutcomesByMatchday =>
      _recentOutcomesByMatchday;

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

  // ======================================================================
  // SNAPSHOT SERIALIZATION (PredictionMatch <-> JSON)
  // ======================================================================

  Map<String, dynamic> _predictionMatchToSnapshot(PredictionMatch m) {
    return {
      'id': m.id,
      'kickoff': m.kickoff.toIso8601String(),
      'home': normalizeSerieATeamName(m.homeTeam),
      'away': normalizeSerieATeamName(m.awayTeam),
      if (m.homeTeamLogo != null) 'homeLogo': m.homeTeamLogo,
      if (m.awayTeamLogo != null) 'awayLogo': m.awayTeamLogo,
      if (m.homeGoals != null) 'homeGoals': m.homeGoals,
      if (m.awayGoals != null) 'awayGoals': m.awayGoals,
      if (m.statusShort != null && m.statusShort!.isNotEmpty)
        'statusShort': m.statusShort,
      if (m.liveEvents.isNotEmpty)
        'events': m.liveEvents
            .map(
              (e) => {
                'minute': e.minute,
                if (e.extraMinute != null) 'extraMinute': e.extraMinute,
                'type': e.type,
                if (e.detail != null && e.detail!.isNotEmpty)
                  'detail': e.detail,
                if (e.teamName != null && e.teamName!.isNotEmpty)
                  'teamName': e.teamName,
                if (e.playerName != null && e.playerName!.isNotEmpty)
                  'playerName': e.playerName,
                if (e.assistName != null && e.assistName!.isNotEmpty)
                  'assistName': e.assistName,
              },
            )
            .toList(),
      'odds': {
        'home': m.odds.home,
        'draw': m.odds.draw,
        'away': m.odds.away,
        'homeDraw': m.odds.homeDraw,
        'drawAway': m.odds.drawAway,
        'homeAway': m.odds.homeAway,
      },
    };
  }

  PredictionMatch _predictionMatchFromSnapshot(Map<String, dynamic> j) {
    final odds = j['odds'] as Map<String, dynamic>;
    final rawStatus = j['statusShort']?.toString().trim();
    final rawEvents = (j['events'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
    return PredictionMatch(
      id: j['id'] as String,
      kickoff: DateTime.parse(j['kickoff'] as String).toLocal(),
      homeTeam: normalizeSerieATeamName(j['home'] as String),
      awayTeam: normalizeSerieATeamName(j['away'] as String),
      homeTeamLogo: j['homeLogo'] as String?,
      awayTeamLogo: j['awayLogo'] as String?,
      homeGoals: _asNullableInt(j['homeGoals']),
      awayGoals: _asNullableInt(j['awayGoals']),
      statusShort: (rawStatus == null || rawStatus.isEmpty) ? null : rawStatus,
      liveEvents: rawEvents
          .map(
            (e) => MatchLiveEvent(
              minute: _asNullableInt(e['minute']) ?? 0,
              extraMinute: _asNullableInt(e['extraMinute']),
              type: e['type']?.toString() ?? 'unknown',
              detail: e['detail']?.toString(),
              teamName: e['teamName']?.toString(),
              playerName: e['playerName']?.toString(),
              assistName: e['assistName']?.toString(),
            ),
          )
          .toList(growable: false),
      odds: Odds(
        home: (odds['home'] as num).toDouble(),
        draw: (odds['draw'] as num).toDouble(),
        away: (odds['away'] as num).toDouble(),
        homeDraw: (odds['homeDraw'] as num).toDouble(),
        drawAway: (odds['drawAway'] as num).toDouble(),
        homeAway: (odds['homeAway'] as num).toDouble(),
      ),
    );
  }

  int? _asNullableInt(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }
}
