import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'user_profile.dart';
import 'package:cassandra/features/predictions/models/prediction_match.dart';
import '../../features/scoring/models/match_outcome.dart';
import 'dart:async';
import 'dart:convert';
import '../../features/predictions/models/pick_option.dart';
import 'dart:math';

class AppState extends ChangeNotifier {
  Map<String, MatchOutcome> cachedPredictionOutcomesByMatchId = {};
  // Chiavi "nuove" (più pulite)
  static const _kProfileTeamName = 'profile.teamName';
  static const _kProfileFavoriteTeam = 'profile.favoriteTeam';

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

  UserProfile _profile;
  CassandraLanguage _language;
  PredictionVisibility _defaultVisibility;

  AppState._(
    this._prefs, {
    required UserProfile profile,
    required CassandraLanguage language,
    required PredictionVisibility defaultVisibility,
  }) : _profile = profile,
       _language = language,
       _defaultVisibility = defaultVisibility;

  /// --- getters usati dal resto dell'app ---
  UserProfile get profile => _profile;

  /// comodo per alcune UI (compatibilità)
  String get teamName => _profile.teamName;
  String get favoriteTeam => _profile.favoriteTeam ?? '';

  CassandraLanguage get language => _language;
  PredictionVisibility get defaultVisibility => _defaultVisibility;

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

    return AppState._(
      prefs,
      profile: profile,
      language: language,
      defaultVisibility: visibility,
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

  // ===== DEBUG =====
  // Simula risultati (tutti graded) per la matchday in cache: utile per testare leaderboard
  void debugSimulateOutcomesForCachedMatches({int seed = 777}) {
    final matches = _cachedPredictionMatches;
    if (matches == null || matches.isEmpty) return;

    final rnd = Random(seed);
    const outs = [MatchOutcome.home, MatchOutcome.draw, MatchOutcome.away];

    final map = <String, MatchOutcome>{};
    for (final m in matches) {
      map[m.id] = outs[rnd.nextInt(outs.length)];
    }

    cachedPredictionOutcomesByMatchId = map;
    notifyListeners();
  }
}
