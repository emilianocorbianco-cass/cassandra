import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/group/models/group_member.dart';
import '../../services/firestore/firestore_service.dart';
import '../../services/firestore/models/group_document.dart';
import '../config/storage_keys.dart';
import 'user_profile.dart';

/// Stato del gruppo, estratto da AppState per isolamento e testabilità.
///
/// Gestisce: creazione/join/leave/delete gruppo, metadata locale,
/// Firestore group IDs, active group, admin approval.
class GroupState extends ChangeNotifier {
  String _friendlyGroupError(Object error, String fallback) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Permission denied';
        case 'deadline-exceeded':
          return 'Request timeout';
        case 'unavailable':
          return 'Backend unavailable';
        case 'resource-exhausted':
          return 'Group full';
        case 'failed-precondition':
          return 'Group unavailable';
      }
    }
    return fallback;
  }

  void _logGroupError(String operation, Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;
    debugPrint('[group-state][$operation] $error');
    debugPrint('$stackTrace');
  }

  static const _kGroupNameV1 = StorageKeys.groupNameV1;
  static const _kGroupInviteCodeV1 = StorageKeys.groupInviteCodeV1;
  static const _kGroupImagePathV1 = StorageKeys.groupImagePathV1;
  static const _kGroupAdminApprovalV1 = StorageKeys.groupAdminApprovalV1;
  static const _kGroupActiveGroupIdV1 = StorageKeys.groupActiveGroupIdV1;

  final SharedPreferences? _prefs;

  String? _groupName;
  String? _groupInviteCode;
  String? _groupImagePath;
  bool _groupAdminApproval = false;

  List<String> _firestoreGroupIds = [];
  String? _activeGroupId;

  // ===== Getters =====

  String? get groupName => _groupName;
  String? get groupInviteCode => _groupInviteCode;
  String? get groupImagePath => _groupImagePath;
  bool get groupAdminApproval => _groupAdminApproval;
  List<String> get firestoreGroupIds =>
      List<String>.unmodifiable(_firestoreGroupIds);

  String? get activeGroupId =>
      _activeGroupId ??
      (_firestoreGroupIds.isNotEmpty ? _firestoreGroupIds.first : null);

  bool get hasGroup => activeGroupId != null || _groupName != null;

  // ===== Constructor =====

  GroupState._({
    required SharedPreferences? prefs,
    String? groupName,
    String? groupInviteCode,
    String? groupImagePath,
    bool groupAdminApproval = false,
    String? activeGroupId,
  }) : _prefs = prefs,
       _groupName = groupName,
       _groupInviteCode = groupInviteCode,
       _groupImagePath = groupImagePath,
       _groupAdminApproval = groupAdminApproval,
       _activeGroupId = activeGroupId;

  /// Crea dallo storage persistente (usato da AppState.load).
  factory GroupState.fromPrefs(SharedPreferences? prefs) {
    return GroupState._(
      prefs: prefs,
      groupName: prefs?.getString(_kGroupNameV1),
      groupInviteCode: prefs?.getString(_kGroupInviteCodeV1),
      groupImagePath: prefs?.getString(_kGroupImagePathV1),
      groupAdminApproval: prefs?.getBool(_kGroupAdminApprovalV1) ?? false,
      activeGroupId: prefs?.getString(_kGroupActiveGroupIdV1),
    );
  }

  /// In-memory (per i test).
  factory GroupState.inMemory() {
    return GroupState._(prefs: null);
  }

  // ===== Firestore group IDs =====

  void setFirestoreGroupIds(List<String> ids) {
    final incoming = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    // If _activeGroupId was set locally (e.g. just created/joined a group)
    // but the remote list doesn't include it yet, merge it in so a stale
    // remote fetch doesn't overwrite the user's intent.
    final active = _activeGroupId;
    if (active != null &&
        active.isNotEmpty &&
        !incoming.contains(active)) {
      _firestoreGroupIds = [...incoming, active];
    } else {
      _firestoreGroupIds = incoming;
    }

    if (_activeGroupId == null) {
      _activeGroupId = _firestoreGroupIds.isNotEmpty
          ? _firestoreGroupIds.first
          : null;
      unawaited(_persistActiveGroupId());
    }
  }

  void setActiveGroupId(String? id) {
    final cleaned = (id ?? '').trim();
    _activeGroupId = cleaned.isEmpty ? null : cleaned;
    unawaited(_persistActiveGroupId());
    notifyListeners();
  }

  // ===== Metadata updates =====

  Future<void> updateGroupName(String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return;
    if (cleaned == _groupName) return;

    _groupName = cleaned;
    await _prefs?.setString(_kGroupNameV1, cleaned);
    notifyListeners();
  }

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

  // ===== Group lifecycle =====

  /// Crea gruppo. Ritorna error string o null se ok.
  Future<String?> createGroup({
    required String name,
    required String uid,
    required bool isAuthenticated,
    required UserProfile profile,
    required int avatarSeed,
    required FirestoreService? firestoreService,
  }) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return 'Invalid name';

    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    final fs = firestoreService;

    // Dev mode: backend non configurato -> crea solo locale.
    if (fs == null) {
      final suffix = List.generate(
        4,
        (_) => chars[rng.nextInt(chars.length)],
      ).join();
      final code = 'CASS-$suffix';
      final localGroupId = 'local-$code';
      _groupName = cleaned;
      _groupInviteCode = code;
      _activeGroupId = localGroupId;
      _firestoreGroupIds = [localGroupId];
      await _prefs?.setString(_kGroupNameV1, cleaned);
      await _prefs?.setString(_kGroupInviteCodeV1, code);
      await _persistActiveGroupId();
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
      } catch (error, stackTrace) {
        _logGroupError('createGroup.checkInviteCode', error, stackTrace);
        return _friendlyGroupError(error, 'Permission denied');
      }
    }
    if (code == null) return 'Invite code generation failed';

    try {
      final groupId = await fs.createGroup(
        name: cleaned,
        adminUid: uid,
        inviteCode: code,
        creatorDisplayName: profile.displayName,
        creatorTeamName: profile.teamName,
        creatorAvatarSeed: avatarSeed,
        creatorFavoriteTeam: profile.favoriteTeam,
        creatorPhotoUrl: profile.photoUrl,
      );

      _groupName = cleaned;
      _groupInviteCode = code;
      await _prefs?.setString(_kGroupNameV1, cleaned);
      await _prefs?.setString(_kGroupInviteCodeV1, code);

      if (!_firestoreGroupIds.contains(groupId)) {
        _firestoreGroupIds = [..._firestoreGroupIds, groupId];
      }
      _activeGroupId = groupId;
      await _persistActiveGroupId();

      notifyListeners();
      return null;
    } catch (error, stackTrace) {
      _logGroupError('createGroup', error, stackTrace);
      return _friendlyGroupError(error, 'Create group failed');
    }
  }

  /// Join via invite code. Ritorna error string o null se ok.
  Future<String?> joinGroupByInviteCode({
    required String code,
    required String uid,
    required bool isAuthenticated,
    required UserProfile profile,
    required int avatarSeed,
    required FirestoreService? firestoreService,
  }) async {
    final fs = firestoreService;
    if (fs == null) return 'Backend unavailable';
    if (!isAuthenticated) return 'Not authenticated';
    try {
      final group = await fs.getGroupByInviteCode(code.trim().toUpperCase());
      if (group == null) return 'Invalid code';

      if (_firestoreGroupIds.contains(group.id)) return 'Already a member';

      await fs.joinGroup(
        groupId: group.id,
        uid: uid,
        displayName: profile.displayName,
        teamName: profile.teamName,
        avatarSeed: avatarSeed,
        favoriteTeam: profile.favoriteTeam,
        photoUrl: profile.photoUrl,
      );

      _firestoreGroupIds = [..._firestoreGroupIds, group.id];
      _activeGroupId = group.id;
      await _persistActiveGroupId();

      _groupName = group.name;
      _groupInviteCode = group.inviteCode;
      await _prefs?.setString(_kGroupNameV1, group.name);
      await _prefs?.setString(_kGroupInviteCodeV1, group.inviteCode);

      notifyListeners();
      return null;
    } catch (error, stackTrace) {
      _logGroupError('joinGroupByInviteCode', error, stackTrace);
      return _friendlyGroupError(error, 'Join group failed');
    }
  }

  /// Lascia un gruppo Firestore.
  Future<void> leaveFirestoreGroup({
    required String groupId,
    required String uid,
    required bool isAuthenticated,
    required FirestoreService? firestoreService,
  }) async {
    final fs = firestoreService;
    if (fs == null || !isAuthenticated) return;

    await fs.leaveGroup(groupId: groupId, uid: uid);

    _firestoreGroupIds = _firestoreGroupIds
        .where((id) => id != groupId)
        .toList();
    if (_activeGroupId == groupId) {
      _activeGroupId = _firestoreGroupIds.isNotEmpty
          ? _firestoreGroupIds.first
          : null;
      await _persistActiveGroupId();
    }

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

  /// Elimina gruppo attivo (solo admin). Ritorna error string o null.
  Future<String?> deleteActiveGroupIfAdmin({
    required String uid,
    required bool isAuthenticated,
    required FirestoreService? firestoreService,
  }) async {
    final fs = firestoreService;
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
      await _prefs?.remove(_kGroupActiveGroupIdV1);
      notifyListeners();
      return null;
    }

    if (!isAuthenticated || uid.isEmpty) return 'Not authenticated';

    GroupDocument? group;
    try {
      group = await fs.getGroup(groupId);
    } catch (error, stackTrace) {
      _logGroupError('deleteGroup.fetchGroup', error, stackTrace);
      return _friendlyGroupError(error, 'Delete group failed');
    }

    if (group == null) {
      _firestoreGroupIds = _firestoreGroupIds
          .where((id) => id != groupId)
          .toList();
      _activeGroupId = _firestoreGroupIds.isNotEmpty
          ? _firestoreGroupIds.first
          : null;
      await _persistActiveGroupId();
      if (_activeGroupId == null) {
        await _clearLocalGroupData();
      }
      notifyListeners();
      return null;
    }

    if (group.adminUid != uid) return 'Not admin';

    try {
      await fs.deleteGroupAsAdmin(groupId: groupId, adminUid: uid);
    } catch (error, stackTrace) {
      _logGroupError('deleteGroup.deleteAsAdmin', error, stackTrace);
      return _friendlyGroupError(error, 'Delete group failed');
    }

    _firestoreGroupIds = _firestoreGroupIds
        .where((id) => id != groupId)
        .toList();
    _activeGroupId = _firestoreGroupIds.isNotEmpty
        ? _firestoreGroupIds.first
        : null;
    await _persistActiveGroupId();

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
        await _persistActiveGroupId();
        await _prefs?.remove(_kGroupNameV1);
        await _prefs?.remove(_kGroupInviteCodeV1);
        await _prefs?.remove(_kGroupImagePathV1);
        await _prefs?.remove(_kGroupAdminApprovalV1);
      }
    }

    notifyListeners();
    return null;
  }

  /// Refresh metadata del gruppo attivo da Firestore.
  /// Returns the fetched GroupDocument (or null) for caller use (e.g. repair).
  Future<GroupDocument?> refreshActiveGroupMetadataFromFirestore({
    required bool isAuthenticated,
    required FirestoreService? firestoreService,
  }) async {
    final fs = firestoreService;
    final groupId = activeGroupId;
    if (fs == null || !isAuthenticated || groupId == null) return null;

    final group = await fs.getGroup(groupId);
    if (group == null) return null;

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
    final groupImage = (group.imageUrl ?? '').trim();
    final normalizedGroupImage = groupImage.isEmpty ? null : groupImage;
    if (_groupImagePath != normalizedGroupImage) {
      _groupImagePath = normalizedGroupImage;
      if (normalizedGroupImage == null) {
        await _prefs?.remove(_kGroupImagePathV1);
      } else {
        await _prefs?.setString(_kGroupImagePathV1, normalizedGroupImage);
      }
      changed = true;
    }

    if (changed) notifyListeners();
    return group;
  }

  /// Fetch group members da Firestore.
  Future<List<GroupMember>> fetchFirestoreGroupMembers({
    required bool isAuthenticated,
    required FirestoreService? firestoreService,
  }) async {
    final fs = firestoreService;
    final groupId = activeGroupId;
    if (fs == null || !isAuthenticated || groupId == null) return [];

    final docs = await fs.getGroupMembers(groupId);
    return docs.map((d) {
      final photo = (d.photoUrl ?? '').trim();
      return GroupMember(
        id: d.uid,
        displayName: d.displayName,
        teamName: d.teamName,
        avatarSeed: d.avatarSeed,
        favoriteTeam: d.favoriteTeam,
        photoUrl: photo.isEmpty ? null : photo,
      );
    }).toList();
  }

  static bool _looksLikePortableImageRef(String value) {
    final lower = value.trim().toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('data:image/');
  }

  /// Exposed for testing only — do not call from production code.
  ///
  /// Returns true when [value] is a portable image reference (an http/https URL
  /// or an inline data: URI) that can be safely displayed across devices.
  /// File-system paths and blank strings return false.
  @visibleForTesting
  static bool isPortableImageRef(String value) =>
      _looksLikePortableImageRef(value);

  /// Fetch active group document da Firestore.
  Future<GroupDocument?> fetchActiveGroupDocument({
    required bool isAuthenticated,
    required FirestoreService? firestoreService,
  }) async {
    final fs = firestoreService;
    final groupId = activeGroupId;
    if (fs == null || !isAuthenticated || groupId == null) return null;
    return fs.getGroup(groupId);
  }

  // ===== Reset =====

  /// Pulisce tutto lo stato gruppo (usato da signOut/resetAll).
  Future<void> clearAll() async {
    _groupName = null;
    _groupInviteCode = null;
    _deleteGroupImageFile();
    _groupImagePath = null;
    _groupAdminApproval = false;
    _firestoreGroupIds = [];
    _activeGroupId = null;
    await _prefs?.remove(_kGroupNameV1);
    await _prefs?.remove(_kGroupInviteCodeV1);
    await _prefs?.remove(_kGroupImagePathV1);
    await _prefs?.remove(_kGroupAdminApprovalV1);
    await _prefs?.remove(_kGroupActiveGroupIdV1);
    notifyListeners();
  }

  // ===== Helpers =====

  void _deleteGroupImageFile() {
    final path = _groupImagePath;
    if (path == null) return;
    final lower = path.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('data:image/')) {
      return;
    }
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // ignore: best-effort cleanup
    }
  }

  Future<void> _clearLocalGroupData() async {
    _groupName = null;
    _groupInviteCode = null;
    _deleteGroupImageFile();
    _groupImagePath = null;
    _groupAdminApproval = false;
    _activeGroupId = null;
    await _prefs?.remove(_kGroupNameV1);
    await _prefs?.remove(_kGroupInviteCodeV1);
    await _prefs?.remove(_kGroupImagePathV1);
    await _prefs?.remove(_kGroupAdminApprovalV1);
    await _prefs?.remove(_kGroupActiveGroupIdV1);
  }

  Future<void> _persistActiveGroupId() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final activeId = (_activeGroupId ?? '').trim();
    if (activeId.isEmpty) {
      await prefs.remove(_kGroupActiveGroupIdV1);
      return;
    }
    await prefs.setString(_kGroupActiveGroupIdV1, activeId);
  }

  @override
  void dispose() {
    _groupName = null;
    _groupInviteCode = null;
    _groupImagePath = null;
    _groupAdminApproval = false;
    _firestoreGroupIds = const <String>[];
    _activeGroupId = null;
    super.dispose();
  }
}
