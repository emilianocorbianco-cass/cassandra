import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'cassandra_clock.dart';
import 'group_state.dart';
import 'matchday_state.dart';
import 'prediction_state.dart';
import 'user_profile.dart';
import '../../features/group/models/group_member.dart';
import '../../features/scoring/models/match_outcome.dart';
import '../../features/scoring/models/score_breakdown.dart';
import '../../services/firestore/models/group_document.dart';
import '../../services/firestore/models/picks_document.dart';
import '../../services/auth/auth_service.dart';
import '../../services/firestore/firestore_service.dart';
import '../../services/notifications/push_notifications_service.dart';
import '../../services/storage/storage_service.dart';
import 'dart:async';
import '../../features/predictions/models/pick_option.dart';

import '../../features/predictions/models/prediction_match.dart';
import '../../services/api_football/models/api_football_odds.dart';
import '../../services/api_football/models/api_football_standing.dart';

import '../../domain/matchday/matchday_recovery_rules.dart';
import '../config/storage_keys.dart';

class AppState extends ChangeNotifier {
  /// Virtual clock for cold-test time travel. Production: always real time.
  final CassandraClock clock = CassandraClock();

  /// App-wide "now" — respects cold-test time travel when active.
  DateTime now() => clock.now();

  bool get isColdTestActive => clock.isActive;

  /// Activate or deactivate the cold-test clock and rebuild the widget tree.
  void setColdTestClock({Duration? offset}) {
    if (offset != null) {
      clock.activate(offset);
    } else {
      clock.deactivate();
    }
    notifyListeners();
  }

  static const Duration _kProfileSyncDebounce = Duration(milliseconds: 450);
  static const Duration _kProfileSyncRetryDelay = Duration(seconds: 2);
  static const Duration _kProfileSyncRetryMaxDelay = Duration(seconds: 12);
  static const Duration _kHistoryHydrationTimeout = Duration(seconds: 25);
  static const Duration _kHistoryHydrationRetryBaseDelay = Duration(seconds: 2);
  static const Duration _kHistoryHydrationRetryMaxDelay = Duration(seconds: 12);
  static const Duration _kFirestoreWriteRetryBaseDelay = Duration(
    milliseconds: 400,
  );
  static const int _kHistoryHydrationAttempts = 3;
  static const int _kFirestoreWriteAttempts = 3;
  // Chiavi "nuove" (più pulite)
  static const _kProfileTeamName = StorageKeys.profileTeamName;
  static const _kProfileFavoriteTeam = StorageKeys.profileFavoriteTeam;
  static const _kDemoSeedV1 = StorageKeys.demoSeedV1;

  // Chiavi legacy (macro-step 1 precedente)
  static const _kTeamNameLegacy = StorageKeys.teamNameLegacy;
  static const _kFavoriteTeamLegacy = StorageKeys.favoriteTeamLegacy;

  static const _kProfileId = StorageKeys.profileIdV1;
  static const _kProfileDisplayName = StorageKeys.profileDisplayNameV1;
  static const _kProfileEmail = StorageKeys.profileEmailV1;
  static const _kProfilePhotoUrl = StorageKeys.profilePhotoUrlV1;
  static const _kProfileLocalUpdatedAtMs =
      StorageKeys.profileLocalUpdatedAtMsV1;
  static const _kProfileLocalFieldUpdatedAtMs =
      StorageKeys.profileLocalFieldUpdatedAtMsV1;
  static const _kRememberMeEnabled = StorageKeys.rememberMeEnabledV1;
  static const _kRememberedUid = StorageKeys.rememberedUidV1;
  static const _kRememberedHandle = StorageKeys.rememberedHandleV1;
  static const _kRememberedPhotoUrl = StorageKeys.rememberedPhotoUrlV1;
  static const _kRememberedProvider = StorageKeys.rememberedProviderV1;
  static const _kAnonymousHistoryScope = StorageKeys.anonymousHistoryScopeV1;
  static const _kDevicePushToken = StorageKeys.devicePushTokenV1;
  static const _kFirestoreMigrationV1Done =
      StorageKeys.firestoreMigrationV1Done;

  static const _kLanguage = StorageKeys.language;
  static const _kDefaultVisibility = StorageKeys.defaultVisibility;
  static const _kThemeMode = StorageKeys.themeMode;

  static const _kProfileFieldDisplayName = 'displayName';
  static const _kProfileFieldTeamName = 'teamName';
  static const _kProfileFieldFavoriteTeam = 'favoriteTeam';
  static const _kProfileFieldPhotoUrl = 'photoUrl';
  static const _kProfileFieldLanguage = 'language';
  static const _kProfileFieldDefaultVisibility = 'defaultVisibility';

  // ---------------------------------------------------------------------------
  // Pure parsing helpers (extracted for testability)
  // ---------------------------------------------------------------------------

  /// Parses the [groupIds] field from a Firestore user-profile snapshot.
  ///
  /// Returns `null` when the field is absent or not a List, and silently
  /// filters out any non-String elements (e.g. ints from schema drift) rather
  /// than throwing a [CastError] from a lazy `.cast<String>()` call.
  @visibleForTesting
  static List<String>? parseGroupIds(dynamic raw) {
    if (raw is! List) return null;
    return raw.whereType<String>().toList(growable: false);
  }

  // Key strings duplicated from PredictionState for scoped key generation.
  static const _kCurrentUserPicksByMatchday =
      StorageKeys.currentUserPicksByMatchdayV1;
  static const _kPendingPicksOutbox = StorageKeys.pendingPicksOutboxV1;
  static const _kPredictionOutcomesByMatchday =
      StorageKeys.predictionOutcomesByMatchdayV1;
  static const _kMatchdayMatchesByDayV1 = StorageKeys.matchdayMatchesByDayV1;

  String? _anonymousHistoryScope;

  String _resolveAnonymousHistoryScope() {
    final cached = _anonymousHistoryScope;
    if (cached != null && cached.trim().isNotEmpty) return cached.trim();

    final fromPrefs = _prefs?.getString(_kAnonymousHistoryScope)?.trim();
    if (fromPrefs != null && fromPrefs.isNotEmpty) {
      _anonymousHistoryScope = fromPrefs;
      return fromPrefs;
    }

    final generated =
        'anon-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    _anonymousHistoryScope = generated;
    unawaited(_prefs?.setString(_kAnonymousHistoryScope, generated));
    return generated;
  }

  String _scopedHistoryKey(String base, {String? uid, String? seasonKey}) {
    final scopedUidRaw = (uid ?? _profile.id).trim();
    final scopedUid = scopedUidRaw.isEmpty
        ? _resolveAnonymousHistoryScope()
        : scopedUidRaw;
    final scopedSeason = (seasonKey ?? currentSeasonKey).trim();
    final safeUid = scopedUid;
    final safeSeason = scopedSeason.isEmpty ? 'season' : scopedSeason;
    return '$base.$safeUid.$safeSeason';
  }

  String get _kFirestoreMigrationV1DoneScoped =>
      _scopedHistoryKey(_kFirestoreMigrationV1Done);
  String get _kPendingPicksOutboxScoped =>
      _scopedHistoryKey(_kPendingPicksOutbox);

  static const UserProfile _defaultProfile = UserProfile(
    id: '',
    displayName: '',
    teamName: '',
  );

  final SharedPreferences? _prefs;

  AuthService? _authService;
  FirestoreService? _firestoreService;
  StorageService? _storageService;
  StreamSubscription<User?>? _authStateSubscription;
  StreamSubscription<User?>? _idTokenSubscription;
  String? _lastAuthBootstrapUid;

  AuthService? get authService => _authService;
  FirestoreService? get firestoreService => _firestoreService;
  StorageService? get storageService => _storageService;

  void setAuthService(AuthService service) {
    if (identical(_authService, service)) return;
    _authStateSubscription?.cancel();
    _idTokenSubscription?.cancel();
    _authService = service;
    _bindAuthReconciliationStreams(service);
  }

  void setFirestoreService(FirestoreService service) {
    _firestoreService = service;
    final currentUser = _authService?.currentUser;
    if (currentUser != null) {
      _handleAuthStreamEvent(currentUser);
    }
  }

  void setStorageService(StorageService service) {
    _storageService = service;
  }

  void _bindAuthReconciliationStreams(AuthService service) {
    _authStateSubscription = service.authStateChanges.listen(
      (user) => _handleAuthStreamEvent(user),
      onError: (Object error, StackTrace stackTrace) {
        _recordBackendError(error, stackTrace);
      },
    );
    _idTokenSubscription = service.idTokenChanges.listen(
      (user) => _handleAuthStreamEvent(user),
      onError: (Object error, StackTrace stackTrace) {
        _recordBackendError(error, stackTrace);
      },
    );

    // Bootstrap immediately from current auth state to avoid startup races.
    _handleAuthStreamEvent(service.currentUser);
  }

  void _handleAuthStreamEvent(User? user) {
    final incomingUid = user?.uid.trim() ?? '';
    if (incomingUid.isEmpty) {
      unawaited(_applySignedOutAuthStateIfNeeded());
      return;
    }
    if (_profile.id.trim() != incomingUid) {
      setProfileFromFirebaseUser(user!);
    }
    if (_lastAuthBootstrapUid == incomingUid) {
      return;
    }
    _lastAuthBootstrapUid = incomingUid;
    unawaited(_runPostAuthBootstrap(incomingUid));
  }

  Future<void> _runPostAuthBootstrap(String uid) async {
    if (uid.trim().isEmpty || _profile.id.trim() != uid.trim()) return;
    if (_firestoreService == null) {
      // Retry bootstrap when Firestore is attached later.
      _lastAuthBootstrapUid = null;
      return;
    }
    await hydrateProfileFromFirestore(uid);
    try {
      await _firestoreService?.resumeDeletingGroupsForAdmin(adminUid: uid);
    } catch (e, st) {
      _recordBackendError(e, st);
    }
    await hydrateCurrentUserHistoryFromFirestore();
    await migrateLocalDataToFirestoreIfNeeded();
    await flushPendingPicksOutbox();
    await PushNotificationsService.instance.initializeForAppState(this);
  }

  Future<void> _applySignedOutAuthStateIfNeeded() async {
    if (_profile.id.trim().isEmpty) return;
    _lastAuthBootstrapUid = null;

    // Only clear identity prefs (id/email).  Profile data prefs (photoUrl,
    // favoriteTeam, teamName, timestamps) are intentionally preserved so they
    // survive transient auth-stream glitches (e.g. idTokenChanges firing null
    // during token refresh).  The explicit signOut() method handles full pref
    // cleanup when the user intentionally signs out.
    _prefs?.remove(_kProfileId);
    _prefs?.remove(_kProfileEmail);

    _profile = _defaultProfile;
    _currentUserProfileSetupCompleted = false;
    _profileLocalUpdatedAtMs = 0;
    _profileLocalFieldUpdatedAtMs = const <String, int>{};
    _resetProfileSyncState();
    _hydratedCurrentUserHistoryKey = null;
    _historyHydrationQueued = false;
    _cancelStandingsStream();
    await groupState.clearAll();
    predictionState.clearAllHistory();
    await _prefs?.remove(_kPendingPicksOutboxScoped);
    notifyListeners();
  }

  static Map<String, int> _decodeProfileFieldUpdateMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, int>{};
      final out = <String, int>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty) continue;
        final value = (entry.value as num?)?.toInt();
        if (value == null || value <= 0) continue;
        out[key] = value;
      }
      return Map<String, int>.unmodifiable(out);
    } catch (_) {
      return const <String, int>{};
    }
  }

  Future<void> _persistProfileFieldUpdateMap() async {
    final prefs = _prefs;
    if (prefs == null) return;
    if (_profileLocalFieldUpdatedAtMs.isEmpty) {
      await prefs.remove(_kProfileLocalFieldUpdatedAtMs);
      return;
    }
    await prefs.setString(
      _kProfileLocalFieldUpdatedAtMs,
      jsonEncode(_profileLocalFieldUpdatedAtMs),
    );
  }

  int _localProfileUpdatedAtForField(String fieldKey) {
    final fromField = _profileLocalFieldUpdatedAtMs[fieldKey];
    if (fromField != null && fromField > 0) return fromField;
    return _profileLocalUpdatedAtMs;
  }

  bool _isRemoteProfileFieldNewer(int? remoteUpdatedAtMs, String fieldKey) {
    if (remoteUpdatedAtMs == null) return false;
    return remoteUpdatedAtMs > _localProfileUpdatedAtForField(fieldKey);
  }

  Future<void> _markLocalProfileUpdatedNow([String? fieldKey]) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _profileLocalUpdatedAtMs = nowMs;
    if (fieldKey != null && fieldKey.trim().isNotEmpty) {
      _profileLocalFieldUpdatedAtMs = {
        ..._profileLocalFieldUpdatedAtMs,
        fieldKey.trim(): nowMs,
      };
    }
    await _prefs?.setInt(_kProfileLocalUpdatedAtMs, _profileLocalUpdatedAtMs);
    if (fieldKey != null && fieldKey.trim().isNotEmpty) {
      await _persistProfileFieldUpdateMap();
    }
  }

  void _markRemoteFieldApplied(String fieldKey, int remoteUpdatedAtMs) {
    _profileLocalFieldUpdatedAtMs = {
      ..._profileLocalFieldUpdatedAtMs,
      fieldKey: remoteUpdatedAtMs,
    };
  }

  int? _extractRemoteProfileUpdatedAtMs(Map<String, dynamic> data) {
    final raw = data['updatedAt'];
    if (raw is DateTime) return raw.millisecondsSinceEpoch;
    if (raw is Timestamp) return raw.toDate().millisecondsSinceEpoch;
    return null;
  }

  /// Merge profilo letto da Firestore con stato locale.
  /// Usato all'avvio per ripristinare dati da cloud su device nuovo.
  void mergeFirestoreProfile(Map<String, dynamic> data) {
    bool changed = false;
    final remoteUpdatedAtMs = _extractRemoteProfileUpdatedAtMs(data);

    final remoteDisplayName = data['displayName'] as String?;
    if (remoteDisplayName != null) {
      final sanitized = UserProfile.sanitizeDisplayName(remoteDisplayName);
      final remoteIsNewer = _isRemoteProfileFieldNewer(
        remoteUpdatedAtMs,
        _kProfileFieldDisplayName,
      );
      if (sanitized.isNotEmpty &&
          (remoteIsNewer || _profile.displayName.trim().isEmpty) &&
          sanitized != _profile.displayName) {
        _profile = _profile.copyWith(displayName: sanitized);
        _prefs?.setString(_kProfileDisplayName, sanitized);
        if (remoteUpdatedAtMs != null) {
          _markRemoteFieldApplied(_kProfileFieldDisplayName, remoteUpdatedAtMs);
        }
        changed = true;
      }
    }

    final remoteTeamName = data['teamName'] as String?;
    if (remoteTeamName != null && remoteTeamName.trim().isNotEmpty) {
      final normalizedRemote = UserProfile.normalizeHandle(remoteTeamName);
      final remoteIsNewer = _isRemoteProfileFieldNewer(
        remoteUpdatedAtMs,
        _kProfileFieldTeamName,
      );
      if ((remoteIsNewer || _profile.teamName == _defaultProfile.teamName) &&
          normalizedRemote != _profile.teamName) {
        _profile = _profile.copyWith(teamName: normalizedRemote);
        _prefs?.setString(_kProfileTeamName, normalizedRemote);
        if (remoteUpdatedAtMs != null) {
          _markRemoteFieldApplied(_kProfileFieldTeamName, remoteUpdatedAtMs);
        }
        changed = true;
      }
    }

    final remoteFavoriteTeam = data['favoriteTeam'] as String?;
    final sanitizedFav = UserProfile.sanitizeFavoriteTeam(remoteFavoriteTeam);
    final remoteIsNewerFavorite = _isRemoteProfileFieldNewer(
      remoteUpdatedAtMs,
      _kProfileFieldFavoriteTeam,
    );
    if (sanitizedFav != null &&
        (remoteIsNewerFavorite || _profile.favoriteTeam == null) &&
        sanitizedFav != _profile.favoriteTeam) {
      _profile = _profile.copyWith(favoriteTeam: sanitizedFav);
      _prefs?.setString(_kProfileFavoriteTeam, sanitizedFav);
      if (remoteUpdatedAtMs != null) {
        _markRemoteFieldApplied(_kProfileFieldFavoriteTeam, remoteUpdatedAtMs);
      }
      changed = true;
    }

    final remotePhotoUrl = data['photoUrl'] as String?;
    if (remotePhotoUrl != null && remotePhotoUrl.trim().isNotEmpty) {
      final normalizedRemotePhoto = _normalizePersistedImageReference(
        remotePhotoUrl,
      );
      final remoteIsNewer = _isRemoteProfileFieldNewer(
        remoteUpdatedAtMs,
        _kProfileFieldPhotoUrl,
      );
      if ((remoteIsNewer || (_profile.photoUrl ?? '').trim().isEmpty) &&
          _profile.photoUrl != normalizedRemotePhoto) {
        _profile = _profile.copyWith(photoUrl: normalizedRemotePhoto);
        _prefs?.setString(_kProfilePhotoUrl, normalizedRemotePhoto);
        if (remoteUpdatedAtMs != null) {
          _markRemoteFieldApplied(_kProfileFieldPhotoUrl, remoteUpdatedAtMs);
        }
        changed = true;
      }
    }

    final remoteLang = data['language'] as String?;
    final remoteIsNewerLanguage = _isRemoteProfileFieldNewer(
      remoteUpdatedAtMs,
      _kProfileFieldLanguage,
    );
    if (remoteLang != null && remoteIsNewerLanguage) {
      final parsed = cassandraLanguageFromStorage(remoteLang);
      if (parsed != _language) {
        _language = parsed;
        _prefs?.setString(_kLanguage, remoteLang);
        if (remoteUpdatedAtMs != null) {
          _markRemoteFieldApplied(_kProfileFieldLanguage, remoteUpdatedAtMs);
        }
        changed = true;
      }
    }

    final remoteVis = data['defaultVisibility'] as String?;
    final remoteIsNewerVisibility = _isRemoteProfileFieldNewer(
      remoteUpdatedAtMs,
      _kProfileFieldDefaultVisibility,
    );
    if (remoteVis != null && remoteIsNewerVisibility) {
      final parsed = predictionVisibilityFromStorage(remoteVis);
      if (parsed != _defaultVisibility) {
        _defaultVisibility = parsed;
        _prefs?.setString(_kDefaultVisibility, remoteVis);
        if (remoteUpdatedAtMs != null) {
          _markRemoteFieldApplied(
            _kProfileFieldDefaultVisibility,
            remoteUpdatedAtMs,
          );
        }
        changed = true;
      }
    }

    final previousActiveGroupId = groupState.activeGroupId;
    // Restore groupIds for multi-group support.  parseGroupIds is used instead
    // of a direct cast so corrupt / mixed-type arrays don't throw CastError.
    final remoteGroupIds = parseGroupIds(data['groupIds']);
    if (remoteGroupIds != null) {
      groupState.setFirestoreGroupIds(remoteGroupIds);
      changed = true;
    }

    if (changed) notifyListeners();

    if ((remoteGroupIds?.isNotEmpty ?? false) &&
        (groupState.groupName == null || groupState.groupInviteCode == null)) {
      unawaited(
        refreshActiveGroupMetadataFromFirestore().catchError((
          Object e,
          StackTrace st,
        ) {
          _recordBackendError(e, st);
        }),
      );
    }

    if (remoteGroupIds != null &&
        previousActiveGroupId != groupState.activeGroupId) {
      _triggerHistoryHydrationWithRetry();
    }

    if (remoteUpdatedAtMs != null &&
        remoteUpdatedAtMs > _profileLocalUpdatedAtMs) {
      _profileLocalUpdatedAtMs = remoteUpdatedAtMs;
      unawaited(_prefs?.setInt(_kProfileLocalUpdatedAtMs, remoteUpdatedAtMs));
    }
    if (remoteUpdatedAtMs != null) {
      unawaited(_persistProfileFieldUpdateMap());
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

  Timer? _profileSyncDebounceTimer;
  Timer? _profileSyncRetryTimer;
  bool _profileSyncDirty = false;
  bool _profileSyncLoopRunning = false;
  int _profileSyncRetryAttempt = 0;
  String? _lastProfileSyncFingerprint;
  String? _profileHydrationPendingUid;
  String? _profileHydrationCompletedUid;
  String? _lastBackendSyncError;
  DateTime? _lastBackendSyncErrorAt;
  int _consecutiveSyncFailures = 0;
  bool _didRepairMembership = false;

  /// Number of consecutive sync failures required before the offline banner
  /// is shown. With a 30-second sync interval this means ~60 s of sustained
  /// failures before the user sees the banner — enough to ignore transient
  /// hiccups while still surfacing real connectivity problems quickly.
  static const int _syncFailureThreshold = 2;

  StreamSubscription<List<ApiFootballStanding>>? _standingsSubscription;

  String? get lastBackendSyncError => _lastBackendSyncError;
  DateTime? get lastBackendSyncErrorAt => _lastBackendSyncErrorAt;
  bool get hasBackendSyncError =>
      _lastBackendSyncError != null &&
      _consecutiveSyncFailures >= _syncFailureThreshold;

  void _recordBackendError(Object error, [StackTrace? st]) {
    _consecutiveSyncFailures++;
    final message = error.toString();
    _lastBackendSyncError = message;
    _lastBackendSyncErrorAt = DateTime.now();
    if (kDebugMode) {
      debugPrint(
        '[backend-sync] failure $_consecutiveSyncFailures/$_syncFailureThreshold: $message',
      );
      if (st != null) debugPrint('$st');
    }
    // Only notify (and potentially show the banner) when the threshold is
    // reached or already exceeded.  Before that the UI stays unchanged.
    if (_consecutiveSyncFailures >= _syncFailureThreshold) {
      notifyListeners();
    }
  }

  void _clearBackendError() {
    final hadVisibleError =
        _lastBackendSyncError != null &&
        _consecutiveSyncFailures >= _syncFailureThreshold;
    _lastBackendSyncError = null;
    _lastBackendSyncErrorAt = null;
    _consecutiveSyncFailures = 0;
    if (hadVisibleError) {
      notifyListeners();
    }
  }

  void markBackendSyncError(Object error, [StackTrace? st]) {
    _recordBackendError(error, st);
  }

  void clearBackendSyncError() {
    _clearBackendError();
  }

  String _profileSyncFingerprint() {
    final sortedGroupIds = [...groupState.firestoreGroupIds]..sort();
    return [
      _profile.id.trim(),
      _profile.displayName.trim(),
      _profile.teamName.trim(),
      _profile.favoriteTeam?.trim() ?? '',
      _profile.email?.trim() ?? '',
      _profile.photoUrl?.trim() ?? '',
      _language.name,
      _defaultVisibility.name,
      '$currentUserAvatarSeed',
      sortedGroupIds.join(','),
    ].join('|');
  }

  bool _isProfileHydrationPendingForUid(String uid) {
    final cleaned = uid.trim();
    if (cleaned.isEmpty) return false;
    return _profileHydrationPendingUid == cleaned;
  }

  void _markProfileHydrationPending(String uid) {
    final cleaned = uid.trim();
    if (cleaned.isEmpty) return;
    _profileHydrationPendingUid = cleaned;
    if (_profileHydrationCompletedUid != cleaned) {
      _profileHydrationCompletedUid = null;
    }
  }

  void _markProfileHydrationCompleted(String uid) {
    final cleaned = uid.trim();
    if (cleaned.isEmpty) return;
    if (_profileHydrationPendingUid == cleaned) {
      _profileHydrationPendingUid = null;
    }
    _profileHydrationCompletedUid = cleaned;
    if (_profile.id.trim() == cleaned && _profileSyncDirty) {
      _profileSyncRetryTimer?.cancel();
      _profileSyncRetryTimer = null;
      _profileSyncRetryAttempt = 0;
      _scheduleProfileSyncStart(Duration.zero);
    }
  }

  void _clearProfileHydrationState() {
    _profileHydrationPendingUid = null;
    _profileHydrationCompletedUid = null;
  }

  void _resetProfileSyncState({bool clearHydration = true}) {
    _profileSyncDebounceTimer?.cancel();
    _profileSyncDebounceTimer = null;
    _profileSyncRetryTimer?.cancel();
    _profileSyncRetryTimer = null;
    _profileSyncDirty = false;
    _profileSyncRetryAttempt = 0;
    _lastProfileSyncFingerprint = null;
    _didRepairMembership = false;
    if (clearHydration) {
      _clearProfileHydrationState();
    }
  }

  void _scheduleProfileSyncStart(Duration delay) {
    _profileSyncDebounceTimer?.cancel();
    _profileSyncDebounceTimer = Timer(delay, _startProfileSyncLoopIfNeeded);
  }

  Duration _profileSyncRetryBackoffForAttempt(int attempt) {
    final multiplier = 1 << (attempt > 0 ? attempt - 1 : 0);
    final delayMs = _kProfileSyncRetryDelay.inMilliseconds * multiplier;
    final maxMs = _kProfileSyncRetryMaxDelay.inMilliseconds;
    return Duration(milliseconds: delayMs > maxMs ? maxMs : delayMs);
  }

  void _scheduleProfileSyncRetry() {
    _profileSyncRetryTimer?.cancel();
    final delay = _profileSyncRetryBackoffForAttempt(_profileSyncRetryAttempt);
    _profileSyncRetryTimer = Timer(delay, () {
      _profileSyncRetryTimer = null;
      _startProfileSyncLoopIfNeeded();
    });
  }

  void _startProfileSyncLoopIfNeeded() {
    if (_profileSyncLoopRunning || !_profileSyncDirty) return;
    _profileSyncLoopRunning = true;
    unawaited(_runProfileSyncLoop());
  }

  /// Fire-and-forget (debounced): sync full user profile to Firestore.
  void _syncProfileToFirestore() {
    _profileSyncDirty = true;
    _profileSyncRetryAttempt = 0;
    _profileSyncRetryTimer?.cancel();
    _profileSyncRetryTimer = null;
    _scheduleProfileSyncStart(_kProfileSyncDebounce);
  }

  Future<void> _runProfileSyncLoop() async {
    try {
      while (_profileSyncDirty) {
        _profileSyncDirty = false;
        final shouldRetry = await _flushProfileSyncToFirestore();
        if (shouldRetry) {
          _profileSyncDirty = true;
          _profileSyncRetryAttempt += 1;
          _scheduleProfileSyncRetry();
          return;
        }
        _profileSyncRetryAttempt = 0;
      }
    } finally {
      _profileSyncLoopRunning = false;
      if (_profileSyncDirty && _profileSyncRetryTimer == null) {
        _startProfileSyncLoopIfNeeded();
      }
    }
  }

  Future<bool> _flushProfileSyncToFirestore() async {
    final fs = _firestoreService;
    if (fs == null || !isAuthenticated) {
      return false;
    }
    final uid = _profile.id;
    if (uid.isEmpty) {
      return false;
    }
    if (_isProfileHydrationPendingForUid(uid)) {
      return true;
    }

    final fingerprint = _profileSyncFingerprint();
    if (_lastProfileSyncFingerprint == fingerprint) {
      _clearBackendError();
      return false;
    }

    try {
      await fs.setUserProfile(
        uid: uid,
        profile: _profile,
        language: _language,
        defaultVisibility: _defaultVisibility,
        avatarSeed: currentUserAvatarSeed,
      );

      if (groupState.firestoreGroupIds.isNotEmpty) {
        await fs.updateGroupMemberProfileInGroups(
          uid: uid,
          groupIds: groupState.firestoreGroupIds,
          displayName: _profile.displayName,
          teamName: _profile.teamName,
          avatarSeed: currentUserAvatarSeed,
          favoriteTeam: _profile.favoriteTeam,
          photoUrl: _profile.photoUrl,
        );
      }
      _lastProfileSyncFingerprint = fingerprint;
      _clearBackendError();
      return false;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[profile-sync] failed: $e');
        debugPrint('$st');
      }
      _recordBackendError(e, st);
      return true;
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _idTokenSubscription?.cancel();
    _resetProfileSyncState();
    _cancelStandingsStream();
    groupState.removeListener(notifyListeners);
    predictionState.removeListener(notifyListeners);
    matchdayState.removeListener(notifyListeners);
    groupState.dispose();
    predictionState.dispose();
    matchdayState.dispose();
    super.dispose();
  }

  void _startStandingsStream() {
    _cancelStandingsStream();
    final fs = _firestoreService;
    if (fs == null) return;
    _standingsSubscription = fs
        .streamSeasonStandings(seasonKey: currentSeasonKey)
        .listen(
          (standings) =>
              setCachedSeasonStandings(standings, updatedAt: DateTime.now()),
          onError: (e) {
            if (kDebugMode) debugPrint('[standings stream] error: $e');
          },
        );
  }

  void _cancelStandingsStream() {
    _standingsSubscription?.cancel();
    _standingsSubscription = null;
  }

  Future<void> hydrateProfileFromFirestore([String? uid]) async {
    final fs = _firestoreService;
    final targetUid = uid ?? _profile.id;
    if (fs == null || targetUid.isEmpty) return;
    _markProfileHydrationPending(targetUid);

    try {
      final data = await fs.getUserProfile(targetUid);
      if (_profile.id.trim() != targetUid.trim()) {
        return;
      }
      if (data != null) {
        mergeFirestoreProfile(data);

        // Auto-complete profile setup if already done on another device.
        if (!_currentUserProfileSetupCompleted) {
          final remoteSetupDone =
              data['profileSetupCompleted'] == true;
          final remoteHandle =
              ((data['teamName'] as String?) ?? '').trim();
          final remoteDisplayName =
              ((data['displayName'] as String?) ?? '').trim();
          if (remoteSetupDone ||
              (remoteHandle.isNotEmpty &&
                  remoteHandle != '@cassandra' &&
                  remoteDisplayName.isNotEmpty)) {
            _currentUserProfileSetupCompleted = true;
            await _writeProfileSetupCompletedForUid(targetUid, true);
          }
        }
      }

      // Detect stale duplicate: if a previous Firebase Auth account with the
      // same email was deleted and the user recreated it, an orphan user doc
      // with the old UID still exists.  Migrate its data and clean it up.
      final email = _profile.email?.trim() ?? '';
      if (email.isNotEmpty) {
        final staleUid = await fs.findExistingUidForEmail(
          email: email,
          currentUid: targetUid,
        );
        if (staleUid != null) {
          if (kDebugMode) {
            debugPrint(
              '[hydrate] found stale user doc $staleUid for $email — '
              'migrating data to $targetUid',
            );
          }
          await fs.migrateStaleUserData(
            fromUid: staleUid,
            toUid: targetUid,
            displayName: _profile.displayName,
            teamName: _profile.teamName,
            avatarSeed: currentUserAvatarSeed,
            favoriteTeam: _profile.favoriteTeam,
            photoUrl: _profile.photoUrl,
          );
        }
      }

      if (groupState.firestoreGroupIds.isEmpty) {
        final recoveredGroupIds = await fs.findGroupIdsForMember(targetUid);
        if (recoveredGroupIds.isNotEmpty) {
          final previousActiveGroupId = groupState.activeGroupId;
          groupState.setFirestoreGroupIds(recoveredGroupIds);
          await fs.mergeUserField(targetUid, {'groupIds': recoveredGroupIds});
          notifyListeners();
          if (previousActiveGroupId != groupState.activeGroupId) {
            _triggerHistoryHydrationWithRetry();
          }
        }
      }
      await refreshActiveGroupMetadataFromFirestore();
      await _repairProfilePhotoReferenceIfNeeded();

      // Self-heal group membership: verifies member docs exist for every
      // group the user belongs to and recreates any that are missing.
      // Runs synchronously so the group page has correct membership by the
      // time the user navigates to it.
      if (!_didRepairMembership) {
        _didRepairMembership = true;
        await fs.repairGroupMembershipIfNeeded(
          uid: targetUid,
          displayName: _profile.displayName,
          teamName: _profile.teamName,
          avatarSeed: currentUserAvatarSeed,
          favoriteTeam: _profile.favoriteTeam,
          photoUrl: _profile.photoUrl,
        );
      }
    } catch (e, st) {
      _recordBackendError(e, st);
    } finally {
      final currentUid = _profile.id.trim();
      if (currentUid == targetUid.trim()) {
        _markProfileHydrationCompleted(currentUid);
      } else if (_profileHydrationPendingUid == targetUid.trim()) {
        _profileHydrationPendingUid = null;
      }
    }
  }

  Future<void> refreshActiveGroupMetadataFromFirestore() async {
    final group = await groupState.refreshActiveGroupMetadataFromFirestore(
      isAuthenticated: isAuthenticated,
      firestoreService: _firestoreService,
    );
    if (group != null) {
      await _repairGroupImageReferenceIfNeeded(group);
    }
  }

  /// Fire-and-forget: sync a single field to Firestore.
  void _syncFieldToFirestore(Map<String, dynamic> fields) {
    final fs = _firestoreService;
    if (fs == null || !isAuthenticated) return;
    final uid = _profile.id;
    if (uid.isEmpty) return;
    if (_isProfileHydrationPendingForUid(uid)) {
      _syncProfileToFirestore();
      return;
    }
    final payload = Map<String, dynamic>.from(fields);
    unawaited(
      _runFirestoreWriteWithRetry(
        operation: 'updateUserField',
        action: () => fs.updateUserField(uid, payload),
      ),
    );
  }

  Future<_FirestoreWriteResult> _runFirestoreWriteWithRetryDetailed({
    required String operation,
    required Future<void> Function() action,
  }) async {
    for (var attempt = 1; attempt <= _kFirestoreWriteAttempts; attempt++) {
      try {
        await action();
        _clearBackendError();
        return const _FirestoreWriteResult(success: true);
      } catch (error, stackTrace) {
        final isLastAttempt = attempt >= _kFirestoreWriteAttempts;
        debugPrint(
          '[firestore-write] $operation attempt '
          '$attempt/$_kFirestoreWriteAttempts failed: $error',
        );
        if (kDebugMode) {
          debugPrint('$stackTrace');
        }
        if (isLastAttempt) {
          _recordBackendError(error, stackTrace);
          return _FirestoreWriteResult(
            success: false,
            error: error,
            stackTrace: stackTrace,
          );
        }
        final backoff = Duration(
          milliseconds:
              _kFirestoreWriteRetryBaseDelay.inMilliseconds *
              (1 << (attempt - 1)),
        );
        await Future<void>.delayed(backoff);
      }
    }
    return const _FirestoreWriteResult(success: false);
  }

  Future<bool> _runFirestoreWriteWithRetry({
    required String operation,
    required Future<void> Function() action,
  }) async {
    final result = await _runFirestoreWriteWithRetryDetailed(
      operation: operation,
      action: action,
    );
    return result.success;
  }

  bool get isAuthenticated => _authService?.isSignedIn ?? false;

  /// Serie A season key: agosto-maggio → anno di inizio.
  String get currentSeasonKey {
    final n = clock.now();
    return (n.month >= 8 ? n.year : n.year - 1).toString();
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
  CassandraThemeMode _themeMode;
  PredictionVisibility _defaultVisibility;
  bool _rememberMeEnabled = false;
  bool _currentUserProfileSetupCompleted = false;
  String? _rememberedUid;
  String? _rememberedHandle;
  String? _rememberedPhotoUrl;
  String? _rememberedProvider;
  String? _devicePushToken;
  int _profileLocalUpdatedAtMs = 0;
  Map<String, int> _profileLocalFieldUpdatedAtMs = const <String, int>{};
  bool _flushingPendingPicksOutbox = false;

  int _demoSeed;

  /// Debug override for lock state: null = natural, true = forced lock,
  /// false = forced unlock. Not persisted.
  bool? _debugLockOverride;

  // ===== GRUPPO (delegated to GroupState) =====

  String? get groupName => groupState.groupName;
  String? get groupInviteCode => groupState.groupInviteCode;
  String? get groupImagePath => groupState.groupImagePath;
  bool get groupAdminApproval => groupState.groupAdminApproval;
  bool get hasGroup => groupState.hasGroup;
  String? get activeGroupId => groupState.activeGroupId;

  void setActiveGroupId(String? id) {
    final cleaned = (id ?? '').trim();
    final next = cleaned.isEmpty ? null : cleaned;
    if (next == groupState.activeGroupId) return;

    groupState.setActiveGroupId(next);
    clearMemberPicks();
    clearCurrentUserPicks();
    clearCurrentUserPicksHistory();
    _triggerHistoryHydrationWithRetry();
    unawaited(
      refreshActiveGroupMetadataFromFirestore().catchError((
        Object e,
        StackTrace st,
      ) {
        _recordBackendError(e, st);
      }),
    );
  }

  String _normalizePersistedImageReference(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    final storage = _storageService;
    if (storage != null) {
      return storage.normalizePersistedImageReference(trimmed);
    }
    return StorageService.normalizePersistedReference(trimmed);
  }

  Future<void> updateGroupImagePath(String? path) async {
    final cleaned = (path ?? '').trim();
    final nextRaw = cleaned.isEmpty ? null : cleaned;
    final previous = (groupState.groupImagePath ?? '').trim();
    final fs = _firestoreService;
    final groupId = activeGroupId;
    final remoteWritable = fs != null && isAuthenticated && groupId != null;

    if (nextRaw == null) {
      if (remoteWritable) {
        final writableFs = fs;
        final writableGroupId = groupId;
        final ok = await _runFirestoreWriteWithRetry(
          operation: 'updateGroupImageUrl.clear',
          action: () => writableFs.updateGroupImageUrl(
            groupId: writableGroupId,
            imageUrl: null,
          ),
        );
        if (!ok) return;
      }
      await groupState.updateGroupImagePath(null);
      if (previous.isNotEmpty) {
        unawaited(_bestEffortDeleteStorageObject(previous));
      }
      return;
    }

    final imageRef = await _resolveImageReferenceForUpload(
      source: nextRaw,
      profileUid: null,
      groupId: groupId,
    );
    final next = imageRef == null
        ? nextRaw
        : (imageRef.uploaded
              ? StorageService.toStorageReference(imageRef.storagePath)
              : _normalizePersistedImageReference(imageRef.downloadUrl));

    if (remoteWritable) {
      final writableFs = fs;
      final writableGroupId = groupId;
      final ok = await _runFirestoreWriteWithRetry(
        operation: 'updateGroupImageUrl',
        action: () => writableFs.updateGroupImageUrl(
          groupId: writableGroupId,
          imageUrl: next,
        ),
      );
      if (!ok) {
        if (imageRef?.uploaded == true) {
          unawaited(
            _bestEffortDeleteStorageObject(
              StorageService.toStorageReference(imageRef!.storagePath),
            ),
          );
        }
        return;
      }
    }

    await groupState.updateGroupImagePath(next);

    if (imageRef?.uploaded == true && previous.isNotEmpty && previous != next) {
      unawaited(_bestEffortDeleteStorageObject(previous));
    }
  }

  Future<void> updateGroupAdminApproval(bool value) =>
      groupState.updateGroupAdminApproval(
        value,
        firestoreService: _firestoreService,
      );

  Future<String?> createGroup(String name) =>
      groupState.createGroup(
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
    required CassandraThemeMode themeMode,
    required PredictionVisibility defaultVisibility,
    required GroupState groupStateInstance,
    required PredictionState predictionStateInstance,
    required MatchdayState matchdayStateInstance,
    int demoSeed = 0,
  }) : _profile = profile,
       _language = language,
       _themeMode = themeMode,
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
  CassandraThemeMode get themeMode => _themeMode;
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

  bool? get debugLockOverride => _debugLockOverride;

  void setDebugLockOverride(bool? value) {
    _debugLockOverride = value;
    notifyListeners();
  }

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
    final storedPhotoUrl = StorageService.normalizePersistedReference(
      (prefs.getString(_kProfilePhotoUrl) ?? '').trim(),
    );
    if (storedPhotoUrl.isNotEmpty &&
        storedPhotoUrl != (prefs.getString(_kProfilePhotoUrl) ?? '').trim()) {
      await prefs.setString(_kProfilePhotoUrl, storedPhotoUrl);
    }

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
          : UserProfile.normalizeHandle(storedTeamName),
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
    final themeMode = cassandraThemeModeFromStorage(
      prefs.getString(_kThemeMode),
    );
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
    final normalizedRememberedPhotoUrl =
        StorageService.normalizePersistedReference(rememberedPhotoUrl);
    if (rememberedPhotoUrl.isNotEmpty &&
        normalizedRememberedPhotoUrl != rememberedPhotoUrl) {
      await prefs.setString(_kRememberedPhotoUrl, normalizedRememberedPhotoUrl);
    }
    final rememberedProvider = (prefs.getString(_kRememberedProvider) ?? '')
        .trim()
        .toLowerCase();
    final storedPushToken = (prefs.getString(_kDevicePushToken) ?? '').trim();
    final profileLocalUpdatedAtMs =
        prefs.getInt(_kProfileLocalUpdatedAtMs) ?? 0;
    final profileLocalFieldUpdatedAtMs = _decodeProfileFieldUpdateMap(
      prefs.getString(_kProfileLocalFieldUpdatedAtMs),
    );
    final profileSetupCompleted = storedId.isNotEmpty
        ? (prefs.getBool(_profileSetupCompletedKeyForUid(storedId)) ?? false)
        : false;

    return AppState._(
        prefs,
        profile: profile,
        language: language,
        themeMode: themeMode,
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
          : normalizedRememberedPhotoUrl
      .._rememberedProvider =
          (rememberedProvider == 'google' || rememberedProvider == 'apple')
          ? rememberedProvider
          : null
      .._devicePushToken = storedPushToken.isEmpty ? null : storedPushToken
      .._profileLocalUpdatedAtMs = profileLocalUpdatedAtMs
      .._profileLocalFieldUpdatedAtMs = profileLocalFieldUpdatedAtMs
      .._currentUserProfileSetupCompleted = profileSetupCompleted;
  }

  /// In-memory (per i test)
  factory AppState.inMemory({
    UserProfile? profile,
    CassandraLanguage language = CassandraLanguage.system,
    CassandraThemeMode themeMode = CassandraThemeMode.system,
    PredictionVisibility defaultVisibility = PredictionVisibility.friends,
  }) {
    return AppState._(
      null,
      profile: profile ?? _defaultProfile,
      language: language,
      themeMode: themeMode,
      defaultVisibility: defaultVisibility,
      groupStateInstance: GroupState.inMemory(),
      predictionStateInstance: PredictionState.inMemory(),
      matchdayStateInstance: MatchdayState.inMemory(),
      demoSeed: 0,
    );
  }

  Future<void> updateTeamName(String value) async {
    final normalized = UserProfile.normalizeHandle(value);
    if (normalized == _profile.teamName) return;

    _profile = _profile.copyWith(teamName: normalized);
    notifyListeners();

    await _prefs?.setString(_kProfileTeamName, normalized);
    // scrivo anche la legacy per compatibilità
    await _prefs?.setString(_kTeamNameLegacy, normalized);
    await _markLocalProfileUpdatedNow(_kProfileFieldTeamName);
    await _syncRememberedIdentityFromProfile();
    _syncProfileToFirestore();
  }

  Future<void> updateDisplayName(String value) async {
    final cleaned = UserProfile.sanitizeDisplayName(value);
    if (cleaned.isEmpty) return;
    if (cleaned == _profile.displayName) return;

    _profile = _profile.copyWith(displayName: cleaned);
    notifyListeners();

    await _prefs?.setString(_kProfileDisplayName, cleaned);
    await _markLocalProfileUpdatedNow(_kProfileFieldDisplayName);
    await _syncRememberedIdentityFromProfile();
    _syncProfileToFirestore();
  }

  Future<void> updateProfilePhotoPath(String? path) async {
    final cleaned = (path ?? '').trim();
    final nextRaw = cleaned.isEmpty ? null : cleaned;
    final current = (_profile.photoUrl ?? '').trim();
    if (nextRaw != null && nextRaw == current) return;

    final fs = _firestoreService;
    final uid = _profile.id.trim();
    final remoteWritable = fs != null && isAuthenticated && uid.isNotEmpty;

    if (nextRaw == null) {
      if (remoteWritable) {
        final writableFs = fs;
        final ok = await _runFirestoreWriteWithRetry(
          operation: 'updateUserField.photoUrl.clear',
          action: () => writableFs.updateUserField(uid, {'photoUrl': null}),
        );
        if (!ok) return;
      }

      _profile = _profile.copyWith(clearPhotoUrl: true);
      notifyListeners();
      await _prefs?.remove(_kProfilePhotoUrl);
      await _markLocalProfileUpdatedNow(_kProfileFieldPhotoUrl);
      await _syncRememberedIdentityFromProfile();
      _syncProfileToFirestore();
      if (current.isNotEmpty) {
        unawaited(_bestEffortDeleteStorageObject(current));
      }
      return;
    }

    final uploaded = await _resolveImageReferenceForUpload(
      source: nextRaw,
      profileUid: uid,
      groupId: null,
    );
    final next = uploaded == null
        ? nextRaw
        : (uploaded.uploaded
              ? StorageService.toStorageReference(uploaded.storagePath)
              : _normalizePersistedImageReference(uploaded.downloadUrl));
    if (next == current) return;

    if (remoteWritable) {
      final writableFs = fs;
      final ok = await _runFirestoreWriteWithRetry(
        operation: 'updateUserField.photoUrl',
        action: () => writableFs.updateUserField(uid, {'photoUrl': next}),
      );
      if (!ok) {
        if (uploaded?.uploaded == true) {
          unawaited(
            _bestEffortDeleteStorageObject(
              StorageService.toStorageReference(uploaded!.storagePath),
            ),
          );
        }
        return;
      }
    }

    _profile = _profile.copyWith(photoUrl: next);
    notifyListeners();

    await _prefs?.setString(_kProfilePhotoUrl, next);
    await _markLocalProfileUpdatedNow(_kProfileFieldPhotoUrl);
    await _syncRememberedIdentityFromProfile();
    _syncProfileToFirestore();

    if (uploaded?.uploaded == true && current.isNotEmpty && current != next) {
      unawaited(_bestEffortDeleteStorageObject(current));
    }
  }

  Future<void> updateFavoriteTeam(String value) async {
    final stored = UserProfile.sanitizeFavoriteTeam(value);

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
    await _markLocalProfileUpdatedNow(_kProfileFieldFavoriteTeam);
    _syncProfileToFirestore();
  }

  Future<void> updateLanguage(CassandraLanguage value) async {
    if (value == _language) return;
    _language = value;
    notifyListeners();
    await _prefs?.setString(_kLanguage, cassandraLanguageToStorage(value));
    await _markLocalProfileUpdatedNow(_kProfileFieldLanguage);
    _syncFieldToFirestore({'language': cassandraLanguageToStorage(value)});
  }

  Future<void> updateThemeMode(CassandraThemeMode value) async {
    if (value == _themeMode) return;
    _themeMode = value;
    notifyListeners();
    await _prefs?.setString(_kThemeMode, cassandraThemeModeToStorage(value));
  }

  Future<void> updateDefaultVisibility(PredictionVisibility value) async {
    if (value == _defaultVisibility) return;
    _defaultVisibility = value;
    notifyListeners();
    await _prefs?.setString(
      _kDefaultVisibility,
      predictionVisibilityToStorage(value),
    );
    await _markLocalProfileUpdatedNow(_kProfileFieldDefaultVisibility);
    _syncFieldToFirestore({
      'defaultVisibility': predictionVisibilityToStorage(value),
    });
  }

  Future<void> setDevicePushToken(String token) async {
    final cleaned = token.trim();
    if (cleaned.isEmpty) return;

    final previous = _devicePushToken;
    final changed = cleaned != _devicePushToken;

    if (changed) {
      _devicePushToken = cleaned;
      await _prefs?.setString(_kDevicePushToken, cleaned);
    }

    final fs = _firestoreService;
    final uid = _profile.id.trim();
    if (fs == null || !isAuthenticated || uid.isEmpty) return;

    // Remove stale token best-effort so it does not block new registration.
    if (changed && previous != null && previous.isNotEmpty) {
      unawaited(
        _runFirestoreWriteWithRetry(
          operation: 'removeUserFcmToken',
          action: () => fs.removeUserFcmToken(uid: uid, token: previous),
        ),
      );
    }
    // Always sync to Firestore — arrayUnion is idempotent, so re-registering
    // the same token is safe and covers the case where a previous Firestore
    // write was skipped (e.g. auth/service not ready on first attempt).
    unawaited(
      _runFirestoreWriteWithRetry(
        operation: 'addUserFcmToken',
        action: () => fs.addUserFcmToken(uid: uid, token: cleaned),
      ),
    );
  }

  void setProfileFromFirebaseUser(User user) {
    final previousPersistedUid = (_prefs?.getString(_kProfileId) ?? '').trim();
    final nextUid = user.uid.trim();
    _lastProfileSyncFingerprint = null;
    _markProfileHydrationPending(nextUid);
    final accountSwitched =
        previousPersistedUid.isEmpty || previousPersistedUid != nextUid;
    if (accountSwitched) {
      // Prevent cross-account cache contamination on shared devices.
      predictionState.clearAllHistory();
      _hydratedCurrentUserHistoryKey = null;
    }

    final existingTeamName =
        _prefs?.getString(_kProfileTeamName) ??
        _prefs?.getString(_kTeamNameLegacy);
    final existingFavoriteTeam =
        _prefs?.getString(_kProfileFavoriteTeam) ??
        _prefs?.getString(_kFavoriteTeamLegacy);
    final existingPhotoUrlRaw =
        _prefs?.getString(_kProfilePhotoUrl) ?? _profile.photoUrl;
    final existingPhotoUrl = _normalizePersistedImageReference(
      (existingPhotoUrlRaw ?? '').trim(),
    );

    _profile = UserProfile.fromFirebaseUser(
      user,
      existingTeamName: existingTeamName,
      existingFavoriteTeam: existingFavoriteTeam,
      existingPhotoUrl: existingPhotoUrl.isEmpty ? null : existingPhotoUrl,
    );
    // Preserve field timestamps when re-authenticating the same account so the
    // Firestore merge correctly knows which values are newer.  Only reset
    // timestamps on a genuine account switch where old timestamps are invalid.
    if (accountSwitched) {
      _profileLocalUpdatedAtMs = 0;
      _profileLocalFieldUpdatedAtMs = const <String, int>{};
    } else {
      final loadedFieldMap = _decodeProfileFieldUpdateMap(
        _prefs?.getString(_kProfileLocalFieldUpdatedAtMs),
      );
      if (loadedFieldMap.isNotEmpty) {
        _profileLocalFieldUpdatedAtMs = loadedFieldMap;
      }
      final loadedGlobalTs = _prefs?.getInt(_kProfileLocalUpdatedAtMs) ?? 0;
      if (loadedGlobalTs > 0) {
        _profileLocalUpdatedAtMs = loadedGlobalTs;
      } else {
        _profileLocalUpdatedAtMs = 0;
      }
    }
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
    if (_profile.teamName.isNotEmpty) {
      _prefs?.setString(_kProfileTeamName, _profile.teamName);
    }
    if (_profile.favoriteTeam != null) {
      _prefs?.setString(_kProfileFavoriteTeam, _profile.favoriteTeam!);
    }
    _prefs?.setInt(_kProfileLocalUpdatedAtMs, _profileLocalUpdatedAtMs);
    if (accountSwitched) {
      _prefs?.remove(_kProfileLocalFieldUpdatedAtMs);
    }

    if (_rememberMeEnabled) {
      unawaited(_syncRememberedIdentityFromProfile());
    }

    _syncProfileToFirestore();
    _triggerHistoryHydrationWithRetry();
    _startStandingsStream();
    final token = _devicePushToken;
    if (token != null && token.trim().isNotEmpty) {
      final fs = _firestoreService;
      if (fs == null) {
        if (kDebugMode) {
          debugPrint(
            '[push] skipped token registration: firestore unavailable',
          );
        }
      } else {
        unawaited(
          _runFirestoreWriteWithRetry(
            operation: 'addUserFcmToken',
            action: () => fs.addUserFcmToken(uid: user.uid, token: token),
          ),
        );
      }
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    final token = _devicePushToken;
    final uid = _profile.id.trim();
    final scopedOutboxKey = _scopedHistoryKey(
      _kPendingPicksOutbox,
      uid: uid,
      seasonKey: currentSeasonKey,
    );
    final fs = _firestoreService;
    if (token != null && token.isNotEmpty && uid.isNotEmpty && fs != null) {
      await _runFirestoreWriteWithRetry(
        operation: 'removeUserFcmToken',
        action: () => fs.removeUserFcmToken(uid: uid, token: token),
      );
    }

    await _authService?.signOut();
    await forgetRememberedIdentity();
    _lastAuthBootstrapUid = null;

    _prefs?.remove(_kProfileId);
    _prefs?.remove(_kProfileDisplayName);
    _prefs?.remove(_kProfileEmail);
    // Preserve photoUrl, teamName, and favoriteTeam across re-login so the
    // profile is visually intact before Firestore hydration completes.
    // These are overwritten by mergeFirestoreProfile when a different account
    // logs in.
    _prefs?.remove(_kTeamNameLegacy);
    _prefs?.remove(_kFavoriteTeamLegacy);
    _prefs?.remove(_kProfileLocalUpdatedAtMs);
    _prefs?.remove(_kProfileLocalFieldUpdatedAtMs);
    _prefs?.remove(scopedOutboxKey);

    _profile = _defaultProfile;
    _currentUserProfileSetupCompleted = false;
    _profileLocalUpdatedAtMs = 0;
    _profileLocalFieldUpdatedAtMs = const <String, int>{};
    _resetProfileSyncState();
    await groupState.clearAll();
    predictionState.clearAllHistory();
    _cancelStandingsStream();
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    final token = _devicePushToken;
    final uid = _profile.id.trim();
    final scopedOutboxKey = _scopedHistoryKey(
      _kPendingPicksOutbox,
      uid: uid,
      seasonKey: currentSeasonKey,
    );
    final fs = _firestoreService;
    if (token != null && token.isNotEmpty && uid.isNotEmpty && fs != null) {
      await _runFirestoreWriteWithRetry(
        operation: 'removeUserFcmToken',
        action: () => fs.removeUserFcmToken(uid: uid, token: token),
      );
    }

    await _authService?.deleteAccount();
    await forgetRememberedIdentity();
    _lastAuthBootstrapUid = null;

    _prefs?.remove(_kProfileId);
    _prefs?.remove(_kProfileDisplayName);
    _prefs?.remove(_kProfileEmail);
    _prefs?.remove(_kProfilePhotoUrl);
    _prefs?.remove(_kProfileLocalUpdatedAtMs);
    _prefs?.remove(_kProfileLocalFieldUpdatedAtMs);
    _prefs?.remove(scopedOutboxKey);

    _cancelStandingsStream();
    await groupState.clearAll();

    await resetAll();
    _resetProfileSyncState();
    notifyListeners();
  }

  Future<void> resetAll() async {
    final scopedUid = _profile.id.trim();
    final scopedSeason = currentSeasonKey;

    _profile = _defaultProfile;
    _language = CassandraLanguage.system;
    _themeMode = CassandraThemeMode.system;
    _defaultVisibility = PredictionVisibility.friends;
    _profileLocalUpdatedAtMs = 0;
    _profileLocalFieldUpdatedAtMs = const <String, int>{};
    await groupState.clearAll();
    predictionState.clearAllHistory();
    _rememberMeEnabled = false;
    _currentUserProfileSetupCompleted = false;
    _rememberedUid = null;
    _rememberedHandle = null;
    _rememberedPhotoUrl = null;
    _rememberedProvider = null;
    _resetProfileSyncState();
    notifyListeners();

    if (_prefs == null) return;

    await _prefs.remove(_kProfileTeamName);
    await _prefs.remove(_kProfileFavoriteTeam);

    await _prefs.remove(_kTeamNameLegacy);
    await _prefs.remove(_kFavoriteTeamLegacy);

    await _prefs.remove(_kLanguage);
    await _prefs.remove(_kThemeMode);
    await _prefs.remove(_kDefaultVisibility);

    await _prefs.remove(_kRememberMeEnabled);
    await _prefs.remove(_kRememberedUid);
    await _prefs.remove(_kRememberedHandle);
    await _prefs.remove(_kRememberedPhotoUrl);
    await _prefs.remove(_kRememberedProvider);
    await _prefs.remove(_kProfileLocalUpdatedAtMs);
    await _prefs.remove(_kProfileLocalFieldUpdatedAtMs);
    await _prefs.remove(
      _scopedHistoryKey(
        _kPendingPicksOutbox,
        uid: scopedUid,
        seasonKey: scopedSeason,
      ),
    );
    await _prefs.remove(
      _scopedHistoryKey(
        _kCurrentUserPicksByMatchday,
        uid: scopedUid,
        seasonKey: scopedSeason,
      ),
    );
    await _prefs.remove(
      _scopedHistoryKey(
        _kPredictionOutcomesByMatchday,
        uid: scopedUid,
        seasonKey: scopedSeason,
      ),
    );
    await _prefs.remove(
      _scopedHistoryKey(
        _kMatchdayMatchesByDayV1,
        uid: scopedUid,
        seasonKey: scopedSeason,
      ),
    );
    await _prefs.remove(
      _scopedHistoryKey(
        _kFirestoreMigrationV1Done,
        uid: scopedUid,
        seasonKey: scopedSeason,
      ),
    );
    // Backward-compat cleanup for older global keys.
    await _prefs.remove(_kCurrentUserPicksByMatchday);
    await _prefs.remove(_kPendingPicksOutbox);
    await _prefs.remove(_kPredictionOutcomesByMatchday);
    await _prefs.remove(_kMatchdayMatchesByDayV1);
    await _prefs.remove(_kFirestoreMigrationV1Done);
  }

  bool _hydratingCurrentUserHistoryFromFirestore = false;
  String? _hydratedCurrentUserHistoryKey;
  String? _lastHistoryHydrationError;
  DateTime? _lastHistoryHydrationAttemptAt;
  bool _historyHydrationLoopRunning = false;
  bool _historyHydrationQueued = false;

  bool get isHydratingCurrentUserHistoryFromFirestore =>
      _hydratingCurrentUserHistoryFromFirestore;
  String? get lastHistoryHydrationError => _lastHistoryHydrationError;
  DateTime? get lastHistoryHydrationAttemptAt => _lastHistoryHydrationAttemptAt;

  void _triggerHistoryHydrationWithRetry() {
    _historyHydrationQueued = true;
    if (_historyHydrationLoopRunning) return;
    _historyHydrationLoopRunning = true;
    unawaited(_runHistoryHydrationLoop());
  }

  Future<void> _runHistoryHydrationLoop() async {
    try {
      while (_historyHydrationQueued) {
        _historyHydrationQueued = false;

        // Serializza le hydration anche quando una chiamata diretta
        // (es. login flow) è già in corso.
        while (_hydratingCurrentUserHistoryFromFirestore) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }

        await _hydrateCurrentUserHistoryWithRetry();
      }
    } finally {
      _historyHydrationLoopRunning = false;
      if (_historyHydrationQueued) {
        _triggerHistoryHydrationWithRetry();
      }
    }
  }

  Future<void> _hydrateCurrentUserHistoryWithRetry() async {
    for (var attempt = 1; attempt <= _kHistoryHydrationAttempts; attempt++) {
      try {
        await hydrateCurrentUserHistoryFromFirestore(
          force: attempt > 1,
          throwOnError: true,
        ).timeout(_kHistoryHydrationTimeout);
        return;
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[history-hydration] attempt $attempt failed: $e');
          debugPrint('$st');
        }
        if (attempt >= _kHistoryHydrationAttempts) return;
        final multiplier = 1 << (attempt - 1);
        final backoffMs =
            _kHistoryHydrationRetryBaseDelay.inMilliseconds * multiplier;
        final maxMs = _kHistoryHydrationRetryMaxDelay.inMilliseconds;
        await Future<void>.delayed(
          Duration(milliseconds: backoffMs > maxMs ? maxMs : backoffMs),
        );
      }
    }
  }

  List<_PendingPicksSubmission> _loadPendingPicksOutbox() {
    final raw = _prefs?.getString(_kPendingPicksOutboxScoped);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final entries = <_PendingPicksSubmission>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final parsed = _PendingPicksSubmission.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (parsed != null) entries.add(parsed);
      }
      return entries;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[picks-outbox] failed to parse outbox: $e');
        debugPrint('$st');
      }
      return const [];
    }
  }

  Future<void> _savePendingPicksOutbox(
    List<_PendingPicksSubmission> entries,
  ) async {
    final prefs = _prefs;
    if (prefs == null) return;
    if (entries.isEmpty) {
      await prefs.remove(_kPendingPicksOutboxScoped);
      return;
    }
    await prefs.setString(
      _kPendingPicksOutboxScoped,
      jsonEncode(entries.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  bool _sameOutboxScope(
    _PendingPicksSubmission entry, {
    required int dayNumber,
    required String? groupId,
  }) {
    final normalizedGroup = (groupId ?? '').trim();
    final entryGroup = (entry.groupId ?? '').trim();
    return entry.dayNumber == dayNumber && entryGroup == normalizedGroup;
  }

  Future<void> _enqueuePendingPicksSubmission({
    required int dayNumber,
    required Map<String, PickOption> picksByMatchId,
    required String visibility,
    required String? groupId,
  }) async {
    final current = _loadPendingPicksOutbox();
    final next = <_PendingPicksSubmission>[];
    for (final entry in current) {
      if (_sameOutboxScope(entry, dayNumber: dayNumber, groupId: groupId)) {
        continue;
      }
      next.add(entry);
    }
    next.add(
      _PendingPicksSubmission(
        dayNumber: dayNumber,
        picksByMatchId: Map<String, PickOption>.from(picksByMatchId),
        visibility: visibility,
        groupId: (groupId ?? '').trim().isEmpty ? null : groupId!.trim(),
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _savePendingPicksOutbox(next);
  }

  Future<void> _removePendingPicksSubmission({
    required int dayNumber,
    required String? groupId,
  }) async {
    final current = _loadPendingPicksOutbox();
    final next = current
        .where(
          (entry) =>
              !_sameOutboxScope(entry, dayNumber: dayNumber, groupId: groupId),
        )
        .toList(growable: false);
    await _savePendingPicksOutbox(next);
  }

  bool _isPermanentPicksOutboxFailure(_FirestoreWriteResult result) {
    final code = result.firebaseCode;
    if (code == null || code.isEmpty) return false;
    return code == 'permission-denied' ||
        code == 'failed-precondition' ||
        code == 'invalid-argument' ||
        code == 'not-found';
  }

  Future<void> flushPendingPicksOutbox() async {
    if (_flushingPendingPicksOutbox) return;
    final fs = _firestoreService;
    if (fs == null || !isAuthenticated) return;
    final uid = _profile.id.trim();
    if (uid.isEmpty) return;

    _flushingPendingPicksOutbox = true;
    try {
      final queue = _loadPendingPicksOutbox();
      if (queue.isEmpty) return;

      final remaining = <_PendingPicksSubmission>[];
      for (var i = 0; i < queue.length; i++) {
        final entry = queue[i];
        final result = await _runFirestoreWriteWithRetryDetailed(
          operation: 'savePicks.outbox',
          action: () => fs.savePicks(
            uid: uid,
            seasonKey: currentSeasonKey,
            dayNumber: entry.dayNumber,
            picksByMatchId: entry.picksByMatchId,
            visibility: entry.visibility,
            groupId: entry.groupId,
          ),
        );
        if (!result.success) {
          if (_isPermanentPicksOutboxFailure(result)) {
            if (kDebugMode) {
              debugPrint(
                '[picks-outbox] dropping entry day=${entry.dayNumber} '
                'group=${entry.groupId ?? "nogroup"} '
                'reason=${result.firebaseCode ?? "permanent-failure"}',
              );
            }
            continue;
          }
          remaining.addAll(queue.sublist(i));
          // Break at first failing write to avoid hammering backend.
          break;
        }
      }
      await _savePendingPicksOutbox(remaining);
    } finally {
      _flushingPendingPicksOutbox = false;
    }
  }

  /// Upload picks per questa giornata su Firestore.
  ///
  /// When [targetGroupId] is provided it overrides the current [activeGroupId],
  /// allowing bulk submission to multiple groups without switching active group.
  Future<bool> submitPicksToFirestore({
    required int dayNumber,
    required Map<String, PickOption> picksByMatchId,
    required String visibility,
    DayScoreBreakdown? score,
    String? targetGroupId,
  }) async {
    final fs = _firestoreService;
    if (fs == null || !isAuthenticated) {
      debugPrint('[savePicks] bail: fs=${fs != null} auth=$isAuthenticated');
      return false;
    }
    final payload = Map<String, PickOption>.from(picksByMatchId);
    final scopedGroupId = (targetGroupId ?? activeGroupId ?? '').trim();
    final groupId = scopedGroupId.isEmpty ? null : scopedGroupId;

    debugPrint(
      '[savePicks] uid=${_profile.id} season=$currentSeasonKey '
      'day=$dayNumber group=${groupId ?? "none"} picks=${payload.length}',
    );

    await _enqueuePendingPicksSubmission(
      dayNumber: dayNumber,
      picksByMatchId: payload,
      visibility: visibility,
      groupId: groupId,
    );

    final ok = await _runFirestoreWriteWithRetry(
      operation: 'savePicks',
      action: () => fs.savePicks(
        uid: _profile.id,
        seasonKey: currentSeasonKey,
        dayNumber: dayNumber,
        picksByMatchId: payload,
        visibility: visibility,
        groupId: groupId,
        score: score,
      ),
    );
    if (!ok) {
      debugPrint('[savePicks] FAILED for day=$dayNumber');
    }
    if (ok) {
      await _removePendingPicksSubmission(
        dayNumber: dayNumber,
        groupId: groupId,
      );
      unawaited(flushPendingPicksOutbox());
    }
    return ok;
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

    final docs = await fs.getPicksForMatchday(
      seasonKey: currentSeasonKey,
      dayNumber: dayNumber,
      uids: uids,
      groupId: activeGroupId,
    );

    final requesterUid = _profile.id;
    final now = DateTime.now();

    return {
      for (final d in docs)
        d.uid: () {
          if (d.uid == requesterUid) return d.picksByMatchId;

          final visibility = d.visibility.toLowerCase().trim();
          if (visibility == 'public') {
            // "Invia e mostra": visibile subito.
            return d.picksByMatchId;
          }

          // Per-user lock: visibile 1 minuto dopo la sottomissione.
          final revealTime =
              d.submittedAt.add(const Duration(minutes: 1));
          if (now.isAfter(revealTime)) {
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
  Future<List<PicksDocument>> fetchSeasonPicksForUser(
    String uid, {
    String? groupId,
    bool scopedToActiveGroup = false,
  }) async {
    final fs = _firestoreService;
    if (fs == null || !isAuthenticated) return [];
    final scopedGroupId = scopedToActiveGroup ? activeGroupId : groupId;
    return fs.getPicksForUser(
      uid: uid,
      seasonKey: currentSeasonKey,
      groupId: scopedGroupId,
    );
  }

  Future<Map<String, List<PicksDocument>>>
  fetchSeasonPicksByMemberForActiveGroup(List<String> memberUids) async {
    final fs = _firestoreService;
    final groupId = activeGroupId;
    if (fs == null || !isAuthenticated || groupId == null) return const {};

    final scopedUids = memberUids
        .map((uid) => uid.trim())
        .where((uid) => uid.isNotEmpty)
        .toSet();
    if (scopedUids.isEmpty) return const {};

    final seasonDocs = await fs.getPicksForSeason(
      seasonKey: currentSeasonKey,
      groupId: groupId,
    );
    final out = <String, List<PicksDocument>>{};
    for (final doc in seasonDocs) {
      if (!scopedUids.contains(doc.uid)) continue;
      out.putIfAbsent(doc.uid, () => <PicksDocument>[]).add(doc);
    }
    for (final uid in scopedUids) {
      out.putIfAbsent(uid, () => <PicksDocument>[]);
    }
    for (final docs in out.values) {
      docs.sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
    }
    return out;
  }

  /// Hydrate picks history + matchday snapshots from Firestore for current user.
  /// This avoids losing "past predictions" and day scores on new install/device.
  Future<void> hydrateCurrentUserHistoryFromFirestore({
    bool force = false,
    bool throwOnError = false,
  }) async {
    final fs = _firestoreService;
    final uid = _profile.id.trim();
    if (fs == null || !isAuthenticated || uid.isEmpty) return;
    if (_hydratingCurrentUserHistoryFromFirestore) return;

    final hydrationKey = '$uid:$currentSeasonKey:${_historyGroupScopeKey()}';
    if (!force && _hydratedCurrentUserHistoryKey == hydrationKey) return;

    _hydratingCurrentUserHistoryFromFirestore = true;
    _lastHistoryHydrationAttemptAt = DateTime.now();
    try {
      final picksDocs = await fs.getPicksForUser(
        uid: uid,
        seasonKey: currentSeasonKey,
        groupId: activeGroupId,
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

      // If the live picks map is empty but we have saved picks for the
      // current matchday, repopulate it so the Predictions tab shows them
      // immediately without requiring a page reload.
      predictionState.ensureCurrentUserPicksLoaded();
      final cursor = cassandraMatchdayCursor;
      if (predictionState.currentUserPicksByMatchId.isEmpty && cursor > 0) {
        final savedForCurrent =
            predictionState.currentUserPicksByMatchday[cursor];
        if (savedForCurrent != null && savedForCurrent.isNotEmpty) {
          for (final entry in savedForCurrent.entries) {
            predictionState.setCurrentUserPick(entry.key, entry.value);
          }
          if (kDebugMode) {
            debugPrint(
              '[history-hydration] restored ${savedForCurrent.length} '
              'live picks from history for day=$cursor',
            );
          }
        }
      }

      _hydratedCurrentUserHistoryKey = hydrationKey;
      if (_lastHistoryHydrationError != null) {
        _lastHistoryHydrationError = null;
        notifyListeners();
      }
    } catch (e, st) {
      _lastHistoryHydrationError = e.toString();
      if (kDebugMode) {
        debugPrint('[history-hydration] failed: $e');
        debugPrint('$st');
      }
      _recordBackendError(e, st);
      if (throwOnError) rethrow;
    } finally {
      _hydratingCurrentUserHistoryFromFirestore = false;
    }
  }

  String _historyGroupScopeKey() {
    final scopedGroupId = activeGroupId?.trim() ?? '';
    return scopedGroupId.isEmpty ? 'nogroup' : scopedGroupId;
  }

  // ===== LOCAL → FIRESTORE MIGRATION =====

  /// One-time migration: upload local picks + outcomes to Firestore.
  /// Runs once per device, flagged via SharedPreferences.
  Future<void> migrateLocalDataToFirestoreIfNeeded() async {
    final prefs = _prefs;
    final fs = _firestoreService;
    if (prefs == null || fs == null || !isAuthenticated) return;
    if (prefs.getBool(_kFirestoreMigrationV1DoneScoped) == true) return;

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

        await fs.savePicks(
          uid: uid,
          seasonKey: season,
          dayNumber: dayNumber,
          picksByMatchId: picks,
          visibility: predictionVisibilityToStorage(_defaultVisibility),
          groupId: activeGroupId,
        );
      }

      await prefs.setBool(_kFirestoreMigrationV1DoneScoped, true);
      _clearBackendError();
    } catch (e, st) {
      // Migration failed — will retry next launch
      _recordBackendError(e, st);
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

  /// Reset picks for the current matchday: clear local + delete from Firestore.
  Future<void> resetPicksForCurrentMatchday() async {
    final day = cassandraMatchdayCursor;
    // Clear live picks.
    predictionState.clearCurrentUserPicks();
    // Clear history entry for this matchday.
    predictionState.clearPicksForMatchday(day);
    // Delete from Firestore.
    final fs = _firestoreService;
    final uid = _profile.id.trim();
    if (fs != null && uid.isNotEmpty) {
      try {
        await fs.deletePicks(
          uid: uid,
          seasonKey: currentSeasonKey,
          dayNumber: day,
          groupId: activeGroupId,
        );
      } catch (e) {
        debugPrint('[resetPicks] Firestore delete failed: $e');
      }
    }
    notifyListeners();
  }
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

  // ===== PORTABLE IMAGE UTILITIES =====

  Future<StorageUploadResult?> _resolveImageReferenceForUpload({
    required String source,
    required String? profileUid,
    required String? groupId,
  }) async {
    final cleaned = source.trim();
    if (cleaned.isEmpty) return null;
    final lower = cleaned.toLowerCase();
    final isLocalOrData =
        lower.startsWith('data:image/') || _looksLikeLocalFileRef(cleaned);
    final storage = _storageService;

    if (!isLocalOrData) {
      if (storage != null && storage.isRemoteImageUrl(cleaned)) {
        final normalizedRemote = _normalizePersistedImageReference(cleaned);
        return StorageUploadResult(
          downloadUrl: normalizedRemote,
          storagePath: '',
          uploaded: false,
        );
      }
      return null;
    }

    if (storage != null) {
      try {
        if (groupId != null && groupId.trim().isNotEmpty) {
          final uploaded = await storage.uploadGroupImage(
            groupId: groupId.trim(),
            source: cleaned,
          );
          if (uploaded != null) return uploaded;
        } else if (profileUid != null && profileUid.trim().isNotEmpty) {
          final uploaded = await storage.uploadUserProfileImage(
            uid: profileUid.trim(),
            source: cleaned,
          );
          if (uploaded != null) return uploaded;
        }
      } catch (e, st) {
        _recordBackendError(e, st);
      }
    }

    final portable = await _portableImageReference(cleaned);
    if (portable != null && portable.trim().isNotEmpty) {
      return StorageUploadResult(
        downloadUrl: portable,
        storagePath: '',
        uploaded: false,
      );
    }

    return null;
  }

  Future<void> _bestEffortDeleteStorageObject(String? reference) async {
    final storage = _storageService;
    final cleaned = (reference ?? '').trim();
    if (storage == null || cleaned.isEmpty) return;
    try {
      await storage.deleteByDownloadUrl(cleaned);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[image] storage cleanup failed: $e');
        debugPrint('$st');
      }
    }
  }

  Future<bool> _isKnownMissingStorageObject(String reference) async {
    final storage = _storageService;
    final cleaned = reference.trim();
    if (storage == null || cleaned.isEmpty) return false;
    if (!storage.isFirebaseStorageUrl(cleaned) &&
        !storage.isStoragePathReference(cleaned)) {
      return false;
    }
    try {
      return !(await storage.objectExistsByDownloadUrl(cleaned));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[image] storage metadata check failed: $e');
        debugPrint('$st');
      }
      return false;
    }
  }

  Future<String?> _portableImageReference(String source) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('data:image/')) {
      return trimmed;
    }

    try {
      var filePath = trimmed;
      if (lower.startsWith('file://')) {
        final uri = Uri.tryParse(trimmed);
        if (uri != null && uri.scheme == 'file') {
          filePath = uri.toFilePath();
        } else {
          filePath = trimmed.replaceFirst(RegExp(r'^file://'), '');
        }
      }

      final file = File(filePath);
      if (!file.existsSync()) return trimmed;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return trimmed;
      String mime = 'image/jpeg';
      final lowerPath = file.path.toLowerCase();
      if (lowerPath.endsWith('.png')) {
        mime = 'image/png';
      } else if (lowerPath.endsWith('.webp')) {
        mime = 'image/webp';
      } else if (lowerPath.endsWith('.gif')) {
        mime = 'image/gif';
      }
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[image] failed to encode portable image reference: $e');
        debugPrint('$st');
      }
      return trimmed;
    }
  }

  bool _looksLikePortableImageRef(String value) {
    final lower = value.trim().toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('data:image/');
  }

  bool _looksLikeLocalFileRef(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    return lower.startsWith('file://') ||
        lower.startsWith('/var/') ||
        lower.startsWith('/private/var/') ||
        lower.startsWith('/data/') ||
        lower.startsWith('/storage/') ||
        lower.startsWith('/users/');
  }

  Future<void> _repairProfilePhotoReferenceIfNeeded() async {
    final current = (_profile.photoUrl ?? '').trim();
    if (current.isEmpty) {
      return;
    }

    final normalized = _normalizePersistedImageReference(current);
    if (normalized != current) {
      await updateProfilePhotoPath(normalized);
      return;
    }

    final missingStorageObject = await _isKnownMissingStorageObject(current);
    if (missingStorageObject) {
      await updateProfilePhotoPath(null);
      return;
    }

    if (_looksLikePortableImageRef(current) ||
        !_looksLikeLocalFileRef(current)) {
      return;
    }

    await updateProfilePhotoPath(current);
  }

  Future<void> _repairGroupImageReferenceIfNeeded(GroupDocument group) async {
    final raw = (group.imageUrl ?? '').trim();
    if (raw.isEmpty) {
      return;
    }

    final isAdmin = group.adminUid.trim() == _profile.id.trim();
    final normalized = _normalizePersistedImageReference(raw);
    if (normalized != raw) {
      if (isAdmin) {
        await updateGroupImagePath(normalized);
      }
      return;
    }
    final missingStorageObject = await _isKnownMissingStorageObject(raw);
    if (missingStorageObject) {
      if (isAdmin) {
        await updateGroupImagePath(null);
      }
      return;
    }

    if (_looksLikePortableImageRef(raw) || !_looksLikeLocalFileRef(raw)) {
      return;
    }
    if (!isAdmin) {
      return;
    }
    await updateGroupImagePath(raw);
  }
}

class _PendingPicksSubmission {
  final int dayNumber;
  final Map<String, PickOption> picksByMatchId;
  final String visibility;
  final String? groupId;
  final int createdAtMs;

  const _PendingPicksSubmission({
    required this.dayNumber,
    required this.picksByMatchId,
    required this.visibility,
    required this.groupId,
    required this.createdAtMs,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'dayNumber': dayNumber,
    'visibility': visibility,
    'groupId': groupId,
    'createdAtMs': createdAtMs,
    'picksByMatchId': {
      for (final e in picksByMatchId.entries) e.key: e.value.name,
    },
  };

  static _PendingPicksSubmission? fromJson(Map<String, dynamic> json) {
    final dayNumber = json['dayNumber'];
    final visibility = (json['visibility'] as String?)?.trim();
    final rawPicks = json['picksByMatchId'];
    if (dayNumber is! int ||
        visibility == null ||
        visibility.isEmpty ||
        rawPicks is! Map) {
      return null;
    }
    final picks = <String, PickOption>{};
    for (final entry in rawPicks.entries) {
      final key = (entry.key as Object?)?.toString().trim() ?? '';
      final value = (entry.value as Object?)?.toString().trim() ?? '';
      if (key.isEmpty || value.isEmpty) continue;
      try {
        picks[key] = PickOption.values.byName(value);
      } catch (_) {
        // Skip unknown enum values from older/corrupt payloads.
      }
    }
    if (picks.isEmpty) return null;
    final groupId = (json['groupId'] as String?)?.trim();
    final createdAtMs = (json['createdAtMs'] as num?)?.toInt() ?? 0;
    return _PendingPicksSubmission(
      dayNumber: dayNumber,
      picksByMatchId: picks,
      visibility: visibility,
      groupId: (groupId == null || groupId.isEmpty) ? null : groupId,
      createdAtMs: createdAtMs,
    );
  }
}

class _FirestoreWriteResult {
  const _FirestoreWriteResult({
    required this.success,
    this.error,
    this.stackTrace,
  });

  final bool success;
  final Object? error;
  final StackTrace? stackTrace;

  String? get firebaseCode {
    final err = error;
    if (err is FirebaseException) {
      final code = err.code.trim();
      return code.isEmpty ? null : code;
    }
    return null;
  }
}
