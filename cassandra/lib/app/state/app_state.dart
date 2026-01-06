import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'user_profile.dart';
import 'package:cassandra/features/predictions/models/prediction_match.dart';

class AppState extends ChangeNotifier {
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
    _cachedPredictionMatchesAreReal = isReal;
    _cachedPredictionMatchesUpdatedAt = updatedAt ?? DateTime.now();
    notifyListeners();
  }

  void clearCachedPredictionMatches() {
    _cachedPredictionMatches = null;
    _cachedPredictionMatchesAreReal = false;
    _cachedPredictionMatchesUpdatedAt = null;
    notifyListeners();
  }
}
