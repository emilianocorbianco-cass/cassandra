import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_profile.dart';

class AppState extends ChangeNotifier {
  // Chiavi SharedPreferences
  static const _kTeamName = 'profile.teamName';
  static const _kFavoriteTeam = 'profile.favoriteTeam';

  // Per ora fissiamo “chi sei” (senza auth): u6 = Emiliano
  // Quando faremo autenticazione, questo verrà dal backend/auth.
  static const UserProfile _defaultProfile = UserProfile(
    id: 'u6',
    displayName: 'Emiliano',
    teamName: 'FC Cassandra',
    favoriteTeam: 'Milan',
  );

  final SharedPreferences? _prefs;
  UserProfile _profile;

  AppState._(this._prefs, this._profile);

  UserProfile get profile => _profile;

  /// In UI usiamo sempre lo stesso seed, così il colore/avatar resta coerente.
  int get currentUserAvatarSeed => 66;

  static Future<AppState> load() async {
    final prefs = await SharedPreferences.getInstance();

    final storedTeamName = prefs.getString(_kTeamName);
    final storedFavorite = prefs.getString(_kFavoriteTeam);

    final profile = _defaultProfile.copyWith(
      teamName: storedTeamName ?? _defaultProfile.teamName,
      favoriteTeam: storedFavorite ?? _defaultProfile.favoriteTeam,
      clearFavoriteTeam: false,
    );

    return AppState._(prefs, profile);
  }

  /// Per test (niente SharedPreferences)
  factory AppState.inMemory({UserProfile? profile}) {
    return AppState._(null, profile ?? _defaultProfile);
  }

  Future<void> updateTeamName(String value) async {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return;

    _profile = _profile.copyWith(teamName: cleaned);
    notifyListeners();

    await _prefs?.setString(_kTeamName, cleaned);
  }

  Future<void> updateFavoriteTeam(String? value) async {
    final cleaned = value?.trim();
    final stored = (cleaned == null || cleaned.isEmpty) ? null : cleaned;

    _profile = _profile.copyWith(
      favoriteTeam: stored,
      clearFavoriteTeam: stored == null,
    );
    notifyListeners();

    final prefs = _prefs;
    if (prefs == null) return;

    if (stored == null) {
      await prefs.remove(_kFavoriteTeam);
    } else {
      await prefs.setString(_kFavoriteTeam, stored);
    }
  }

  Future<void> resetProfileToDefault() async {
    _profile = _defaultProfile;
    notifyListeners();

    final prefs = _prefs;
    if (prefs == null) return;

    await prefs.remove(_kTeamName);
    await prefs.remove(_kFavoriteTeam);
  }
}
