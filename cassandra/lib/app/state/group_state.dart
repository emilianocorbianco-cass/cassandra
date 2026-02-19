import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/group/models/group_member.dart';
import '../../services/firestore/firestore_service.dart';
import '../../services/firestore/models/group_document.dart';
import 'user_profile.dart';

/// Stato del gruppo, estratto da AppState per isolamento e testabilità.
///
/// Gestisce: creazione/join/leave/delete gruppo, metadata locale,
/// Firestore group IDs, active group, admin approval.
class GroupState extends ChangeNotifier {
  static const _kGroupNameV1 = 'group.name.v1';
  static const _kGroupInviteCodeV1 = 'group.inviteCode.v1';
  static const _kGroupImagePathV1 = 'group.imagePath.v1';
  static const _kGroupAdminApprovalV1 = 'group.adminApproval.v1';

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
  List<String> get firestoreGroupIds => _firestoreGroupIds;

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
  }) : _prefs = prefs,
       _groupName = groupName,
       _groupInviteCode = groupInviteCode,
       _groupImagePath = groupImagePath,
       _groupAdminApproval = groupAdminApproval;

  /// Crea dallo storage persistente (usato da AppState.load).
  factory GroupState.fromPrefs(SharedPreferences? prefs) {
    return GroupState._(
      prefs: prefs,
      groupName: prefs?.getString(_kGroupNameV1),
      groupInviteCode: prefs?.getString(_kGroupInviteCodeV1),
      groupImagePath: prefs?.getString(_kGroupImagePathV1),
      groupAdminApproval: prefs?.getBool(_kGroupAdminApprovalV1) ?? false,
    );
  }

  /// In-memory (per i test).
  factory GroupState.inMemory() {
    return GroupState._(prefs: null);
  }

  // ===== Firestore group IDs =====

  void setFirestoreGroupIds(List<String> ids) {
    _firestoreGroupIds = ids;
    if (_activeGroupId == null ||
        !_firestoreGroupIds.contains(_activeGroupId)) {
      _activeGroupId =
          _firestoreGroupIds.isNotEmpty ? _firestoreGroupIds.first : null;
    }
  }

  void setActiveGroupId(String? id) {
    _activeGroupId = id;
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
      await fs.joinGroup(
        groupId: groupId,
        uid: uid,
        displayName: profile.displayName,
        teamName: profile.teamName,
        avatarSeed: avatarSeed,
        favoriteTeam: profile.favoriteTeam,
        photoUrl: profile.photoUrl,
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

    _groupName = group.name;
    _groupInviteCode = group.inviteCode;
    await _prefs?.setString(_kGroupNameV1, group.name);
    await _prefs?.setString(_kGroupInviteCodeV1, group.inviteCode);

    notifyListeners();
    return null;
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

    _firestoreGroupIds =
        _firestoreGroupIds.where((id) => id != groupId).toList();
    if (_activeGroupId == groupId) {
      _activeGroupId =
          _firestoreGroupIds.isNotEmpty ? _firestoreGroupIds.first : null;
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
      notifyListeners();
      return null;
    }

    if (!isAuthenticated || uid.isEmpty) return 'Not authenticated';

    GroupDocument? group;
    try {
      group = await fs.getGroup(groupId);
    } catch (_) {
      return 'Delete group failed';
    }

    if (group == null) {
      _firestoreGroupIds =
          _firestoreGroupIds.where((id) => id != groupId).toList();
      _activeGroupId =
          _firestoreGroupIds.isNotEmpty ? _firestoreGroupIds.first : null;
      if (_activeGroupId == null) {
        await _clearLocalGroupData();
      }
      notifyListeners();
      return null;
    }

    if (group.adminUid != uid) return 'Not admin';

    try {
      await fs.deleteGroupAsAdmin(groupId: groupId, adminUid: uid);
    } catch (_) {
      return 'Delete group failed';
    }

    _firestoreGroupIds =
        _firestoreGroupIds.where((id) => id != groupId).toList();
    _activeGroupId =
        _firestoreGroupIds.isNotEmpty ? _firestoreGroupIds.first : null;

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

  /// Refresh metadata del gruppo attivo da Firestore.
  Future<void> refreshActiveGroupMetadataFromFirestore({
    required bool isAuthenticated,
    required FirestoreService? firestoreService,
  }) async {
    final fs = firestoreService;
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

  /// Fetch group members da Firestore.
  Future<List<GroupMember>> fetchFirestoreGroupMembers({
    required bool isAuthenticated,
    required FirestoreService? firestoreService,
  }) async {
    final fs = firestoreService;
    final groupId = activeGroupId;
    if (fs == null || !isAuthenticated || groupId == null) return [];

    final docs = await fs.getGroupMembers(groupId);
    final photosByUid = await fs.getUserPhotoUrls(
      docs.map((d) => d.uid).toList(growable: false),
    );
    return docs
        .map(
          (d) => GroupMember(
            id: d.uid,
            displayName: d.displayName,
            teamName: d.teamName,
            avatarSeed: d.avatarSeed,
            favoriteTeam: d.favoriteTeam,
            photoUrl: (d.photoUrl?.trim().isNotEmpty ?? false)
                ? d.photoUrl!.trim()
                : photosByUid[d.uid],
          ),
        )
        .toList();
  }

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
    notifyListeners();
  }

  // ===== Helpers =====

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

  Future<void> _clearLocalGroupData() async {
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
}
