import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'user_profile.dart';
import '../../features/scoring/models/match_outcome.dart';
import 'dart:async';
import 'dart:convert';
import '../../features/predictions/models/pick_option.dart';
import 'dart:math';

import '../../features/predictions/models/prediction_match.dart';

import '../../domain/matchday/matchday_recovery_rules.dart';

class AppState extends ChangeNotifier {
  Map<String, MatchOutcome> cachedPredictionOutcomesByMatchId = {};
  // Chiavi "nuove" (più pulite)
  static const _kProfileTeamName = 'profile.teamName';
  static const _kProfileFavoriteTeam = 'profile.favoriteTeam';
  static const _kCurrentUserPicksByMatchday = 'picks.currentUser.byMatchday.v1';
  static const _kCassandraMatchdayCursorV1 = 'cassandra.matchday.cursor.v1';
  static const int _kCassandraDefaultMatchdayCursor = 20;
  static const _kPredictionOutcomesByMatchday = 'outcomes.byMatchday.v1';
  static const _kDemoSeedV1 = 'demo_seed.v1';
  static const _kFinalizedMatchdaysV1 = 'matchday.finalized.v1';
  static const _kCassandraMatchdayLastAutoBumpFromV1 =
      'cassandra.matchday.lastAutoBumpFrom.v1';
  static const _kOriginKickoffsByMatchIdV1 =
      'fixtures.originKickoffsByMatchId.v1';

  // Chiavi legacy (macro-step 1 precedente)
  static const _kTeamNameLegacy = 'teamName';
  static const _kFavoriteTeamLegacy = 'favoriteTeam';

  static const _kLanguage = 'language';
  static const _kDefaultVisibility = 'defaultVisibility';

  static const UserProfile _defaultProfile = UserProfile(
    id: 'u6',
    displayName: 'Emiliano',
    teamName: 'FC Cassandra',
    favoriteTeam: 'Milan',
  );

  final SharedPreferences? _prefs;

  int? _cassandraMatchdayCursor;

  /// Giornata “corrente” secondo Cassandra (ignorando recuperi di round vecchi).
  /// Persistita in SharedPreferences.
  int get cassandraMatchdayCursor => _cassandraMatchdayCursor ??=
      (_prefs?.getInt(_kCassandraMatchdayCursorV1) ??
      _kCassandraDefaultMatchdayCursor);

  Future<void> setCassandraMatchdayCursor(int dayNumber) async {
    if (dayNumber <= 0) return;
    _cassandraMatchdayCursor = dayNumber;
    await _prefs?.setInt(_kCassandraMatchdayCursorV1, dayNumber);

    _uiMatchdayNumber = null;
    notifyListeners();
  }

  Future<void> bumpCassandraMatchdayCursor() async {
    await setCassandraMatchdayCursor(cassandraMatchdayCursor + 1);
  }

  void ensureFinalizedMatchdaysLoaded() {
    if (_finalizedMatchdaysLoaded) return;
    _finalizedMatchdaysLoaded = true;

    final raw = _prefs?.getString(_kFinalizedMatchdaysV1);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final e in decoded) {
          final n = int.tryParse(e.toString());
          if (n != null && n > 0) _finalizedMatchdays.add(n);
        }
      }
    } catch (_) {
      // ignore corrupt storage
    }
  }

  bool isMatchdayFinalized(int matchdayNumber) {
    ensureFinalizedMatchdaysLoaded();
    return _finalizedMatchdays.contains(matchdayNumber);
  }

  Future<bool> markMatchdayFinalized(int matchdayNumber) async {
    if (matchdayNumber <= 0) return false;
    ensureFinalizedMatchdaysLoaded();
    if (_finalizedMatchdays.contains(matchdayNumber)) return false;

    _finalizedMatchdays.add(matchdayNumber);
    final list = _finalizedMatchdays.toList()..sort();
    await _prefs?.setString(_kFinalizedMatchdaysV1, jsonEncode(list));
    notifyListeners();
    return true;
  }

  /// Finalizza una matchday quando `finalDone` (e valida >= 6):
  /// - salva snapshot matches
  /// - salva matches/outcomes nello storico (per leaderboard stabile)
  ///
  /// Idempotente: se già finalizzata non fa nulla.
  Future<bool> maybeFinalizeMatchday({
    required int matchdayNumber,
    required List<PredictionMatch> matches,
    required Map<String, MatchOutcome> outcomesByMatchId,
  }) async {
    final didMark = await markMatchdayFinalized(matchdayNumber);
    if (!didMark) return false;

    ensureMatchdayMatchesLoaded();
    ensureMatchesHistoryLoaded();
    ensureOutcomesHistoryLoaded();

    await saveMatchdayMatchesSnapshot(
      matchdayNumber: matchdayNumber,
      matches: matches,
    );

    saveMatchesHistory(matchdayNumber: matchdayNumber, matches: matches);

    saveOutcomesHistory(
      dayNumber: matchdayNumber,
      outcomesByMatchId: outcomesByMatchId,
    );

    return true;
  }

  int? get lastAutoBumpFromMatchday =>
      _prefs?.getInt(_kCassandraMatchdayLastAutoBumpFromV1);

  Future<bool> maybeAutoBumpCassandraMatchdayCursor({
    required int fromMatchday,
  }) async {
    final prefs = _prefs;
    if (prefs == null) return false;

    final last = prefs.getInt(_kCassandraMatchdayLastAutoBumpFromV1) ?? -1;
    if (last == fromMatchday) return false;

    await prefs.setInt(_kCassandraMatchdayLastAutoBumpFromV1, fromMatchday);
    await setCassandraMatchdayCursor(fromMatchday + 1);
    return true;
  }

  void ensureOriginKickoffsLoaded() {
    if (_originKickoffsLoaded) return;
    _originKickoffsLoaded = true;
    final raw = _prefs?.getString(_kOriginKickoffsByMatchIdV1);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _originKickoffIsoByMatchId = {
          for (final e in decoded.entries) e.key.toString(): e.value.toString(),
        };
      }
    } catch (_) {
      // ignore: keep empty
    }
  }

  void registerOriginKickoff({
    required String matchId,
    required DateTime kickoff,
  }) {
    ensureOriginKickoffsLoaded();
    _originKickoffIsoByMatchId.putIfAbsent(
      matchId,
      () => kickoff.toUtc().toIso8601String(),
    );
  }

  DateTime originKickoffFor({
    required String matchId,
    required DateTime fallbackKickoff,
  }) {
    ensureOriginKickoffsLoaded();
    final iso = _originKickoffIsoByMatchId[matchId];
    if (iso == null) return fallbackKickoff;
    final parsed = DateTime.tryParse(iso);
    return parsed?.toLocal() ?? fallbackKickoff;
  }

  Future<void> persistOriginKickoffs() async {
    final prefs = _prefs;
    if (prefs == null) return;
    ensureOriginKickoffsLoaded();
    await prefs.setString(
      _kOriginKickoffsByMatchIdV1,
      jsonEncode(_originKickoffIsoByMatchId),
    );
  }

  UserProfile _profile;
  CassandraLanguage _language;
  PredictionVisibility _defaultVisibility;

  int _demoSeed;

  // ===== MATCHDAY FINALIZATION (finalDone) =====
  bool _finalizedMatchdaysLoaded = false;
  final Set<int> _finalizedMatchdays = <int>{};

  bool _originKickoffsLoaded = false;
  Map<String, String> _originKickoffIsoByMatchId = {};

  AppState._(
    this._prefs, {
    required UserProfile profile,
    required CassandraLanguage language,
    required PredictionVisibility defaultVisibility,
    int demoSeed = 0,
  }) : _profile = profile,
       _language = language,
       _defaultVisibility = defaultVisibility,
       _demoSeed = demoSeed;

  /// --- getters usati dal resto dell'app ---
  UserProfile get profile => _profile;

  /// comodo per alcune UI (compatibilità)
  String get teamName => _profile.teamName;
  String get favoriteTeam => _profile.favoriteTeam ?? '';

  CassandraLanguage get language => _language;
  PredictionVisibility get defaultVisibility => _defaultVisibility;

  int get demoSeed => _demoSeed;

  Locale? get localeOverride => localeForLanguage(_language);

  /// coerente con i mock: Emiliano ha seed 66
  int get currentUserAvatarSeed => 66;

  /// Caricamento persistente
  static Future<AppState> load() async {
    final prefs = await SharedPreferences.getInstance();

    // teamName: prova chiave nuova, poi legacy
    final storedTeamName =
        (prefs.getString(_kProfileTeamName) ??
                prefs.getString(_kTeamNameLegacy))
            ?.trim();

    // favoriteTeam: prova chiave nuova, poi legacy
    final storedFavorite =
        (prefs.getString(_kProfileFavoriteTeam) ??
                prefs.getString(_kFavoriteTeamLegacy))
            ?.trim();

    final profile = _defaultProfile.copyWith(
      teamName: (storedTeamName == null || storedTeamName.isEmpty)
          ? _defaultProfile.teamName
          : storedTeamName,
      favoriteTeam: (storedFavorite == null || storedFavorite.isEmpty)
          ? null
          : storedFavorite,
      clearFavoriteTeam: (storedFavorite == null || storedFavorite.isEmpty),
    );

    final language = cassandraLanguageFromStorage(prefs.getString(_kLanguage));
    final visibility = predictionVisibilityFromStorage(
      prefs.getString(_kDefaultVisibility),
    );
    final demoSeed = prefs.getInt(_kDemoSeedV1) ?? 0;

    return AppState._(
      prefs,
      profile: profile,
      language: language,
      defaultVisibility: visibility,
      demoSeed: demoSeed,
    );
  }

  /// In-memory (per i test)
  factory AppState.inMemory({
    UserProfile? profile,
    CassandraLanguage language = CassandraLanguage.system,
    PredictionVisibility defaultVisibility = PredictionVisibility.friends,
  }) {
    return AppState._(
      null,
      profile: profile ?? _defaultProfile,
      language: language,
      defaultVisibility: defaultVisibility,
      demoSeed: 0,
    );
  }

  Future<void> updateTeamName(String value) async {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return;
    if (cleaned == _profile.teamName) return;

    _profile = _profile.copyWith(teamName: cleaned);
    notifyListeners();

    await _prefs?.setString(_kProfileTeamName, cleaned);
    // scrivo anche la legacy per compatibilità
    await _prefs?.setString(_kTeamNameLegacy, cleaned);
  }

  Future<void> updateFavoriteTeam(String value) async {
    final cleaned = value.trim();
    final stored = cleaned.isEmpty ? null : cleaned;

    if (stored == _profile.favoriteTeam) return;

    _profile = _profile.copyWith(
      favoriteTeam: stored,
      clearFavoriteTeam: stored == null,
    );
    notifyListeners();

    if (_prefs == null) return;

    if (stored == null) {
      await _prefs.remove(_kProfileFavoriteTeam);
      await _prefs.remove(_kFavoriteTeamLegacy);
    } else {
      await _prefs.setString(_kProfileFavoriteTeam, stored);
      await _prefs.setString(_kFavoriteTeamLegacy, stored);
    }
  }

  Future<void> updateLanguage(CassandraLanguage value) async {
    if (value == _language) return;
    _language = value;
    notifyListeners();
    await _prefs?.setString(_kLanguage, cassandraLanguageToStorage(value));
  }

  Future<void> updateDefaultVisibility(PredictionVisibility value) async {
    if (value == _defaultVisibility) return;
    _defaultVisibility = value;
    notifyListeners();
    await _prefs?.setString(
      _kDefaultVisibility,
      predictionVisibilityToStorage(value),
    );
  }

  Future<void> resetAll() async {
    _profile = _defaultProfile;
    _language = CassandraLanguage.system;
    _defaultVisibility = PredictionVisibility.friends;
    notifyListeners();

    if (_prefs == null) return;

    await _prefs.remove(_kProfileTeamName);
    await _prefs.remove(_kProfileFavoriteTeam);

    await _prefs.remove(_kTeamNameLegacy);
    await _prefs.remove(_kFavoriteTeamLegacy);

    await _prefs.remove(_kLanguage);
    await _prefs.remove(_kDefaultVisibility);
  }

  // ===== Runtime cache (NON persistita) =====
  // Usata per condividere le fixture reali tra pagine (Pronostici, Gruppo, ecc.)
  // senza rifare fetch e senza scriverle su storage.

  List<PredictionMatch>? _cachedPredictionMatches;
  bool _cachedPredictionMatchesAreReal = false;
  DateTime? _cachedPredictionMatchesUpdatedAt;

  List<PredictionMatch>? get cachedPredictionMatches =>
      _cachedPredictionMatches;
  bool get cachedPredictionMatchesAreReal => _cachedPredictionMatchesAreReal;
  DateTime? get cachedPredictionMatchesUpdatedAt =>
      _cachedPredictionMatchesUpdatedAt;

  // ===== MatchdayProgress (runtime, non persistito) =====
  final Map<int, MatchdayProgress> _matchdayProgressByDay = {};

  int? _uiMatchdayNumber;
  int? _autoAdvancedFromMatchday;
  int get uiMatchdayNumber => _uiMatchdayNumber ?? cassandraMatchdayCursor;

  MatchdayProgress? matchdayProgressFor(int matchdayNumber) =>
      _matchdayProgressByDay[matchdayNumber];

  void setMatchdayProgress({
    required int matchdayNumber,
    required MatchdayProgress progress,
  }) {
    _matchdayProgressByDay[matchdayNumber] = progress;

    _uiMatchdayNumber = matchdayNumber;

    // AUTO-ADVANCE: primaryDone
    if (progress.primaryDone &&
        matchdayNumber == cassandraMatchdayCursor &&
        _autoAdvancedFromMatchday != matchdayNumber) {
      _autoAdvancedFromMatchday = matchdayNumber;
      Future.microtask(() async {
        try {
          await setCassandraMatchdayCursor(matchdayNumber + 1);
        } catch (_) {}
      });
    }

    notifyListeners();
  }

  void clearMatchdayProgress(int matchdayNumber) {
    if (_matchdayProgressByDay.remove(matchdayNumber) != null) {
      if (_uiMatchdayNumber == matchdayNumber) _uiMatchdayNumber = null;
      notifyListeners();
    }
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

  void clearAllPredictionCache() {
    _cachedPredictionMatches = null;
    _cachedPredictionMatchesAreReal = false;
    _cachedPredictionMatchesUpdatedAt = null;
    cachedPredictionOutcomesByMatchId = {};
    notifyListeners();
  }

  void setCachedPredictionOutcomesByMatchId(
    Map<String, MatchOutcome> outcomes,
  ) {
    cachedPredictionOutcomesByMatchId = Map.unmodifiable(outcomes);
    notifyListeners();
  }

  // ===== MATCHDAY RECENT (runtime, non persistito) =====
  // Serve per mostrare "pronostici passati" corretti anche quando il cursor
  // viene fast-forwardato (es. 20 -> 21) e per gestire recuperi (matchday parziale).
  final Map<int, List<PredictionMatch>> _recentMatchesByMatchday = {};
  final Map<int, Map<String, MatchOutcome>> _recentOutcomesByMatchday = {};

  Map<int, List<PredictionMatch>> get recentMatchesByMatchday =>
      _recentMatchesByMatchday;
  Map<int, Map<String, MatchOutcome>> get recentOutcomesByMatchday =>
      _recentOutcomesByMatchday;

  void setRecentMatchdayDataBulk({
    required Map<int, List<PredictionMatch>> matchesByMatchday,
    required Map<int, Map<String, MatchOutcome>> outcomesByMatchday,
  }) {
    _recentMatchesByMatchday
      ..clear()
      ..addAll({
        for (final e in matchesByMatchday.entries)
          e.key: List<PredictionMatch>.unmodifiable(e.value),
      });

    _recentOutcomesByMatchday
      ..clear()
      ..addAll({
        for (final e in outcomesByMatchday.entries)
          e.key: Map<String, MatchOutcome>.unmodifiable(e.value),
      });

    notifyListeners();
  }

  // ===== Pronostici utente (persistiti) =====
  static const String _kCurrentUserPicksByMatchIdV1 =
      'cassandra.current_user_picks_by_match_id_v1';
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
          if (pick != PickOption.none) {
            map[k] = pick;
          }
        } catch (_) {
          // ignore valori sconosciuti
        }
      }

      currentUserPicksByMatchId = Map.unmodifiable(map);
    } catch (_) {
      // ignore JSON rotto
    }
  }

  // ===== PICKS STORICO (per matchday) =====
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
          } catch (_) {
            // ignore unknown
          }
        }
        if (picks.isNotEmpty) _currentUserPicksByMatchday[day] = picks;
      }
    } catch (_) {
      // ignore corrupted prefs
    }
  }

  void saveCurrentUserPicksHistory({
    required int dayNumber,
    required Map<String, PickOption> picksByMatchId,
  }) {
    ensureCurrentUserPicksHistoryLoaded();

    // salva snapshot (copia)
    _currentUserPicksByMatchday[dayNumber] = Map<String, PickOption>.from(
      picksByMatchId,
    );

    // persist (string->string)
    final out = <String, Object?>{};
    for (final e in _currentUserPicksByMatchday.entries) {
      out[e.key.toString()] = {
        for (final p in e.value.entries) p.key: p.value.name,
      };
    }

    try {
      _prefs?.setString(_kCurrentUserPicksByMatchday, jsonEncode(out));
    } catch (_) {
      // ignore
    }

    notifyListeners();
  }

  void clearCurrentUserPicksHistory() {
    _currentUserPicksByMatchday.clear();
    try {
      _prefs?.remove(_kCurrentUserPicksByMatchday);
    } catch (_) {
      // ignore
    }

    notifyListeners();
  }

  // ===== OUTCOMES STORICO (per matchday) =====
  bool _outcomesHistoryLoaded = false;
  final Map<int, Map<String, MatchOutcome>> _outcomesByMatchday = {};

  // Snapshot match per giornata (storico stabile)
  Map<int, List<PredictionMatch>> _matchdayMatchesByDay = {};

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
            // ignore unknown
          }
        }
        if (outcomes.isNotEmpty) _outcomesByMatchday[day] = outcomes;
      }
    } catch (_) {
      // ignore corrupted prefs
    }
  }

  void saveOutcomesHistory({
    required int dayNumber,
    required Map<String, MatchOutcome> outcomesByMatchId,
  }) {
    ensureOutcomesHistoryLoaded();
    _outcomesByMatchday[dayNumber] = Map<String, MatchOutcome>.from(
      outcomesByMatchId,
    );

    final out = <String, Object?>{};
    for (final e in _outcomesByMatchday.entries) {
      out[e.key.toString()] = {
        for (final o in e.value.entries) o.key: o.value.name,
      };
    }

    try {
      _prefs?.setString(_kPredictionOutcomesByMatchday, jsonEncode(out));
    } catch (_) {
      // ignore
    }

    notifyListeners();
  }

  void clearOutcomesHistory() {
    _outcomesByMatchday.clear();
    try {
      _prefs?.remove(_kPredictionOutcomesByMatchday);
    } catch (_) {
      // ignore
    }
    notifyListeners();
  }

  // ===== MATCHES STORICO (per matchday) =====
  // Nota: per ora lo teniamo SOLO in-memory.
  // Per persisterlo su storage serve aggiungere serializzazione JSON a PredictionMatch (+ odds).
  final Map<int, List<PredictionMatch>> _matchesByMatchday = {};

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
    _matchesByMatchday[matchdayNumber] = List.unmodifiable(matches);
    notifyListeners();
  }

  Future<void> clearMatchesHistory() async {
    _matchesByMatchday.clear();
    notifyListeners();
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

  // ===== Picks membri simulati (persistiti in locale) =====
  static const String _kMemberPicksByMemberIdV1 =
      'cassandra.member_picks_by_member_id_v1';

  bool _memberPicksLoaded = false;

  /// Map: memberId -> (matchId -> pick)
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
            if (pick != PickOption.none) {
              inner[matchId] = pick;
            }
          } catch (_) {
            // ignore valori sconosciuti
          }
        }

        if (inner.isNotEmpty) {
          outer[memberId] = Map.unmodifiable(inner);
        }
      }

      memberPicksByMemberId = Map.unmodifiable(outer);
    } catch (_) {
      // ignore JSON rotto
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

  // ===== OUTCOMES SIMULATI (solo test, non persistiti) =====
  bool _useSimulatedOutcomes = false;
  Map<String, MatchOutcome>? _simulatedOutcomesByMatchId;

  bool get useSimulatedOutcomes => _useSimulatedOutcomes;

  Map<String, MatchOutcome>? get simulatedOutcomesByMatchId =>
      _simulatedOutcomesByMatchId;

  /// Outcomes usati dall'app: se la simulazione è ON usa quelli simulati,
  /// altrimenti usa la cache reale.
  Map<String, MatchOutcome> get effectivePredictionOutcomesByMatchId {
    final sim = _simulatedOutcomesByMatchId;
    if (_useSimulatedOutcomes && sim != null && sim.isNotEmpty) return sim;
    return cachedPredictionOutcomesByMatchId;
  }

  void setUseSimulatedOutcomes(bool value) {
    if (_useSimulatedOutcomes == value) return;
    _useSimulatedOutcomes = value;
    notifyListeners();
  }

  void clearSimulatedOutcomes() {
    _simulatedOutcomesByMatchId = null;
    _useSimulatedOutcomes = false;
    notifyListeners();
  }

  // ===== DEBUG =====
  // Simula risultati (tutti graded) per la matchday in cache: utile per testare leaderboard
  // ===== DEBUG =====
  // Crea outcomes simulati (tutti graded) per la matchday in cache: utile per testare leaderboard.
  // Non sovrascrive la cache reale: puoi fare ON/OFF e ripristinare in un click.
  void debugSimulateOutcomesForCachedMatches({
    int seed = 777,
    bool enable = true,
  }) {
    final matches = _cachedPredictionMatches;
    if (matches == null || matches.isEmpty) return;

    final rnd = Random(seed);
    const outs = [MatchOutcome.home, MatchOutcome.draw, MatchOutcome.away];

    final map = <String, MatchOutcome>{};
    for (final m in matches) {
      map[m.id] = outs[rnd.nextInt(outs.length)];
    }

    _simulatedOutcomesByMatchId = map;
    if (enable) _useSimulatedOutcomes = true;
    notifyListeners();
  }

  Future<void> bumpDemoSeed() async {
    _demoSeed = _demoSeed + 1;
    await _prefs?.setInt(_kDemoSeedV1, _demoSeed);
    notifyListeners();
  }

  void clearAllHistory() {
    ensureCurrentUserPicksLoaded();
    ensureCurrentUserPicksHistoryLoaded();
    ensureOutcomesHistoryLoaded();
    ensureMemberPicksLoaded();

    currentUserPicksByMatchId = const <String, PickOption>{};
    _currentUserPicksByMatchday.clear();
    _outcomesByMatchday.clear();
    memberPicksByMemberId = const <String, Map<String, PickOption>>{};

    _prefs?.remove(_kCurrentUserPicksByMatchIdV1);
    _prefs?.remove(_kCurrentUserPicksByMatchday);
    _prefs?.remove(_kPredictionOutcomesByMatchday);
    _prefs?.remove(_kMemberPicksByMemberIdV1);

    notifyListeners();
  }

  /// Ritorna i pick dell'utente per una giornata (se abbiamo uno snapshot salvato).
  /// Fallback: pick correnti (giornata live).
  Map<String, PickOption> picksForCurrentUserForMatchday(int matchdayNumber) {
    try {
      // Accesso "robusto": se il campo/getter non esiste, non rompiamo la build.
      final dynamic self = this;
      final byMatchday =
          self.currentUserPicksByMatchday as Map<int, Map<String, PickOption>>;
      final saved = byMatchday[matchdayNumber];
      if (saved != null) return saved;
    } catch (_) {}
    return currentUserPicksByMatchId;
  }

  static const String _kMatchdayMatchesByDayV1 = 'matchdayMatchesByDay.v1';

  Future<void> ensureMatchdayMatchesLoaded() async {
    if (_matchdayMatchesByDay.isNotEmpty) return;

    final prefs = _prefs!;
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

    final prefs = _prefs!;
    await prefs.setString(_kMatchdayMatchesByDayV1, jsonEncode(encoded));
    notifyListeners();
  }

  Map<String, dynamic> _predictionMatchToSnapshot(PredictionMatch m) {
    return {
      'id': m.id,
      'kickoff': m.kickoff.toIso8601String(),
      'home': m.homeTeam,
      'away': m.awayTeam,
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
    return PredictionMatch(
      id: j['id'] as String,
      kickoff: DateTime.parse(j['kickoff'] as String),
      homeTeam: j['home'] as String,
      awayTeam: j['away'] as String,
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
}
