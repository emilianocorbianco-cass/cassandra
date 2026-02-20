import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'group_state.dart';
import 'matchday_state.dart';
import 'prediction_state.dart';
import 'user_profile.dart';
import '../../features/group/models/group_member.dart';
import '../../features/scoring/models/match_outcome.dart';
import '../../features/scoring/models/score_breakdown.dart';
import '../../features/scoring/scoring_engine.dart';
import '../../services/firestore/models/group_document.dart';
import '../../services/firestore/models/picks_document.dart';
import '../../services/auth/auth_service.dart';
import '../../services/firestore/firestore_service.dart';
import 'dart:async';
import 'dart:convert';
import '../../features/predictions/models/pick_option.dart';

import '../../features/predictions/models/prediction_match.dart';
import '../../services/api_football/models/api_football_odds.dart';
import '../../services/api_football/models/api_football_standing.dart';

import '../../domain/matchday/matchday_recovery_rules.dart';

class AppState extends ChangeNotifier {
  static String _normalizeHandle(String raw, {String fallback = '@cassandra'}) {
    final compact = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty || compact == '@') return fallback;
    final body = compact.startsWith('@') ? compact.substring(1) : compact;
    if (body.isEmpty) return fallback;
    return '@$body';
  }

  // Chiavi "nuove" (più pulite)
  static const _kProfileTeamName = 'profile.teamName';
  static const _kProfileFavoriteTeam = 'profile.favoriteTeam';
  static const _kDemoSeedV1 = 'demo_seed.v1';

  // Chiavi legacy (macro-step 1 precedente)
  static const _kTeamNameLegacy = 'teamName';
  static const _kFavoriteTeamLegacy = 'favoriteTeam';

  static const _kProfileId = 'profile.id.v1';
  static const _kProfileDisplayName = 'profile.displayName.v1';
  static const _kProfileEmail = 'profile.email.v1';
  static const _kProfilePhotoUrl = 'profile.photoUrl.v1';
  static const _kRememberMeEnabled = 'auth.rememberMe.enabled.v1';
  static const _kRememberedUid = 'auth.remembered.uid.v1';
  static const _kRememberedHandle = 'auth.remembered.handle.v1';
  static const _kRememberedPhotoUrl = 'auth.remembered.photoUrl.v1';
  static const _kRememberedProvider = 'auth.remembered.provider.v1';
  static const _kDevicePushToken = 'push.deviceToken.v1';

  static const _kLanguage = 'language';
  static const _kDefaultVisibility = 'defaultVisibility';

  static const UserProfile _defaultProfile = UserProfile(
    id: '',
    displayName: '',
    teamName: '',
  );

  final SharedPreferences? _prefs;

  AuthService? _authService;
  FirestoreService? _firestoreService;

  AuthService? get authService => _authService;
  FirestoreService? get firestoreService => _firestoreService;

  void setAuthService(AuthService service) {
    _authService = service;
  }

  void setFirestoreService(FirestoreService service) {
    _firestoreService = service;
  }

  /// Merge profilo letto da Firestore con stato locale.
  /// Usato all'avvio per ripristinare dati da cloud su device nuovo.
  void mergeFirestoreProfile(Map<String, dynamic> data) {
    bool changed = false;

    final remoteDisplayName = data['displayName'] as String?;
    if (remoteDisplayName != null &&
        remoteDisplayName.trim().isNotEmpty &&
        remoteDisplayName != _profile.displayName) {
      _profile = _profile.copyWith(displayName: remoteDisplayName.trim());
      _prefs?.setString(_kProfileDisplayName, remoteDisplayName.trim());
      changed = true;
    }

    final remoteTeamName = data['teamName'] as String?;
    if (remoteTeamName != null &&
        remoteTeamName.trim().isNotEmpty &&
        _profile.teamName == _defaultProfile.teamName &&
        remoteTeamName != _profile.teamName) {
      final normalizedRemote = _normalizeHandle(remoteTeamName);
      _profile = _profile.copyWith(teamName: normalizedRemote);
      _prefs?.setString(_kProfileTeamName, normalizedRemote);
      changed = true;
    }

    final remoteFavoriteTeam = data['favoriteTeam'] as String?;
    if (remoteFavoriteTeam != null &&
        remoteFavoriteTeam.isNotEmpty &&
        _profile.favoriteTeam == null) {
      _profile = _profile.copyWith(favoriteTeam: remoteFavoriteTeam);
      _prefs?.setString(_kProfileFavoriteTeam, remoteFavoriteTeam);
      changed = true;
    }

    final remotePhotoUrl = data['photoUrl'] as String?;
    if (remotePhotoUrl != null &&
        remotePhotoUrl.trim().isNotEmpty &&
        _profile.photoUrl != remotePhotoUrl.trim()) {
      _profile = _profile.copyWith(photoUrl: remotePhotoUrl.trim());
      _prefs?.setString(_kProfilePhotoUrl, remotePhotoUrl.trim());
      changed = true;
    }

    final remoteLang = data['language'] as String?;
    if (remoteLang != null) {
      final parsed = cassandraLanguageFromStorage(remoteLang);
      if (parsed != _language) {
        _language = parsed;
        _prefs?.setString(_kLanguage, remoteLang);
        changed = true;
      }
    }

    final remoteVis = data['defaultVisibility'] as String?;
    if (remoteVis != null) {
      final parsed = predictionVisibilityFromStorage(remoteVis);
      if (parsed != _defaultVisibility) {
        _defaultVisibility = parsed;
        _prefs?.setString(_kDefaultVisibility, remoteVis);
        changed = true;
      }
    }

    // Restore groupIds for multi-group support
    final remoteGroupIds = (data['groupIds'] as List<dynamic>?)
        ?.cast<String>()
        .toList();
    if (remoteGroupIds != null) {
      groupState.setFirestoreGroupIds(remoteGroupIds);
      changed = true;
    }

    if (changed) notifyListeners();

    if ((remoteGroupIds?.isNotEmpty ?? false) &&
        (groupState.groupName == null || groupState.groupInviteCode == null)) {
      unawaited(refreshActiveGroupMetadataFromFirestore().catchError((_) {}));
    }
  }

  // ===== GROUP STATE (delegated) =====
  late final GroupState groupState;

  // ===== PREDICTION STATE (delegated) =====
  late final PredictionState predictionState;

  // ===== MATCHDAY STATE (delegated) =====
  late final MatchdayState matchdayState;

  // Forwarding getters per compatibilità con codice esistente.
  List<String> get firestoreGroupIds => groupState.firestoreGroupIds;

  /// Fire-and-forget: sync full user profile to Firestore.
  void _syncProfileToFirestore() {
    final fs = _firestoreService;
    if (fs == null || !isAuthenticated) return;
    final uid = _profile.id;
    if (uid.isEmpty) return;
    unawaited(
      fs
          .setUserProfile(
            uid: uid,
            profile: _profile,
            language: _language,
            defaultVisibility: _defaultVisibility,
            avatarSeed: currentUserAvatarSeed,
          )
          .catchError((_) {}),
    );
    if (groupState.firestoreGroupIds.isNotEmpty) {
      unawaited(
        fs
            .updateGroupMemberProfileInGroups(
              uid: uid,
              groupIds: groupState.firestoreGroupIds,
              displayName: _profile.displayName,
              teamName: _profile.teamName,
              avatarSeed: currentUserAvatarSeed,
              favoriteTeam: _profile.favoriteTeam,
              photoUrl: _profile.photoUrl,
            )
            .catchError((_) {}),
      );
    }
  }

  Future<void> hydrateProfileFromFirestore([String? uid]) async {
    final fs = _firestoreService;
    final targetUid = uid ?? _profile.id;
    if (fs == null || targetUid.isEmpty) return;

    try {
      final data = await fs.getUserProfile(targetUid);
      if (data != null) {
        mergeFirestoreProfile(data);
      }
      if (groupState.firestoreGroupIds.isEmpty) {
        final recoveredGroupIds = await fs.findGroupIdsForMember(targetUid);
        if (recoveredGroupIds.isNotEmpty) {
          groupState.setFirestoreGroupIds(recoveredGroupIds);
          await fs.mergeUserField(targetUid, {'groupIds': recoveredGroupIds});
          notifyListeners();
        }
      }
      await refreshActiveGroupMetadataFromFirestore();
    } catch (_) {
      // ignore: best-effort hydration
    }
  }

  Future<void> refreshActiveGroupMetadataFromFirestore() async {
    await groupState.refreshActiveGroupMetadataFromFirestore(
      isAuthenticated: isAuthenticated,
      firestoreService: _firestoreService,
    );
  }

  /// Fire-and-forget: sync a single field to Firestore.
  void _syncFieldToFirestore(Map<String, dynamic> fields) {
    final fs = _firestoreService;
    if (fs == null || !isAuthenticated) return;
    final uid = _profile.id;
    if (uid.isEmpty) return;
    unawaited(fs.updateUserField(uid, fields).catchError((_) {}));
  }

  bool get isAuthenticated => _authService?.isSignedIn ?? false;

  /// Serie A season key: agosto-maggio → anno di inizio.
  String get currentSeasonKey {
    final now = DateTime.now();
    return (now.month >= 8 ? now.year : now.year - 1).toString();
  }

  /// Finalizza una matchday quando `finalDone` (e valida >= 6):
  /// - salva snapshot matches
  /// - salva matches/outcomes nello storico (per leaderboard stabile)
  ///
  /// Idempotente: se già finalizzata non fa nulla.
  /// Cross-cutting: coordina MatchdayState e PredictionState.
  Future<bool> maybeFinalizeMatchday({
    required int matchdayNumber,
    required List<PredictionMatch> matches,
    required Map<String, MatchOutcome> outcomesByMatchId,
  }) async {
    final didMark = await matchdayState.markMatchdayFinalized(matchdayNumber);
    if (!didMark) return false;

    ensureMatchdayMatchesLoaded();
    ensureMatchesHistoryLoaded();
    ensureOutcomesHistoryLoaded();

    await saveMatchdayMatchesSnapshot(
      matchdayNumber: matchdayNumber,
      matches: matches,
    );

    await saveMatchesHistory(matchdayNumber: matchdayNumber, matches: matches);

    saveOutcomesHistory(
      dayNumber: matchdayNumber,
      outcomesByMatchId: outcomesByMatchId,
    );

    return true;
  }

  UserProfile _profile;
  CassandraLanguage _language;
  PredictionVisibility _defaultVisibility;
  bool _rememberMeEnabled = false;
  bool _currentUserProfileSetupCompleted = false;
  String? _rememberedUid;
  String? _rememberedHandle;
  String? _rememberedPhotoUrl;
  String? _rememberedProvider;
  String? _devicePushToken;

  int _demoSeed;

  // ===== GRUPPO (delegated to GroupState) =====

  String? get groupName => groupState.groupName;
  String? get groupInviteCode => groupState.groupInviteCode;
  String? get groupImagePath => groupState.groupImagePath;
  bool get groupAdminApproval => groupState.groupAdminApproval;
  bool get hasGroup => groupState.hasGroup;
  String? get activeGroupId => groupState.activeGroupId;

  void setActiveGroupId(String? id) => groupState.setActiveGroupId(id);

  Future<void> updateGroupImagePath(String? path) =>
      groupState.updateGroupImagePath(path);

  Future<void> updateGroupAdminApproval(bool value) =>
      groupState.updateGroupAdminApproval(value);

  Future<String?> createGroup(String name) => groupState.createGroup(
    name: name,
    uid: _profile.id,
    isAuthenticated: isAuthenticated,
    profile: _profile,
    avatarSeed: currentUserAvatarSeed,
    firestoreService: _firestoreService,
  );

  Future<String?> joinGroupByInviteCode(String code) =>
      groupState.joinGroupByInviteCode(
        code: code,
        uid: _profile.id,
        isAuthenticated: isAuthenticated,
        profile: _profile,
        avatarSeed: currentUserAvatarSeed,
        firestoreService: _firestoreService,
      );

  Future<void> leaveFirestoreGroup(String groupId) =>
      groupState.leaveFirestoreGroup(
        groupId: groupId,
        uid: _profile.id,
        isAuthenticated: isAuthenticated,
        firestoreService: _firestoreService,
      );

  Future<String?> deleteActiveGroupIfAdmin() =>
      groupState.deleteActiveGroupIfAdmin(
        uid: _profile.id,
        isAuthenticated: isAuthenticated,
        firestoreService: _firestoreService,
      );

  Future<void> updateGroupName(String name) => groupState.updateGroupName(name);

  AppState._(
    this._prefs, {
    required UserProfile profile,
    required CassandraLanguage language,
    required PredictionVisibility defaultVisibility,
    required GroupState groupStateInstance,
    required PredictionState predictionStateInstance,
    required MatchdayState matchdayStateInstance,
    int demoSeed = 0,
  }) : _profile = profile,
       _language = language,
       _defaultVisibility = defaultVisibility,
       _demoSeed = demoSeed {
    groupState = groupStateInstance;
    predictionState = predictionStateInstance;
    matchdayState = matchdayStateInstance;
    // Propaga notifiche da sub-states -> AppState listeners.
    groupState.addListener(notifyListeners);
    predictionState.addListener(notifyListeners);
    matchdayState.addListener(notifyListeners);
  }

  /// --- getters usati dal resto dell'app ---
  UserProfile get profile => _profile;

  /// comodo per alcune UI (compatibilità)
  String get teamName => _profile.teamName;
  String get favoriteTeam => _profile.favoriteTeam ?? '';

  CassandraLanguage get language => _language;
  PredictionVisibility get defaultVisibility => _defaultVisibility;
  bool get rememberMeEnabled => _rememberMeEnabled;
  bool get hasCompletedProfileSetup => _currentUserProfileSetupCompleted;
  bool get needsProfileSetup =>
      isAuthenticated && !_currentUserProfileSetupCompleted;
  String? get rememberedUid => _rememberedUid;
  String? get rememberedAuthProvider => _rememberedProvider;
  bool get hasRememberedIdentity =>
      _rememberMeEnabled && (_rememberedUid?.trim().isNotEmpty ?? false);
  String get rememberedHandle =>
      (_rememberedHandle ?? _profile.teamName).trim();
  String? get rememberedPhotoUrl => _rememberedPhotoUrl ?? _profile.photoUrl;
  String? get devicePushToken => _devicePushToken;

  int get demoSeed => _demoSeed;

  Locale? get localeOverride => localeForLanguage(_language);

  /// coerente con i mock: Emiliano ha seed 66
  int get currentUserAvatarSeed => 66;

  static String _profileSetupCompletedKeyForUid(String uid) =>
      'auth.profileSetupCompleted.$uid.v1';

  bool _readProfileSetupCompletedForUid(String uid) {
    final prefs = _prefs;
    if (prefs == null || uid.trim().isEmpty) return false;
    return prefs.getBool(_profileSetupCompletedKeyForUid(uid.trim())) ?? false;
  }

  Future<void> _writeProfileSetupCompletedForUid(String uid, bool value) async {
    final prefs = _prefs;
    if (prefs == null || uid.trim().isEmpty) return;
    await prefs.setBool(_profileSetupCompletedKeyForUid(uid.trim()), value);
  }

  Future<void> _syncRememberedIdentityFromProfile() async {
    if (!_rememberMeEnabled) return;
    final uid = _profile.id.trim();
    if (uid.isEmpty) return;

    _rememberedUid = uid;
    _rememberedHandle = _profile.teamName.trim();
    _rememberedPhotoUrl = _profile.photoUrl?.trim();
    await _prefs?.setString(_kRememberedUid, uid);
    await _prefs?.setString(_kRememberedHandle, _rememberedHandle!);
    if (_rememberedProvider != null && _rememberedProvider!.isNotEmpty) {
      await _prefs?.setString(_kRememberedProvider, _rememberedProvider!);
    } else {
      await _prefs?.remove(_kRememberedProvider);
    }
    if (_rememberedPhotoUrl != null && _rememberedPhotoUrl!.isNotEmpty) {
      await _prefs?.setString(_kRememberedPhotoUrl, _rememberedPhotoUrl!);
    } else {
      await _prefs?.remove(_kRememberedPhotoUrl);
    }
  }

  String? _normalizeRememberedProvider(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value == 'google') return 'google';
    if (value == 'apple') return 'apple';
    return null;
  }

  Future<void> setRememberedAuthProvider(String? provider) async {
    final normalized = _normalizeRememberedProvider(provider);
    if (normalized == _rememberedProvider) return;
    _rememberedProvider = normalized;

    if (_rememberMeEnabled) {
      if (normalized == null) {
        await _prefs?.remove(_kRememberedProvider);
      } else {
        await _prefs?.setString(_kRememberedProvider, normalized);
      }
    }
    notifyListeners();
  }

  Future<void> forgetRememberedIdentity() async {
    _rememberMeEnabled = false;
    _rememberedUid = null;
    _rememberedHandle = null;
    _rememberedPhotoUrl = null;
    _rememberedProvider = null;
    await _prefs?.setBool(_kRememberMeEnabled, false);
    await _prefs?.remove(_kRememberedUid);
    await _prefs?.remove(_kRememberedHandle);
    await _prefs?.remove(_kRememberedPhotoUrl);
    await _prefs?.remove(_kRememberedProvider);
    notifyListeners();
  }

  Future<void> setRememberMeEnabled(bool enabled) async {
    if (_rememberMeEnabled == enabled) return;
    _rememberMeEnabled = enabled;
    await _prefs?.setBool(_kRememberMeEnabled, enabled);
    if (enabled) {
      await _syncRememberedIdentityFromProfile();
    } else {
      _rememberedUid = null;
      _rememberedHandle = null;
      _rememberedPhotoUrl = null;
      _rememberedProvider = null;
      await _prefs?.remove(_kRememberedUid);
      await _prefs?.remove(_kRememberedHandle);
      await _prefs?.remove(_kRememberedPhotoUrl);
      await _prefs?.remove(_kRememberedProvider);
    }
    notifyListeners();
  }

  Future<void> completeProfileSetup({required bool rememberMe}) async {
    if (_profile.id.trim().isEmpty) return;
    _currentUserProfileSetupCompleted = true;
    await _writeProfileSetupCompletedForUid(_profile.id, true);
    await setRememberMeEnabled(rememberMe);
    notifyListeners();
  }

  /// Caricamento persistente
  static Future<AppState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedId = (prefs.getString(_kProfileId) ?? '').trim();
    final storedDisplayName = (prefs.getString(_kProfileDisplayName) ?? '')
        .trim();
    final storedEmail = (prefs.getString(_kProfileEmail) ?? '').trim();
    final storedPhotoUrl = (prefs.getString(_kProfilePhotoUrl) ?? '').trim();

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
      id: storedId,
      displayName: storedDisplayName.isEmpty
          ? _defaultProfile.displayName
          : storedDisplayName,
      teamName: (storedTeamName == null || storedTeamName.isEmpty)
          ? _defaultProfile.teamName
          : _normalizeHandle(storedTeamName),
      favoriteTeam: (storedFavorite == null || storedFavorite.isEmpty)
          ? null
          : storedFavorite,
      clearFavoriteTeam: (storedFavorite == null || storedFavorite.isEmpty),
      email: storedEmail.isEmpty ? null : storedEmail,
      clearEmail: storedEmail.isEmpty,
      photoUrl: storedPhotoUrl.isEmpty ? null : storedPhotoUrl,
      clearPhotoUrl: storedPhotoUrl.isEmpty,
    );

    final language = cassandraLanguageFromStorage(prefs.getString(_kLanguage));
    final visibility = predictionVisibilityFromStorage(
      prefs.getString(_kDefaultVisibility),
    );
    final demoSeed = prefs.getInt(_kDemoSeedV1) ?? 0;

    final groupStateInstance = GroupState.fromPrefs(prefs);
    final predictionStateInstance = PredictionState.fromPrefs(prefs);
    final matchdayStateInstance = MatchdayState.fromPrefs(prefs);
    final rememberMeEnabled = prefs.getBool(_kRememberMeEnabled) ?? false;
    final rememberedUid = (prefs.getString(_kRememberedUid) ?? '').trim();
    final rememberedHandle = (prefs.getString(_kRememberedHandle) ?? '').trim();
    final rememberedPhotoUrl = (prefs.getString(_kRememberedPhotoUrl) ?? '')
        .trim();
    final rememberedProvider = (prefs.getString(_kRememberedProvider) ?? '')
        .trim()
        .toLowerCase();
    final storedPushToken = (prefs.getString(_kDevicePushToken) ?? '').trim();
    final profileSetupCompleted = storedId.isNotEmpty
        ? (prefs.getBool(_profileSetupCompletedKeyForUid(storedId)) ?? false)
        : false;

    return AppState._(
        prefs,
        profile: profile,
        language: language,
        defaultVisibility: visibility,
        groupStateInstance: groupStateInstance,
        predictionStateInstance: predictionStateInstance,
        matchdayStateInstance: matchdayStateInstance,
        demoSeed: demoSeed,
      )
      .._rememberMeEnabled = rememberMeEnabled
      .._rememberedUid = rememberedUid.isEmpty ? null : rememberedUid
      .._rememberedHandle = rememberedHandle.isEmpty ? null : rememberedHandle
      .._rememberedPhotoUrl = rememberedPhotoUrl.isEmpty
          ? null
          : rememberedPhotoUrl
      .._rememberedProvider =
          (rememberedProvider == 'google' || rememberedProvider == 'apple')
          ? rememberedProvider
          : null
      .._devicePushToken = storedPushToken.isEmpty ? null : storedPushToken
      .._currentUserProfileSetupCompleted = profileSetupCompleted;
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
      groupStateInstance: GroupState.inMemory(),
      predictionStateInstance: PredictionState.inMemory(),
      matchdayStateInstance: MatchdayState.inMemory(),
      demoSeed: 0,
    );
  }

  Future<void> updateTeamName(String value) async {
    final normalized = _normalizeHandle(value);
    if (normalized == _profile.teamName) return;

    _profile = _profile.copyWith(teamName: normalized);
    notifyListeners();

    await _prefs?.setString(_kProfileTeamName, normalized);
    // scrivo anche la legacy per compatibilità
    await _prefs?.setString(_kTeamNameLegacy, normalized);
    await _syncRememberedIdentityFromProfile();
    _syncFieldToFirestore({'teamName': normalized});
  }

  Future<void> updateDisplayName(String value) async {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return;
    if (cleaned == _profile.displayName) return;

    _profile = _profile.copyWith(displayName: cleaned);
    notifyListeners();

    await _prefs?.setString(_kProfileDisplayName, cleaned);
    await _syncRememberedIdentityFromProfile();
    _syncFieldToFirestore({'displayName': cleaned});
  }

  Future<void> updateProfilePhotoPath(String? path) async {
    final cleaned = (path ?? '').trim();
    final next = cleaned.isEmpty ? null : cleaned;
    if (next == _profile.photoUrl) return;

    _profile = _profile.copyWith(photoUrl: next, clearPhotoUrl: next == null);
    notifyListeners();

    if (next == null) {
      await _prefs?.remove(_kProfilePhotoUrl);
      _syncFieldToFirestore({'photoUrl': null});
      return;
    }

    await _prefs?.setString(_kProfilePhotoUrl, next);
    await _syncRememberedIdentityFromProfile();
    // Sync solo URL web; i path locali non sono portabili cross-device.
    if (next.startsWith('http://') || next.startsWith('https://')) {
      _syncFieldToFirestore({'photoUrl': next});
    }
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
    _syncFieldToFirestore({'favoriteTeam': stored});
  }

  Future<void> updateLanguage(CassandraLanguage value) async {
    if (value == _language) return;
    _language = value;
    notifyListeners();
    await _prefs?.setString(_kLanguage, cassandraLanguageToStorage(value));
    _syncFieldToFirestore({'language': cassandraLanguageToStorage(value)});
  }

  Future<void> updateDefaultVisibility(PredictionVisibility value) async {
    if (value == _defaultVisibility) return;
    _defaultVisibility = value;
    notifyListeners();
    await _prefs?.setString(
      _kDefaultVisibility,
      predictionVisibilityToStorage(value),
    );
    _syncFieldToFirestore({
      'defaultVisibility': predictionVisibilityToStorage(value),
    });
  }

  Future<void> setDevicePushToken(String token) async {
    final cleaned = token.trim();
    if (cleaned.isEmpty || cleaned == _devicePushToken) return;

    final previous = _devicePushToken;
    _devicePushToken = cleaned;
    await _prefs?.setString(_kDevicePushToken, cleaned);

    final fs = _firestoreService;
    final uid = _profile.id.trim();
    if (fs == null || !isAuthenticated || uid.isEmpty) return;

    try {
      if (previous != null && previous.isNotEmpty && previous != cleaned) {
        await fs.removeUserFcmToken(uid: uid, token: previous);
      }
      await fs.addUserFcmToken(uid: uid, token: cleaned);
    } catch (_) {
      // ignore: best-effort sync
    }
  }

  void setProfileFromFirebaseUser(User user) {
    final existingTeamName =
        _prefs?.getString(_kProfileTeamName) ??
        _prefs?.getString(_kTeamNameLegacy);
    final existingFavoriteTeam =
        _prefs?.getString(_kProfileFavoriteTeam) ??
        _prefs?.getString(_kFavoriteTeamLegacy);
    final existingPhotoUrlRaw =
        _prefs?.getString(_kProfilePhotoUrl) ?? _profile.photoUrl;
    final existingPhotoUrl = (existingPhotoUrlRaw ?? '').trim();

    _profile = UserProfile.fromFirebaseUser(
      user,
      existingTeamName: existingTeamName,
      existingFavoriteTeam: existingFavoriteTeam,
      existingPhotoUrl: existingPhotoUrl.isEmpty ? null : existingPhotoUrl,
    );
    _currentUserProfileSetupCompleted = _readProfileSetupCompletedForUid(
      user.uid,
    );

    _prefs?.setString(_kProfileId, user.uid);
    _prefs?.setString(_kProfileDisplayName, _profile.displayName);
    if (_profile.email != null) {
      _prefs?.setString(_kProfileEmail, _profile.email!);
    }
    if (_profile.photoUrl != null) {
      _prefs?.setString(_kProfilePhotoUrl, _profile.photoUrl!);
    }

    if (_rememberMeEnabled) {
      unawaited(_syncRememberedIdentityFromProfile());
    }

    _syncProfileToFirestore();
    unawaited(hydrateCurrentUserHistoryFromFirestore().catchError((_) {}));
    final token = _devicePushToken;
    if (token != null && token.trim().isNotEmpty) {
      unawaited(
        _firestoreService
            ?.addUserFcmToken(uid: user.uid, token: token)
            .catchError((_) {}),
      );
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    final token = _devicePushToken;
    final uid = _profile.id.trim();
    final fs = _firestoreService;
    if (token != null && token.isNotEmpty && uid.isNotEmpty && fs != null) {
      try {
        await fs.removeUserFcmToken(uid: uid, token: token);
      } catch (_) {
        // ignore: best effort
      }
    }

    await _authService?.signOut();
    await forgetRememberedIdentity();

    _prefs?.remove(_kProfileId);
    _prefs?.remove(_kProfileDisplayName);
    _prefs?.remove(_kProfileEmail);
    _prefs?.remove(_kProfilePhotoUrl);

    _profile = _defaultProfile;
    _currentUserProfileSetupCompleted = false;
    await groupState.clearAll();
    predictionState.clearAllHistory();
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    final token = _devicePushToken;
    final uid = _profile.id.trim();
    final fs = _firestoreService;
    if (token != null && token.isNotEmpty && uid.isNotEmpty && fs != null) {
      try {
        await fs.removeUserFcmToken(uid: uid, token: token);
      } catch (_) {
        // ignore: best effort
      }
    }

    await _authService?.deleteAccount();
    await forgetRememberedIdentity();

    _prefs?.remove(_kProfileId);
    _prefs?.remove(_kProfileDisplayName);
    _prefs?.remove(_kProfileEmail);
    _prefs?.remove(_kProfilePhotoUrl);

    await groupState.clearAll();

    await resetAll();
    notifyListeners();
  }

  Future<void> resetAll() async {
    _profile = _defaultProfile;
    _language = CassandraLanguage.system;
    _defaultVisibility = PredictionVisibility.friends;
    await groupState.clearAll();
    predictionState.clearAllHistory();
    _rememberMeEnabled = false;
    _currentUserProfileSetupCompleted = false;
    _rememberedUid = null;
    _rememberedHandle = null;
    _rememberedPhotoUrl = null;
    _rememberedProvider = null;
    notifyListeners();

    if (_prefs == null) return;

    await _prefs.remove(_kProfileTeamName);
    await _prefs.remove(_kProfileFavoriteTeam);

    await _prefs.remove(_kTeamNameLegacy);
    await _prefs.remove(_kFavoriteTeamLegacy);

    await _prefs.remove(_kLanguage);
    await _prefs.remove(_kDefaultVisibility);

    await _prefs.remove(_kRememberMeEnabled);
    await _prefs.remove(_kRememberedUid);
    await _prefs.remove(_kRememberedHandle);
    await _prefs.remove(_kRememberedPhotoUrl);
    await _prefs.remove(_kRememberedProvider);
  }

  bool _hydratingCurrentUserHistoryFromFirestore = false;
  String? _hydratedCurrentUserHistoryKey;

  /// Fire-and-forget: upload picks per questa giornata su Firestore.
  void submitPicksToFirestore({
    required int dayNumber,
    required Map<String, PickOption> picksByMatchId,
    required String visibility,
    DayScoreBreakdown? score,
  }) {
    final fs = _firestoreService;
    if (fs == null || !isAuthenticated) return;
    unawaited(
      fs
          .savePicks(
            uid: _profile.id,
            seasonKey: currentSeasonKey,
            dayNumber: dayNumber,
            picksByMatchId: picksByMatchId,
            visibility: visibility,
            score: score,
          )
          .catchError((_) {}),
    );
  }

  // ===== FIRESTORE GROUP LEADERBOARD =====

  /// Fetch group members from Firestore for active group.
  Future<List<GroupMember>> fetchFirestoreGroupMembers() =>
      groupState.fetchFirestoreGroupMembers(
        isAuthenticated: isAuthenticated,
        firestoreService: _firestoreService,
      );

  /// Fetch picks from Firestore for a list of UIDs + matchday.
  /// Returns map: uid -> picksByMatchId.
  Future<Map<String, Map<String, PickOption>>> fetchFirestorePicksForMatchday({
    required int dayNumber,
    required List<String> uids,
  }) async {
    final fs = _firestoreService;
    if (fs == null || !isAuthenticated) return {};

    DateTime? lockTime;
    try {
      final md = await fs.getMatchdayData(
        seasonKey: currentSeasonKey,
        dayNumber: dayNumber,
      );
      lockTime = md?.lockTime;
    } catch (_) {
      lockTime = null;
    }

    final docs = await fs.getPicksForMatchday(
      seasonKey: currentSeasonKey,
      dayNumber: dayNumber,
      uids: uids,
    );

    final revealAtOrAfterLock =
        lockTime != null && !DateTime.now().isBefore(lockTime);
    final requesterUid = _profile.id;

    return {
      for (final d in docs)
        d.uid: () {
          if (d.uid == requesterUid) return d.picksByMatchId;

          final visibility = d.visibility.toLowerCase().trim();
          if (visibility == 'public') {
            // "Invia e mostra": visibile subito.
            return d.picksByMatchId;
          }

          // "Invia senza mostrare" (e fallback legacy): visibile solo dopo lock.
          final hiddenUntilLock =
              visibility == 'private' ||
              visibility == 'friends' ||
              visibility.isEmpty;
          if (hiddenUntilLock && revealAtOrAfterLock) {
            return d.picksByMatchId;
          }

          return const <String, PickOption>{};
        }(),
    };
  }

  /// Fetch active group metadata from Firestore.
  Future<GroupDocument?> fetchActiveGroupDocument() =>
      groupState.fetchActiveGroupDocument(
        isAuthenticated: isAuthenticated,
        firestoreService: _firestoreService,
      );

  /// Fetch all season picks for a user from Firestore.
  /// Returns list of PicksDocument for the current season.
  Future<List<PicksDocument>> fetchSeasonPicksForUser(String uid) async {
    final fs = _firestoreService;
    if (fs == null || !isAuthenticated) return [];
    return fs.getPicksForUser(uid: uid, seasonKey: currentSeasonKey);
  }

  /// Hydrate picks history + matchday snapshots from Firestore for current user.
  /// This avoids losing "past predictions" and day scores on new install/device.
  Future<void> hydrateCurrentUserHistoryFromFirestore({
    bool force = false,
  }) async {
    final fs = _firestoreService;
    final uid = _profile.id.trim();
    if (fs == null || !isAuthenticated || uid.isEmpty) return;
    if (_hydratingCurrentUserHistoryFromFirestore) return;

    final hydrationKey = '$uid:$currentSeasonKey';
    if (!force && _hydratedCurrentUserHistoryKey == hydrationKey) return;

    _hydratingCurrentUserHistoryFromFirestore = true;
    try {
      final picksDocs = await fs.getPicksForUser(
        uid: uid,
        seasonKey: currentSeasonKey,
      );

      predictionState.ensureCurrentUserPicksHistoryLoaded();
      predictionState.ensureOutcomesHistoryLoaded();
      await predictionState.ensureMatchdayMatchesLoaded();

      var picksChanged = false;
      final dayNumbers = <int>{};
      for (final doc in picksDocs) {
        if (doc.dayNumber <= 0 || doc.picksByMatchId.isEmpty) continue;
        dayNumbers.add(doc.dayNumber);
        final existing =
            predictionState.currentUserPicksByMatchday[doc.dayNumber];
        if (existing == null ||
            existing.length != doc.picksByMatchId.length ||
            existing.entries.any((e) => doc.picksByMatchId[e.key] != e.value)) {
          predictionState.saveCurrentUserPicksHistory(
            dayNumber: doc.dayNumber,
            picksByMatchId: doc.picksByMatchId,
          );
          picksChanged = true;
        }
      }

      final recentMatches = <int, List<PredictionMatch>>{};
      final recentOutcomes = <int, Map<String, MatchOutcome>>{};
      final sortedDays = dayNumbers.toList()..sort((a, b) => b.compareTo(a));
      for (final day in sortedDays) {
        final md = await fs.getMatchdayData(
          seasonKey: currentSeasonKey,
          dayNumber: day,
        );
        if (md == null || md.matches.isEmpty) continue;

        await predictionState.saveMatchesHistory(
          matchdayNumber: day,
          matches: md.matches,
        );
        await predictionState.saveMatchdayMatchesSnapshot(
          matchdayNumber: day,
          matches: md.matches,
        );
        recentMatches[day] = md.matches;

        if (md.outcomesByMatchId.isNotEmpty) {
          predictionState.saveOutcomesHistory(
            dayNumber: day,
            outcomesByMatchId: md.outcomesByMatchId,
          );
          recentOutcomes[day] = md.outcomesByMatchId;
        }
      }

      if (recentMatches.isNotEmpty || recentOutcomes.isNotEmpty) {
        predictionState.setRecentMatchdayDataBulk(
          matchesByMatchday: recentMatches,
          outcomesByMatchday: recentOutcomes,
        );
      } else if (picksChanged) {
        notifyListeners();
      }

      _hydratedCurrentUserHistoryKey = hydrationKey;
    } catch (_) {
      // ignore: best-effort hydration
    } finally {
      _hydratingCurrentUserHistoryFromFirestore = false;
    }
  }

  // ===== LOCAL → FIRESTORE MIGRATION =====
  static const _kFirestoreMigrationV1Done = 'firestore_migration_v1_done';

  /// One-time migration: upload local picks + outcomes to Firestore.
  /// Runs once per device, flagged via SharedPreferences.
  Future<void> migrateLocalDataToFirestoreIfNeeded() async {
    final prefs = _prefs;
    final fs = _firestoreService;
    if (prefs == null || fs == null || !isAuthenticated) return;
    if (prefs.getBool(_kFirestoreMigrationV1Done) == true) return;

    final uid = _profile.id;
    if (uid.isEmpty) return;

    try {
      // 1. Sync profile
      _syncProfileToFirestore();

      // 2. Migrate picks
      predictionState.ensureCurrentUserPicksHistoryLoaded();
      predictionState.ensureOutcomesHistoryLoaded();

      final season = currentSeasonKey;
      for (final entry in predictionState.currentUserPicksByMatchday.entries) {
        final dayNumber = entry.key;
        final picks = entry.value;
        if (picks.isEmpty) continue;

        // Compute score if outcomes available
        DayScoreBreakdown? score;
        final outcomes = predictionState.outcomesByMatchday[dayNumber];
        final matches =
            predictionState.matchesForMatchday(dayNumber) ??
            predictionState.savedMatchesForMatchday(dayNumber);
        if (outcomes != null && matches != null && matches.isNotEmpty) {
          score = CassandraScoringEngine.computeDayScore(
            matches: matches,
            picksByMatchId: picks,
            outcomesByMatchId: outcomes,
          );
        }

        await fs.savePicks(
          uid: uid,
          seasonKey: season,
          dayNumber: dayNumber,
          picksByMatchId: picks,
          visibility: predictionVisibilityToStorage(_defaultVisibility),
          score: score,
        );
      }

      // 3. Migrate matchday data (matches + outcomes)
      await predictionState.ensureMatchdayMatchesLoaded();
      for (final entry in predictionState.matchdayMatchesByDay.entries) {
        final dayNumber = entry.key;
        final matches = entry.value;
        if (matches.isEmpty) continue;

        final outcomes = predictionState.outcomesByMatchday[dayNumber] ?? {};
        await fs.saveMatchdayData(
          seasonKey: season,
          dayNumber: dayNumber,
          matches: matches,
          outcomesByMatchId: outcomes,
        );
      }

      await prefs.setBool(_kFirestoreMigrationV1Done, true);
    } catch (_) {
      // Migration failed — will retry next launch
    }
  }

  // ===== MATCHDAY STATE FORWARDING =====
  // Forwarding getters/methods per compatibilità con codice esistente.
  // La logica è ora in MatchdayState.

  // --- Cursor ---
  int get cassandraMatchdayCursor => matchdayState.cassandraMatchdayCursor;
  Future<void> setCassandraMatchdayCursor(int dayNumber) =>
      matchdayState.setCassandraMatchdayCursor(dayNumber);
  Future<void> bumpCassandraMatchdayCursor() =>
      matchdayState.bumpCassandraMatchdayCursor();

  // --- Finalization ---
  void ensureFinalizedMatchdaysLoaded() =>
      matchdayState.ensureFinalizedMatchdaysLoaded();
  bool isMatchdayFinalized(int matchdayNumber) =>
      matchdayState.isMatchdayFinalized(matchdayNumber);
  Future<bool> markMatchdayFinalized(int matchdayNumber) =>
      matchdayState.markMatchdayFinalized(matchdayNumber);

  // --- Auto-bump ---
  int? get lastAutoBumpFromMatchday => matchdayState.lastAutoBumpFromMatchday;
  Future<bool> maybeAutoBumpCassandraMatchdayCursor({
    required int fromMatchday,
  }) => matchdayState.maybeAutoBumpCassandraMatchdayCursor(
    fromMatchday: fromMatchday,
  );

  // --- Origin kickoffs ---
  void ensureOriginKickoffsLoaded() =>
      matchdayState.ensureOriginKickoffsLoaded();
  void registerOriginKickoff({
    required String matchId,
    required DateTime kickoff,
  }) => matchdayState.registerOriginKickoff(matchId: matchId, kickoff: kickoff);
  DateTime originKickoffFor({
    required String matchId,
    required DateTime fallbackKickoff,
  }) => matchdayState.originKickoffFor(
    matchId: matchId,
    fallbackKickoff: fallbackKickoff,
  );
  Future<void> persistOriginKickoffs() => matchdayState.persistOriginKickoffs();

  // --- Progress (runtime) ---
  int get uiMatchdayNumber => matchdayState.uiMatchdayNumber;
  void setUiMatchdayNumber(int? matchdayNumber) =>
      matchdayState.setUiMatchdayNumber(matchdayNumber);
  MatchdayProgress? matchdayProgressFor(int matchdayNumber) =>
      matchdayState.matchdayProgressFor(matchdayNumber);
  void setMatchdayProgress({
    required int matchdayNumber,
    required MatchdayProgress progress,
    bool allowAutoAdvance = true,
  }) => matchdayState.setMatchdayProgress(
    matchdayNumber: matchdayNumber,
    progress: progress,
    allowAutoAdvance: allowAutoAdvance,
  );
  void clearMatchdayProgress(int matchdayNumber) =>
      matchdayState.clearMatchdayProgress(matchdayNumber);

  // ===== PREDICTION STATE FORWARDING =====
  // Forwarding getters/methods per compatibilità con codice esistente.
  // La logica è ora in PredictionState.
  //
  // Questo blocco sostituisce ~700 righe di codice inline.
  // Vedi prediction_state.dart per l'implementazione.

  // --- Current user picks ---
  Map<String, PickOption> get currentUserPicksByMatchId =>
      predictionState.currentUserPicksByMatchId;
  void ensureCurrentUserPicksLoaded() =>
      predictionState.ensureCurrentUserPicksLoaded();
  void setCurrentUserPick(String matchId, PickOption pick) =>
      predictionState.setCurrentUserPick(matchId, pick);
  void clearCurrentUserPicks() => predictionState.clearCurrentUserPicks();

  // --- Picks history ---
  Map<int, Map<String, PickOption>> get currentUserPicksByMatchday =>
      predictionState.currentUserPicksByMatchday;
  bool hasSavedPicksForMatchday(int dayNumber) =>
      predictionState.hasSavedPicksForMatchday(dayNumber);
  Map<String, PickOption> currentUserPicksForMatchday(int dayNumber) =>
      predictionState.currentUserPicksForMatchday(dayNumber);
  void ensureCurrentUserPicksHistoryLoaded() =>
      predictionState.ensureCurrentUserPicksHistoryLoaded();
  void saveCurrentUserPicksHistory({
    required int dayNumber,
    required Map<String, PickOption> picksByMatchId,
  }) => predictionState.saveCurrentUserPicksHistory(
    dayNumber: dayNumber,
    picksByMatchId: picksByMatchId,
  );
  void clearCurrentUserPicksHistory() =>
      predictionState.clearCurrentUserPicksHistory();
  Map<String, PickOption> picksForCurrentUserForMatchday(int matchdayNumber) =>
      predictionState.picksForCurrentUserForMatchday(matchdayNumber);

  // --- Outcomes history ---
  Map<int, Map<String, MatchOutcome>> get outcomesByMatchday =>
      predictionState.outcomesByMatchday;
  bool hasSavedOutcomesForMatchday(int dayNumber) =>
      predictionState.hasSavedOutcomesForMatchday(dayNumber);
  Map<String, MatchOutcome> outcomesForMatchday(int dayNumber) =>
      predictionState.outcomesForMatchday(dayNumber);
  void ensureOutcomesHistoryLoaded() =>
      predictionState.ensureOutcomesHistoryLoaded();
  void saveOutcomesHistory({
    required int dayNumber,
    required Map<String, MatchOutcome> outcomesByMatchId,
  }) => predictionState.saveOutcomesHistory(
    dayNumber: dayNumber,
    outcomesByMatchId: outcomesByMatchId,
  );
  void clearOutcomesHistory() => predictionState.clearOutcomesHistory();

  // --- Matches history ---
  Map<int, List<PredictionMatch>> get matchesByMatchday =>
      predictionState.matchesByMatchday;
  List<PredictionMatch>? matchesForMatchday(int matchdayNumber) =>
      predictionState.matchesForMatchday(matchdayNumber);
  void ensureMatchesHistoryLoaded() =>
      predictionState.ensureMatchesHistoryLoaded();
  Future<void> saveMatchesHistory({
    required int matchdayNumber,
    required List<PredictionMatch> matches,
  }) => predictionState.saveMatchesHistory(
    matchdayNumber: matchdayNumber,
    matches: matches,
  );
  Future<void> clearMatchesHistory() => predictionState.clearMatchesHistory();

  // --- Matchday matches snapshots ---
  Map<int, List<PredictionMatch>> get matchdayMatchesByDay =>
      predictionState.matchdayMatchesByDay;
  Future<void> ensureMatchdayMatchesLoaded() =>
      predictionState.ensureMatchdayMatchesLoaded();
  bool hasSavedMatchesForMatchday(int matchdayNumber) =>
      predictionState.hasSavedMatchesForMatchday(matchdayNumber);
  List<PredictionMatch>? savedMatchesForMatchday(int matchdayNumber) =>
      predictionState.savedMatchesForMatchday(matchdayNumber);
  Future<void> saveMatchdayMatchesSnapshot({
    required int matchdayNumber,
    required List<PredictionMatch> matches,
  }) => predictionState.saveMatchdayMatchesSnapshot(
    matchdayNumber: matchdayNumber,
    matches: matches,
  );

  // --- Member picks ---
  Map<String, Map<String, PickOption>> get memberPicksByMemberId =>
      predictionState.memberPicksByMemberId;
  void ensureMemberPicksLoaded() => predictionState.ensureMemberPicksLoaded();
  void setMemberPicksBulk(
    Map<String, Map<String, PickOption>> picksByMemberId, {
    bool replace = false,
  }) => predictionState.setMemberPicksBulk(picksByMemberId, replace: replace);
  void clearMemberPicks({String? memberId}) =>
      predictionState.clearMemberPicks(memberId: memberId);

  // --- Runtime cache ---
  Map<String, MatchOutcome> get cachedPredictionOutcomesByMatchId =>
      predictionState.cachedPredictionOutcomesByMatchId;
  List<PredictionMatch>? get cachedPredictionMatches =>
      predictionState.cachedPredictionMatches;
  bool get cachedPredictionMatchesAreReal =>
      predictionState.cachedPredictionMatchesAreReal;
  DateTime? get cachedPredictionMatchesUpdatedAt =>
      predictionState.cachedPredictionMatchesUpdatedAt;
  Map<int, ApiFootballFixtureOdds>? get cachedRealOdds =>
      predictionState.cachedRealOdds;
  List<ApiFootballStanding> get cachedSeasonStandings =>
      predictionState.cachedSeasonStandings;
  DateTime? get cachedSeasonStandingsUpdatedAt =>
      predictionState.cachedSeasonStandingsUpdatedAt;
  Map<String, MatchOutcome> get effectivePredictionOutcomesByMatchId =>
      predictionState.effectivePredictionOutcomesByMatchId;

  void setCachedRealOdds(Map<int, ApiFootballFixtureOdds> odds) =>
      predictionState.setCachedRealOdds(odds);
  void setCachedPredictionMatches(
    List<PredictionMatch> matches, {
    required bool isReal,
    DateTime? updatedAt,
  }) => predictionState.setCachedPredictionMatches(
    matches,
    isReal: isReal,
    updatedAt: updatedAt,
  );
  void clearCachedPredictionMatches() =>
      predictionState.clearCachedPredictionMatches();
  void clearCachedPredictionOutcomes() =>
      predictionState.clearCachedPredictionOutcomes();
  void setCachedPredictionOutcomesByMatchId(
    Map<String, MatchOutcome> outcomes,
  ) => predictionState.setCachedPredictionOutcomesByMatchId(outcomes);
  void setCachedSeasonStandings(
    List<ApiFootballStanding> standings, {
    DateTime? updatedAt,
  }) =>
      predictionState.setCachedSeasonStandings(standings, updatedAt: updatedAt);
  void clearAllPredictionCache() => predictionState.clearAllPredictionCache();

  // --- Recent matchday data ---
  Map<int, List<PredictionMatch>> get recentMatchesByMatchday =>
      predictionState.recentMatchesByMatchday;
  Map<int, Map<String, MatchOutcome>> get recentOutcomesByMatchday =>
      predictionState.recentOutcomesByMatchday;
  void setRecentMatchdayDataBulk({
    required Map<int, List<PredictionMatch>> matchesByMatchday,
    required Map<int, Map<String, MatchOutcome>> outcomesByMatchday,
    bool replace = false,
  }) => predictionState.setRecentMatchdayDataBulk(
    matchesByMatchday: matchesByMatchday,
    outcomesByMatchday: outcomesByMatchday,
    replace: replace,
  );

  // --- Clear all / Demo ---
  void clearAllHistory() => predictionState.clearAllHistory();

  Future<void> bumpDemoSeed() async {
    _demoSeed = _demoSeed + 1;
    await _prefs?.setInt(_kDemoSeedV1, _demoSeed);
    notifyListeners();
  }
}
