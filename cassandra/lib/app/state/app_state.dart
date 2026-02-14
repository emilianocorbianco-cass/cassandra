import 'dart:io';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
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
import 'dart:math';

import '../../features/predictions/models/prediction_match.dart';
import '../../services/api_football/models/api_football_odds.dart';
import '../../services/api_football/models/api_football_standing.dart';

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

  static const _kGroupNameV1 = 'group.name.v1';
  static const _kGroupInviteCodeV1 = 'group.inviteCode.v1';
  static const _kGroupImagePathV1 = 'group.imagePath.v1';
  static const _kGroupAdminApprovalV1 = 'group.adminApproval.v1';

  // Chiavi legacy (macro-step 1 precedente)
  static const _kTeamNameLegacy = 'teamName';
  static const _kFavoriteTeamLegacy = 'favoriteTeam';

  static const _kProfileId = 'profile.id.v1';
  static const _kProfileDisplayName = 'profile.displayName.v1';
  static const _kProfileEmail = 'profile.email.v1';
  static const _kProfilePhotoUrl = 'profile.photoUrl.v1';

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

    final remoteTeamName = data['teamName'] as String?;
    if (remoteTeamName != null &&
        remoteTeamName.isNotEmpty &&
        _profile.teamName == _defaultProfile.teamName &&
        remoteTeamName != _profile.teamName) {
      _profile = _profile.copyWith(teamName: remoteTeamName);
      _prefs?.setString(_kProfileTeamName, remoteTeamName);
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
      _firestoreGroupIds = remoteGroupIds;
      if (_activeGroupId == null ||
          !_firestoreGroupIds.contains(_activeGroupId)) {
        _activeGroupId = _firestoreGroupIds.isNotEmpty
            ? _firestoreGroupIds.first
            : null;
      }
      changed = true;
    }

    if (changed) notifyListeners();

    if ((remoteGroupIds?.isNotEmpty ?? false) &&
        (_groupName == null || _groupInviteCode == null)) {
      unawaited(refreshActiveGroupMetadataFromFirestore().catchError((_) {}));
    }
  }

  // Firestore group IDs (multi-group)
  List<String> _firestoreGroupIds = [];
  List<String> get firestoreGroupIds => _firestoreGroupIds;

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
      if (_firestoreGroupIds.isEmpty) {
        final recoveredGroupIds = await fs.findGroupIdsForMember(targetUid);
        if (recoveredGroupIds.isNotEmpty) {
          _firestoreGroupIds = recoveredGroupIds;
          _activeGroupId = recoveredGroupIds.first;
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
    final fs = _firestoreService;
    final groupId = activeGroupId;
    if (fs == null || !isAuthenticated || groupId == null) return;

    final group = await fs.getGroup(groupId);
    if (group == null) return;

    var changed = false;
    if (_groupName != group.name) {
      _groupName = group.name;
      await _prefs?.setString(_kGroupNameV1, group.name);
      changed = true;
    }
    if (_groupInviteCode != group.inviteCode) {
      _groupInviteCode = group.inviteCode;
      await _prefs?.setString(_kGroupInviteCodeV1, group.inviteCode);
      changed = true;
    }

    if (changed) notifyListeners();
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

  // ===== GRUPPO =====
  String? _groupName;
  String? _groupInviteCode;
  String? _groupImagePath;
  bool _groupAdminApproval = false;

  String? get groupName => _groupName;
  String? get groupInviteCode => _groupInviteCode;
  String? get groupImagePath => _groupImagePath;
  bool get groupAdminApproval => _groupAdminApproval;
  bool get hasGroup => activeGroupId != null || _groupName != null;

  Future<void> updateGroupImagePath(String? path) async {
    _groupImagePath = path;
    if (path != null) {
      await _prefs?.setString(_kGroupImagePathV1, path);
    } else {
      await _prefs?.remove(_kGroupImagePathV1);
    }
    notifyListeners();
  }

  Future<void> updateGroupAdminApproval(bool value) async {
    _groupAdminApproval = value;
    await _prefs?.setBool(_kGroupAdminApprovalV1, value);
    notifyListeners();
  }

  void _deleteGroupImageFile() {
    final path = _groupImagePath;
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // ignore: best-effort cleanup
    }
  }

  Future<String?> createGroup(String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return 'Invalid name';

    // Genera codice invito CASS-XXXX (con check unicità su Firestore)
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    final fs = _firestoreService;
    final uid = _profile.id;

    // Dev mode: backend non configurato → crea solo locale.
    if (fs == null) {
      final suffix = List.generate(
        4,
        (_) => chars[rng.nextInt(chars.length)],
      ).join();
      final code = 'CASS-$suffix';
      _groupName = cleaned;
      _groupInviteCode = code;
      await _prefs?.setString(_kGroupNameV1, cleaned);
      await _prefs?.setString(_kGroupInviteCodeV1, code);
      notifyListeners();
      return null;
    }

    if (!isAuthenticated || uid.isEmpty) {
      return 'Not authenticated';
    }

    String? code;
    for (var i = 0; i < 30; i++) {
      final suffix = List.generate(
        4,
        (_) => chars[rng.nextInt(chars.length)],
      ).join();
      final candidate = 'CASS-$suffix';
      try {
        final taken = await fs.isInviteCodeTaken(candidate);
        if (!taken) {
          code = candidate;
          break;
        }
      } catch (_) {
        return 'Permission denied';
      }
    }
    if (code == null) return 'Invite code generation failed';

    try {
      final groupId = await fs.createGroup(
        name: cleaned,
        adminUid: uid,
        inviteCode: code,
      );
      // Aggiungi admin come primo membro
      await fs.joinGroup(
        groupId: groupId,
        uid: uid,
        displayName: _profile.displayName,
        teamName: _profile.teamName,
        avatarSeed: currentUserAvatarSeed,
        favoriteTeam: _profile.favoriteTeam,
      );

      _groupName = cleaned;
      _groupInviteCode = code;
      await _prefs?.setString(_kGroupNameV1, cleaned);
      await _prefs?.setString(_kGroupInviteCodeV1, code);

      if (!_firestoreGroupIds.contains(groupId)) {
        _firestoreGroupIds = [..._firestoreGroupIds, groupId];
      }
      _activeGroupId = groupId;

      notifyListeners();
      return null;
    } catch (_) {
      return 'Create group failed';
    }
  }

  /// Gruppo Firestore attivo (primo per default)
  String? _activeGroupId;
  String? get activeGroupId =>
      _activeGroupId ??
      (_firestoreGroupIds.isNotEmpty ? _firestoreGroupIds.first : null);

  void setActiveGroupId(String? id) {
    _activeGroupId = id;
    notifyListeners();
  }

  /// Join a Firestore group by invite code. Returns error string or null on success.
  Future<String?> joinGroupByInviteCode(String code) async {
    final fs = _firestoreService;
    if (fs == null) return 'Backend unavailable';
    if (!isAuthenticated) return 'Not authenticated';

    final group = await fs.getGroupByInviteCode(code.trim().toUpperCase());
    if (group == null) return 'Invalid code';

    final uid = _profile.id;

    // Check se già membro
    if (_firestoreGroupIds.contains(group.id)) return 'Already a member';

    await fs.joinGroup(
      groupId: group.id,
      uid: uid,
      displayName: _profile.displayName,
      teamName: _profile.teamName,
      avatarSeed: currentUserAvatarSeed,
      favoriteTeam: _profile.favoriteTeam,
    );

    _firestoreGroupIds = [..._firestoreGroupIds, group.id];
    _activeGroupId = group.id;

    // Salva anche localmente per compatibilità
    _groupName = group.name;
    _groupInviteCode = group.inviteCode;
    await _prefs?.setString(_kGroupNameV1, group.name);
    await _prefs?.setString(_kGroupInviteCodeV1, group.inviteCode);

    notifyListeners();
    return null;
  }

  /// Leave a Firestore group.
  Future<void> leaveFirestoreGroup(String groupId) async {
    final fs = _firestoreService;
    if (fs == null || !isAuthenticated) return;

    final uid = _profile.id;
    await fs.leaveGroup(groupId: groupId, uid: uid);

    _firestoreGroupIds = _firestoreGroupIds
        .where((id) => id != groupId)
        .toList();
    if (_activeGroupId == groupId) {
      _activeGroupId = _firestoreGroupIds.isNotEmpty
          ? _firestoreGroupIds.first
          : null;
    }

    // Se non ha più gruppi, pulisci anche locale
    if (_firestoreGroupIds.isEmpty) {
      _groupName = null;
      _groupInviteCode = null;
      _deleteGroupImageFile();
      _groupImagePath = null;
      await _prefs?.remove(_kGroupNameV1);
      await _prefs?.remove(_kGroupInviteCodeV1);
      await _prefs?.remove(_kGroupImagePathV1);
    }

    notifyListeners();
  }

  Future<String?> deleteActiveGroupIfAdmin() async {
    final fs = _firestoreService;
    final groupId = activeGroupId;
    if (groupId == null) return 'No group';

    if (fs == null) {
      _groupName = null;
      _groupInviteCode = null;
      _deleteGroupImageFile();
      _groupImagePath = null;
      _groupAdminApproval = false;
      _activeGroupId = null;
      _firestoreGroupIds = [];
      await _prefs?.remove(_kGroupNameV1);
      await _prefs?.remove(_kGroupInviteCodeV1);
      await _prefs?.remove(_kGroupImagePathV1);
      await _prefs?.remove(_kGroupAdminApprovalV1);
      notifyListeners();
      return null;
    }

    if (!isAuthenticated || _profile.id.isEmpty) return 'Not authenticated';

    GroupDocument? group;
    try {
      group = await fs.getGroup(groupId);
    } catch (_) {
      return 'Delete group failed';
    }

    if (group == null) {
      _firestoreGroupIds = _firestoreGroupIds
          .where((id) => id != groupId)
          .toList();
      _activeGroupId = _firestoreGroupIds.isNotEmpty
          ? _firestoreGroupIds.first
          : null;
      if (_activeGroupId == null) {
        _groupName = null;
        _groupInviteCode = null;
        _deleteGroupImageFile();
        _groupImagePath = null;
        _groupAdminApproval = false;
        await _prefs?.remove(_kGroupNameV1);
        await _prefs?.remove(_kGroupInviteCodeV1);
        await _prefs?.remove(_kGroupImagePathV1);
        await _prefs?.remove(_kGroupAdminApprovalV1);
      }
      notifyListeners();
      return null;
    }

    if (group.adminUid != _profile.id) return 'Not admin';

    try {
      await fs.deleteGroupAsAdmin(groupId: groupId, adminUid: _profile.id);
    } catch (_) {
      return 'Delete group failed';
    }

    _firestoreGroupIds = _firestoreGroupIds
        .where((id) => id != groupId)
        .toList();
    _activeGroupId = _firestoreGroupIds.isNotEmpty
        ? _firestoreGroupIds.first
        : null;

    _deleteGroupImageFile();
    _groupImagePath = null;
    _groupAdminApproval = false;

    if (_activeGroupId == null) {
      _groupName = null;
      _groupInviteCode = null;
      await _prefs?.remove(_kGroupNameV1);
      await _prefs?.remove(_kGroupInviteCodeV1);
      await _prefs?.remove(_kGroupImagePathV1);
      await _prefs?.remove(_kGroupAdminApprovalV1);
    } else {
      final next = await fs.getGroup(_activeGroupId!);
      if (next != null) {
        _groupName = next.name;
        _groupInviteCode = next.inviteCode;
        await _prefs?.setString(_kGroupNameV1, next.name);
        await _prefs?.setString(_kGroupInviteCodeV1, next.inviteCode);
        await _prefs?.remove(_kGroupImagePathV1);
        await _prefs?.setBool(_kGroupAdminApprovalV1, false);
      } else {
        _groupName = null;
        _groupInviteCode = null;
        _activeGroupId = null;
        _firestoreGroupIds = [];
        await _prefs?.remove(_kGroupNameV1);
        await _prefs?.remove(_kGroupInviteCodeV1);
        await _prefs?.remove(_kGroupImagePathV1);
        await _prefs?.remove(_kGroupAdminApprovalV1);
      }
    }

    notifyListeners();
    return null;
  }

  Future<void> updateGroupName(String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return;
    if (cleaned == _groupName) return;

    _groupName = cleaned;
    await _prefs?.setString(_kGroupNameV1, cleaned);
    notifyListeners();
  }

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

    final groupName = prefs.getString(_kGroupNameV1);
    final groupInviteCode = prefs.getString(_kGroupInviteCodeV1);
    final groupImagePath = prefs.getString(_kGroupImagePathV1);
    final groupAdminApproval = prefs.getBool(_kGroupAdminApprovalV1) ?? false;

    return AppState._(
        prefs,
        profile: profile,
        language: language,
        defaultVisibility: visibility,
        demoSeed: demoSeed,
      )
      .._groupName = groupName
      .._groupInviteCode = groupInviteCode
      .._groupImagePath = groupImagePath
      .._groupAdminApproval = groupAdminApproval;
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
    _syncFieldToFirestore({'teamName': cleaned});
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

  void setProfileFromFirebaseUser(User user) {
    final existingTeamName =
        _prefs?.getString(_kProfileTeamName) ??
        _prefs?.getString(_kTeamNameLegacy);
    final existingFavoriteTeam =
        _prefs?.getString(_kProfileFavoriteTeam) ??
        _prefs?.getString(_kFavoriteTeamLegacy);

    _profile = UserProfile.fromFirebaseUser(
      user,
      existingTeamName: existingTeamName,
      existingFavoriteTeam: existingFavoriteTeam,
    );

    _prefs?.setString(_kProfileId, user.uid);
    _prefs?.setString(_kProfileDisplayName, _profile.displayName);
    if (_profile.email != null) {
      _prefs?.setString(_kProfileEmail, _profile.email!);
    }
    if (_profile.photoUrl != null) {
      _prefs?.setString(_kProfilePhotoUrl, _profile.photoUrl!);
    }

    _syncProfileToFirestore();
    notifyListeners();
  }

  Future<void> signOut() async {
    await _authService?.signOut();

    _prefs?.remove(_kProfileId);
    _prefs?.remove(_kProfileDisplayName);
    _prefs?.remove(_kProfileEmail);
    _prefs?.remove(_kProfilePhotoUrl);
    _prefs?.remove(_kGroupNameV1);
    _prefs?.remove(_kGroupInviteCodeV1);
    _prefs?.remove(_kGroupImagePathV1);
    _prefs?.remove(_kGroupAdminApprovalV1);

    _deleteGroupImageFile();

    _profile = _defaultProfile;
    _groupName = null;
    _groupInviteCode = null;
    _groupImagePath = null;
    _groupAdminApproval = false;
    _firestoreGroupIds = [];
    _activeGroupId = null;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await _authService?.deleteAccount();

    _prefs?.remove(_kProfileId);
    _prefs?.remove(_kProfileDisplayName);
    _prefs?.remove(_kProfileEmail);
    _prefs?.remove(_kProfilePhotoUrl);
    _prefs?.remove(_kGroupNameV1);
    _prefs?.remove(_kGroupInviteCodeV1);
    _prefs?.remove(_kGroupImagePathV1);
    _prefs?.remove(_kGroupAdminApprovalV1);

    _deleteGroupImageFile();

    _groupName = null;
    _groupInviteCode = null;
    _groupImagePath = null;
    _groupAdminApproval = false;
    _firestoreGroupIds = [];
    _activeGroupId = null;

    await resetAll();
    notifyListeners();
  }

  Future<void> resetAll() async {
    _profile = _defaultProfile;
    _language = CassandraLanguage.system;
    _defaultVisibility = PredictionVisibility.friends;
    _groupName = null;
    _groupInviteCode = null;
    _deleteGroupImageFile();
    _groupImagePath = null;
    _groupAdminApproval = false;
    _firestoreGroupIds = [];
    _activeGroupId = null;
    notifyListeners();

    if (_prefs == null) return;

    await _prefs.remove(_kProfileTeamName);
    await _prefs.remove(_kProfileFavoriteTeam);

    await _prefs.remove(_kTeamNameLegacy);
    await _prefs.remove(_kFavoriteTeamLegacy);

    await _prefs.remove(_kLanguage);
    await _prefs.remove(_kDefaultVisibility);

    await _prefs.remove(_kGroupNameV1);
    await _prefs.remove(_kGroupInviteCodeV1);
    await _prefs.remove(_kGroupImagePathV1);
    await _prefs.remove(_kGroupAdminApprovalV1);
  }

  // ===== Runtime cache (NON persistita) =====
  // Usata per condividere le fixture reali tra pagine (Pronostici, Gruppo, ecc.)
  // senza rifare fetch e senza scriverle su storage.

  List<PredictionMatch>? _cachedPredictionMatches;
  bool _cachedPredictionMatchesAreReal = false;
  DateTime? _cachedPredictionMatchesUpdatedAt;

  // Quote reali (runtime cache per evitare ri-fetch ad ogni apertura)
  Map<int, ApiFootballFixtureOdds>? _cachedRealOdds;
  List<ApiFootballStanding> _cachedSeasonStandings =
      const <ApiFootballStanding>[];
  DateTime? _cachedSeasonStandingsUpdatedAt;
  String _cachedSeasonStandingsSignature = '';

  Map<int, ApiFootballFixtureOdds>? get cachedRealOdds => _cachedRealOdds;
  List<ApiFootballStanding> get cachedSeasonStandings => _cachedSeasonStandings;
  DateTime? get cachedSeasonStandingsUpdatedAt =>
      _cachedSeasonStandingsUpdatedAt;

  void setCachedRealOdds(Map<int, ApiFootballFixtureOdds> odds) {
    _cachedRealOdds = Map.unmodifiable(odds);
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
    if (updatedAt == null && _cachedSeasonStandingsSignature == sig) {
      return;
    }

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

  List<PredictionMatch>? get cachedPredictionMatches =>
      _cachedPredictionMatches;
  bool get cachedPredictionMatchesAreReal => _cachedPredictionMatchesAreReal;
  DateTime? get cachedPredictionMatchesUpdatedAt =>
      _cachedPredictionMatchesUpdatedAt;

  // ===== MatchdayProgress (runtime, non persistito) =====
  final Map<int, MatchdayProgress> _matchdayProgressByDay = {};

  int? _uiMatchdayNumber;
  int? _autoAdvancedFromMatchday;
  int? _autoFinalizedFromMatchday;
  int get uiMatchdayNumber => _uiMatchdayNumber ?? cassandraMatchdayCursor;

  void setUiMatchdayNumber(int? matchdayNumber) {
    _uiMatchdayNumber = matchdayNumber;
    notifyListeners();
  }

  MatchdayProgress? matchdayProgressFor(int matchdayNumber) =>
      _matchdayProgressByDay[matchdayNumber];

  void setMatchdayProgress({
    required int matchdayNumber,
    required MatchdayProgress progress,
    bool allowAutoAdvance = true,
  }) {
    _matchdayProgressByDay[matchdayNumber] = progress;

    _uiMatchdayNumber = matchdayNumber;

    // AUTO-ADVANCE: primaryDone
    if (allowAutoAdvance &&
        progress.primaryDone &&
        progress.isValidMatchday &&
        matchdayNumber == cassandraMatchdayCursor &&
        _autoAdvancedFromMatchday != matchdayNumber) {
      _autoAdvancedFromMatchday = matchdayNumber;
      Future.microtask(() async {
        try {
          await setCassandraMatchdayCursor(matchdayNumber + 1);
        } catch (_) {}
      });
    }

    // AUTO-FINALIZE: finalDone
    if (progress.finalDone &&
        progress.isValidMatchday &&
        _autoFinalizedFromMatchday != matchdayNumber) {
      _autoFinalizedFromMatchday = matchdayNumber;
      Future.microtask(() async {
        try {} catch (_) {}
        isMatchdayFinalized(matchdayNumber);
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
    _cachedSeasonStandings = const <ApiFootballStanding>[];
    _cachedSeasonStandingsUpdatedAt = null;
    _cachedSeasonStandingsSignature = '';
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
  /// Returns list of GroupMember (domain model).
  Future<List<GroupMember>> fetchFirestoreGroupMembers() async {
    final fs = _firestoreService;
    final groupId = activeGroupId;
    if (fs == null || !isAuthenticated || groupId == null) return [];

    final docs = await fs.getGroupMembers(groupId);
    return docs
        .map(
          (d) => GroupMember(
            id: d.uid,
            displayName: d.displayName,
            teamName: d.teamName,
            avatarSeed: d.avatarSeed,
            favoriteTeam: d.favoriteTeam,
          ),
        )
        .toList();
  }

  /// Fetch picks from Firestore for a list of UIDs + matchday.
  /// Returns map: uid -> picksByMatchId.
  Future<Map<String, Map<String, PickOption>>> fetchFirestorePicksForMatchday({
    required int dayNumber,
    required List<String> uids,
  }) async {
    final fs = _firestoreService;
    if (fs == null || !isAuthenticated) return {};

    final docs = await fs.getPicksForMatchday(
      seasonKey: currentSeasonKey,
      dayNumber: dayNumber,
      uids: uids,
    );

    return {for (final d in docs) d.uid: d.picksByMatchId};
  }

  /// Fetch active group metadata from Firestore.
  Future<GroupDocument?> fetchActiveGroupDocument() async {
    final fs = _firestoreService;
    final groupId = activeGroupId;
    if (fs == null || !isAuthenticated || groupId == null) return null;
    return fs.getGroup(groupId);
  }

  /// Fetch all season picks for a user from Firestore.
  /// Returns list of PicksDocument for the current season.
  Future<List<PicksDocument>> fetchSeasonPicksForUser(String uid) async {
    final fs = _firestoreService;
    if (fs == null || !isAuthenticated) return [];
    return fs.getPicksForUser(uid: uid, seasonKey: currentSeasonKey);
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
      ensureCurrentUserPicksHistoryLoaded();
      ensureOutcomesHistoryLoaded();

      final season = currentSeasonKey;
      for (final entry in _currentUserPicksByMatchday.entries) {
        final dayNumber = entry.key;
        final picks = entry.value;
        if (picks.isEmpty) continue;

        // Compute score if outcomes available
        DayScoreBreakdown? score;
        final outcomes = _outcomesByMatchday[dayNumber];
        final matches =
            _matchesByMatchday[dayNumber] ?? _matchdayMatchesByDay[dayNumber];
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
      ensureMatchdayMatchesLoaded();
      for (final entry in _matchdayMatchesByDay.entries) {
        final dayNumber = entry.key;
        final matches = entry.value;
        if (matches.isEmpty) continue;

        final outcomes = _outcomesByMatchday[dayNumber] ?? {};
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

  Map<String, MatchOutcome> get effectivePredictionOutcomesByMatchId =>
      cachedPredictionOutcomesByMatchId;

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
      if (m.homeTeamLogo != null) 'homeLogo': m.homeTeamLogo,
      if (m.awayTeamLogo != null) 'awayLogo': m.awayTeamLogo,
      if (m.homeGoals != null) 'homeGoals': m.homeGoals,
      if (m.awayGoals != null) 'awayGoals': m.awayGoals,
      if (m.statusShort != null && m.statusShort!.isNotEmpty)
        'statusShort': m.statusShort,
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
    return PredictionMatch(
      id: j['id'] as String,
      kickoff: DateTime.parse(j['kickoff'] as String).toLocal(),
      homeTeam: j['home'] as String,
      awayTeam: j['away'] as String,
      homeTeamLogo: j['homeLogo'] as String?,
      awayTeamLogo: j['awayLogo'] as String?,
      homeGoals: _asNullableInt(j['homeGoals']),
      awayGoals: _asNullableInt(j['awayGoals']),
      statusShort: (rawStatus == null || rawStatus.isEmpty) ? null : rawStatus,
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
