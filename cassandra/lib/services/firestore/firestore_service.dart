import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../app/state/app_settings.dart';
import '../../app/state/user_profile.dart';
import '../../features/predictions/models/pick_option.dart';
import '../../features/predictions/models/prediction_match.dart';
import '../../features/scoring/models/match_outcome.dart';
import '../api_football/models/api_football_standing.dart';
import 'firestore_serializers.dart';
import 'models/chat_message_document.dart';
import 'models/group_document.dart';
import 'models/matchday_document.dart';
import 'models/picks_document.dart';

class FirestoreService {
  late final FirebaseFirestore _db;
  static const Duration _requestTimeout = Duration(seconds: 15);

  // ---------------------------------------------------------------------------
  // Group profile sync — retry / chunk constants and test-injection fields
  // ---------------------------------------------------------------------------

  static const int _kGroupProfileBatchSize = 350;
  static const int _kGroupProfileSyncMaxAttempts = 3;
  static const Duration _kGroupProfileSyncRetryBaseDelay = Duration(
    milliseconds: 500,
  );

  /// Injectable hook for unit tests — when non-null, replaces the Firestore
  /// batch-commit in [updateGroupMemberProfileInGroups] so tests never need
  /// Firebase to be initialized.
  final Future<void> Function(int chunkIndex, List<String> groupIds)?
  _groupProfileSyncChunkHook;

  /// Injectable retry delay for unit tests.  [null] means use
  /// [_kGroupProfileSyncRetryBaseDelay].  Set to [Duration.zero] to make
  /// retries instant in tests.
  final Duration? _groupProfileSyncRetryDelay;

  FirestoreService({FirebaseFirestore? firestore})
    : _groupProfileSyncChunkHook = null,
      _groupProfileSyncRetryDelay = null {
    _db = firestore ?? FirebaseFirestore.instance;
  }

  /// Test-only named constructor: injects a chunk hook and instant retry delay
  /// so unit tests can exercise retry logic without touching Firebase.
  ///
  /// [_db] is intentionally left un-initialized — accessing it from a test
  /// that uses this constructor will throw [LateInitializationError]
  /// immediately rather than silently succeeding with a live Firestore.
  @visibleForTesting
  FirestoreService.forGroupSyncTest({
    required Future<void> Function(int chunkIndex, List<String> groupIds)
    chunkHook,
    Duration retryDelay = Duration.zero,
  }) : _groupProfileSyncChunkHook = chunkHook,
       _groupProfileSyncRetryDelay = retryDelay;

  Future<T> _withTimeout<T>(
    Future<T> future, {
    required String operation,
  }) async {
    try {
      return await future.timeout(_requestTimeout);
    } on TimeoutException catch (_) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
        message: 'Request timeout during $operation',
      );
    }
  }

  /// Attempts [commitAction] up to [_kGroupProfileSyncMaxAttempts] times with
  /// exponential back-off.  Throws a descriptive [Exception] — never silently
  /// swallows the error — so callers can detect and log partial progress.
  Future<void> _retryChunkCommit({
    required Future<void> Function() commitAction,
    required List<String> chunkGroupIds,
    required int chunkIndex,
    required int totalChunks,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < _kGroupProfileSyncMaxAttempts; attempt++) {
      if (attempt > 0) {
        final baseDelay =
            _groupProfileSyncRetryDelay ?? _kGroupProfileSyncRetryBaseDelay;
        final delay = baseDelay * (1 << attempt); // 500 ms, 1 000 ms, …
        if (kDebugMode) {
          debugPrint(
            '[group-sync] chunk ${chunkIndex + 1}/$totalChunks: '
            'retry $attempt after ${delay.inMilliseconds} ms '
            '(last error: $lastError)',
          );
        }
        await Future<void>.delayed(delay);
      }

      try {
        await commitAction();
        if (kDebugMode && attempt > 0) {
          debugPrint(
            '[group-sync] chunk ${chunkIndex + 1}/$totalChunks: '
            'succeeded on attempt ${attempt + 1}',
          );
        }
        return; // success
      } catch (e) {
        lastError = e;
        if (kDebugMode) {
          debugPrint(
            '[group-sync] chunk ${chunkIndex + 1}/$totalChunks: '
            'attempt ${attempt + 1} failed — $e',
          );
        }
      }
    }

    // All attempts exhausted — surface a descriptive, non-silent error.
    final groupSummary = chunkGroupIds.length <= 5
        ? chunkGroupIds.join(', ')
        : '${chunkGroupIds.take(5).join(', ')} … (${chunkGroupIds.length} total)';
    throw Exception(
      'updateGroupMemberProfileInGroups: chunk ${chunkIndex + 1}/$totalChunks '
      'permanently failed after $_kGroupProfileSyncMaxAttempts attempts '
      '(groups: $groupSummary): $lastError',
    );
  }

  // ===== USER PROFILE =====

  Future<void> setUserProfile({
    required String uid,
    required UserProfile profile,
    required CassandraLanguage language,
    required PredictionVisibility defaultVisibility,
    required int avatarSeed,
    List<String>? groupIds,
  }) async {
    final data = <String, dynamic>{
      'displayName': profile.displayName,
      'teamName': profile.teamName,
      'favoriteTeam': profile.favoriteTeam,
      'email': profile.email,
      'photoUrl': profile.photoUrl,
      'language': cassandraLanguageToStorage(language),
      'defaultVisibility': predictionVisibilityToStorage(defaultVisibility),
      'avatarSeed': avatarSeed,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (groupIds != null) {
      data['groupIds'] = groupIds;
    }

    await _withTimeout(
      _db.collection('users').doc(uid).set(data, SetOptions(merge: true)),
      operation: 'setUserProfile',
    );
  }

  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await _withTimeout(
      _db.collection('users').doc(uid).get(),
      operation: 'getUserProfile',
    );
    if (!doc.exists) return null;
    return doc.data();
  }

  Future<void> updateUserField(String uid, Map<String, dynamic> fields) async {
    fields['updatedAt'] = FieldValue.serverTimestamp();
    await _withTimeout(
      _db.collection('users').doc(uid).update(fields),
      operation: 'updateUserField',
    );
  }

  Future<void> mergeUserField(String uid, Map<String, dynamic> fields) async {
    fields['updatedAt'] = FieldValue.serverTimestamp();
    await _withTimeout(
      _db.collection('users').doc(uid).set(fields, SetOptions(merge: true)),
      operation: 'mergeUserField',
    );
  }

  Future<void> addUserFcmToken({
    required String uid,
    required String token,
  }) async {
    final cleaned = token.trim();
    if (cleaned.isEmpty) return;
    await _withTimeout(
      _db.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([cleaned]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      operation: 'addUserFcmToken',
    );
  }

  Future<void> removeUserFcmToken({
    required String uid,
    required String token,
  }) async {
    final cleaned = token.trim();
    if (cleaned.isEmpty) return;
    await _withTimeout(
      _db.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayRemove([cleaned]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      operation: 'removeUserFcmToken',
    );
  }

  // ===== GROUPS =====

  Future<String> createGroup({
    required String name,
    required String adminUid,
    required String inviteCode,
  }) async {
    final docRef = await _withTimeout(
      _db.collection('groups').add({
        'name': name,
        'inviteCode': inviteCode,
        'adminUid': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'memberCount': 0,
      }),
      operation: 'createGroup',
    );
    return docRef.id;
  }

  Future<GroupDocument?> getGroupByInviteCode(String code) async {
    final snap = await _withTimeout(
      _db
          .collection('groups')
          .where('inviteCode', isEqualTo: code)
          .limit(1)
          .get(),
      operation: 'getGroupByInviteCode',
    );
    if (snap.docs.isEmpty) return null;
    return GroupDocument.fromFirestore(snap.docs.first);
  }

  Future<GroupDocument?> getGroup(String groupId) async {
    final doc = await _withTimeout(
      _db.collection('groups').doc(groupId).get(),
      operation: 'getGroup',
    );
    if (!doc.exists) return null;
    return GroupDocument.fromFirestore(doc);
  }

  Future<void> updateGroupImageUrl({
    required String groupId,
    required String? imageUrl,
  }) async {
    final cleaned = (imageUrl ?? '').trim();
    await _withTimeout(
      _db.collection('groups').doc(groupId).set({
        'imageUrl': cleaned.isEmpty ? null : cleaned,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      operation: 'updateGroupImageUrl',
    );
  }

  Future<void> joinGroup({
    required String groupId,
    required String uid,
    required String displayName,
    required String teamName,
    required int avatarSeed,
    String? favoriteTeam,
    String? photoUrl,
  }) async {
    final groupRef = _db.collection('groups').doc(groupId);
    final memberRef = groupRef.collection('members').doc(uid);
    final userRef = _db.collection('users').doc(uid);

    await _withTimeout(
      _db.runTransaction((txn) async {
        final groupSnap = await txn.get(groupRef);
        if (!groupSnap.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-found',
            message: 'Group not found',
          );
        }

        final memberSnap = await txn.get(memberRef);
        final baseMemberData = <String, dynamic>{
          'displayName': displayName,
          'teamName': teamName,
          'photoUrl': photoUrl,
          'avatarSeed': avatarSeed,
          'favoriteTeam': favoriteTeam,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (!memberSnap.exists) {
          final currentCount =
              (groupSnap.data()?['memberCount'] as num?)?.toInt() ?? 0;
          txn.set(memberRef, {
            ...baseMemberData,
            'joinedAt': FieldValue.serverTimestamp(),
            'role': 'member',
          }, SetOptions(merge: true));
          txn.update(groupRef, {
            'memberCount': currentCount + 1,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          txn.set(memberRef, baseMemberData, SetOptions(merge: true));
        }

        txn.set(userRef, {
          'groupIds': FieldValue.arrayUnion([groupId]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }),
      operation: 'joinGroup.transaction',
    );
  }

  Future<void> updateGroupMemberProfileInGroups({
    required String uid,
    required List<String> groupIds,
    required String displayName,
    required String teamName,
    required int avatarSeed,
    String? favoriteTeam,
    String? photoUrl,
  }) async {
    if (uid.trim().isEmpty || groupIds.isEmpty) return;
    final uniqueGroupIds = groupIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (uniqueGroupIds.isEmpty) return;

    // Pre-build chunks so every retry attempt reuses the same group-ID list.
    final chunks = <List<String>>[];
    for (var i = 0; i < uniqueGroupIds.length; i += _kGroupProfileBatchSize) {
      final end = i + _kGroupProfileBatchSize > uniqueGroupIds.length
          ? uniqueGroupIds.length
          : i + _kGroupProfileBatchSize;
      chunks.add(uniqueGroupIds.sublist(i, end));
    }

    if (kDebugMode) {
      debugPrint(
        '[group-sync] starting profile sync for uid=$uid '
        'across ${uniqueGroupIds.length} group(s) '
        'in ${chunks.length} chunk(s)',
      );
    }

    for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
      final chunkGroupIds = chunks[chunkIndex];

      // Capture hook reference for null-safety promotion inside the closure.
      final hook = _groupProfileSyncChunkHook;

      // Build the commit action; branches on test hook vs. real Firestore.
      Future<void> buildAndCommit() async {
        if (hook != null) {
          await hook(chunkIndex, chunkGroupIds);
          return;
        }
        final batch = _db.batch();
        for (final groupId in chunkGroupIds) {
          final memberRef = _db
              .collection('groups')
              .doc(groupId)
              .collection('members')
              .doc(uid);
          batch.set(memberRef, {
            'displayName': displayName,
            'teamName': teamName,
            'photoUrl': photoUrl,
            'avatarSeed': avatarSeed,
            'favoriteTeam': favoriteTeam,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await _withTimeout(
          batch.commit(),
          operation: 'updateGroupMemberProfileInGroups.batchCommit',
        );
      }

      if (kDebugMode) {
        debugPrint(
          '[group-sync] committing chunk ${chunkIndex + 1}/${chunks.length} '
          '(${chunkGroupIds.length} group(s))',
        );
      }

      // Throws if all retries are exhausted — deliberately NOT caught here so
      // the caller learns that some groups were not updated.  Chunks already
      // committed before this failure are not rolled back; the exception
      // message identifies the failing chunk and group IDs.
      await _retryChunkCommit(
        commitAction: buildAndCommit,
        chunkGroupIds: chunkGroupIds,
        chunkIndex: chunkIndex,
        totalChunks: chunks.length,
      );

      if (kDebugMode) {
        debugPrint(
          '[group-sync] chunk ${chunkIndex + 1}/${chunks.length} done '
          '(${chunkIndex + 1} of ${chunks.length} committed)',
        );
      }
    }

    if (kDebugMode) {
      debugPrint(
        '[group-sync] profile sync complete for uid=$uid '
        '(${uniqueGroupIds.length} group(s), ${chunks.length} chunk(s))',
      );
    }
  }

  Future<void> leaveGroup({
    required String groupId,
    required String uid,
  }) async {
    final groupRef = _db.collection('groups').doc(groupId);
    final memberRef = groupRef.collection('members').doc(uid);
    final userRef = _db.collection('users').doc(uid);

    await _withTimeout(
      _db.runTransaction((txn) async {
        final groupSnap = await txn.get(groupRef);
        final memberSnap = await txn.get(memberRef);

        if (memberSnap.exists) {
          txn.delete(memberRef);
          if (groupSnap.exists) {
            final currentCount =
                (groupSnap.data()?['memberCount'] as num?)?.toInt() ?? 0;
            txn.update(groupRef, {
              'memberCount': currentCount > 0 ? currentCount - 1 : 0,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }

        txn.set(userRef, {
          'groupIds': FieldValue.arrayRemove([groupId]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }),
      operation: 'leaveGroup.transaction',
    );
  }

  Future<void> deleteGroupAsAdmin({
    required String groupId,
    required String adminUid,
  }) async {
    final groupRef = _db.collection('groups').doc(groupId);
    final groupSnap = await _withTimeout(
      groupRef.get(),
      operation: 'deleteGroupAsAdmin.groupGet',
    );
    if (!groupSnap.exists) return;

    final data = groupSnap.data();
    final actualAdminUid = data?['adminUid'] as String?;
    if (actualAdminUid != adminUid) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Only group admin can delete the group',
      );
    }

    final membersSnap = await _withTimeout(
      groupRef.collection('members').get(),
      operation: 'deleteGroupAsAdmin.membersGet',
    );
    final memberUids = membersSnap.docs
        .map((d) => d.id)
        .toList(growable: false);

    // 2 writes per member (user update + member delete). Keep below 500 ops.
    const chunkSize = 200;
    for (var i = 0; i < memberUids.length; i += chunkSize) {
      final end = (i + chunkSize > memberUids.length)
          ? memberUids.length
          : i + chunkSize;
      final batch = _db.batch();
      for (final uid in memberUids.sublist(i, end)) {
        batch.set(_db.collection('users').doc(uid), {
          'groupIds': FieldValue.arrayRemove([groupId]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        batch.delete(groupRef.collection('members').doc(uid));
      }
      await _withTimeout(
        batch.commit(),
        operation: 'deleteGroupAsAdmin.batchCommit',
      );
    }

    await _withTimeout(
      groupRef.delete(),
      operation: 'deleteGroupAsAdmin.delete',
    );
  }

  Future<List<GroupMemberDocument>> getGroupMembers(String groupId) async {
    final snap = await _withTimeout(
      _db.collection('groups').doc(groupId).collection('members').get(),
      operation: 'getGroupMembers',
    );
    return snap.docs.map(GroupMemberDocument.fromFirestore).toList();
  }

  Stream<List<GroupMemberDocument>> streamGroupMembers(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(GroupMemberDocument.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<Map<String, String>> getUserPhotoUrls(List<String> uids) async {
    final clean = uids
        .map((uid) => uid.trim())
        .where((uid) => uid.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (clean.isEmpty) return const {};

    final out = <String, String>{};
    for (final uid in clean) {
      try {
        final doc = await _withTimeout(
          _db.collection('users').doc(uid).get(),
          operation: 'getUserPhotoUrls',
        );
        if (!doc.exists) continue;
        final data = doc.data();
        final photo = (data?['photoUrl'] as String?)?.trim() ?? '';
        if (photo.isEmpty) continue;
        out[doc.id] = photo;
      } catch (_) {
        // Some profiles may be unreadable by security rules (e.g. not self).
        // Ignore and continue with available member-level photoUrl data.
        if (kDebugMode) {
          debugPrint(
            '[group-members] failed loading fallback photo for uid=$uid',
          );
        }
      }
    }
    return out;
  }

  Future<bool> isInviteCodeTaken(String code) async {
    final snap = await _withTimeout(
      _db
          .collection('groups')
          .where('inviteCode', isEqualTo: code)
          .limit(1)
          .get(),
      operation: 'isInviteCodeTaken',
    );
    return snap.docs.isNotEmpty;
  }

  Future<List<String>> findGroupIdsForMember(String uid) async {
    final snap = await _withTimeout(
      _db
          .collectionGroup('members')
          .where(FieldPath.documentId, isEqualTo: uid)
          .get(),
      operation: 'findGroupIdsForMember',
    );

    final ids = <String>{};
    for (final doc in snap.docs) {
      final groupId = doc.reference.parent.parent?.id;
      if (groupId != null && groupId.isNotEmpty) {
        ids.add(groupId);
      }
    }
    return ids.toList(growable: false);
  }

  // ===== GROUP CHAT =====

  Stream<List<GroupChatMessageDocument>> streamGroupChatMessages({
    required String groupId,
    int limit = 250,
  }) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('chatMessages')
        .orderBy('createdAt', descending: false)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(GroupChatMessageDocument.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<void> sendGroupChatMessage({
    required String groupId,
    required String senderUid,
    required String senderDisplayName,
    required String senderTeamName,
    required GroupChatMessageType type,
    String? text,
    String? imageBase64,
  }) async {
    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 24));
    await _withTimeout(
      _db.collection('groups').doc(groupId).collection('chatMessages').add({
        'senderUid': senderUid,
        'senderDisplayName': senderDisplayName,
        'senderTeamName': senderTeamName,
        'type': type.name,
        if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
        if (imageBase64 != null && imageBase64.trim().isNotEmpty)
          'imageBase64': imageBase64.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
      }),
      operation: 'sendGroupChatMessage',
    );
  }

  // ===== PICKS =====

  String _legacyPicksDocId(String uid, String seasonKey, int dayNumber) =>
      '${uid}_${seasonKey}_$dayNumber';

  String _normalizedGroupId(String? groupId) {
    final cleaned = (groupId ?? '').trim();
    return cleaned.isEmpty ? '' : cleaned;
  }

  String _picksScopeKey(String? groupId) {
    final normalized = _normalizedGroupId(groupId);
    return normalized.isEmpty ? 'nogroup' : normalized;
  }

  String _picksDocId(
    String uid,
    String seasonKey,
    int dayNumber, {
    String? groupId,
  }) => '${uid}_${seasonKey}_${dayNumber}_${_picksScopeKey(groupId)}';

  List<PicksDocument> _dedupePicksDocs(Iterable<PicksDocument> docs) =>
      deduplicatePicks(docs);

  Future<void> savePicks({
    required String uid,
    required String seasonKey,
    required int dayNumber,
    required Map<String, PickOption> picksByMatchId,
    required String visibility,
    String? groupId,
    Object? score,
  }) async {
    final normalizedGroupId = _normalizedGroupId(groupId);
    final docId = _picksDocId(
      uid,
      seasonKey,
      dayNumber,
      groupId: normalizedGroupId,
    );
    if (score != null) {
      // Intentionally ignored: score is backend-authoritative.
    }

    final data = <String, dynamic>{
      'uid': uid,
      'seasonKey': seasonKey,
      'dayNumber': dayNumber,
      'picksByMatchId': {
        for (final e in picksByMatchId.entries) e.key: e.value.name,
      },
      'submittedAt': FieldValue.serverTimestamp(),
      'visibility': visibility,
      if (normalizedGroupId.isNotEmpty) 'groupId': normalizedGroupId,
    };
    // score/scoredAt are backend-authoritative and must not be written by client.
    final picksRef = _db.collection('picks').doc(docId);
    await _withTimeout(
      picksRef.set(data, SetOptions(merge: true)),
      operation: 'savePicks.set',
    );

    // Backward compatibility: delete legacy unscoped doc only when it is safe.
    final legacyDocId = _legacyPicksDocId(uid, seasonKey, dayNumber);
    if (legacyDocId == docId) return;
    final legacyRef = _db.collection('picks').doc(legacyDocId);
    final legacy = await _withTimeout(
      legacyRef.get(),
      operation: 'savePicks.legacyGet',
    );
    if (!legacy.exists) return;

    final legacyGroupId = (legacy.data()?['groupId'] as String?)?.trim() ?? '';
    final legacyIsSameScope =
        legacyGroupId.isEmpty || legacyGroupId == normalizedGroupId;
    if (legacyIsSameScope) {
      await _withTimeout(
        legacyRef.delete(),
        operation: 'savePicks.legacyDelete',
      );
    }
  }

  Future<PicksDocument?> getPicks({
    required String uid,
    required String seasonKey,
    required int dayNumber,
    String? groupId,
  }) async {
    final normalizedGroupId = _normalizedGroupId(groupId);
    final docId = _picksDocId(
      uid,
      seasonKey,
      dayNumber,
      groupId: normalizedGroupId,
    );
    final doc = await _withTimeout(
      _db.collection('picks').doc(docId).get(),
      operation: 'getPicks.scoped',
    );
    if (doc.exists) {
      return PicksDocument.fromFirestore(doc);
    }

    final legacyDoc = await _withTimeout(
      _db
          .collection('picks')
          .doc(_legacyPicksDocId(uid, seasonKey, dayNumber))
          .get(),
      operation: 'getPicks.legacy',
    );
    if (!legacyDoc.exists) return null;
    return PicksDocument.fromFirestore(legacyDoc);
  }

  Future<List<PicksDocument>> getPicksForMatchday({
    required String seasonKey,
    required int dayNumber,
    required List<String> uids,
    String? groupId,
  }) async {
    if (uids.isEmpty) return [];

    // Firestore 'whereIn' supports max 30 items
    final results = <PicksDocument>[];
    final scopedGroupId = groupId?.trim() ?? '';
    for (var i = 0; i < uids.length; i += 30) {
      final chunk = uids.sublist(
        i,
        i + 30 > uids.length ? uids.length : i + 30,
      );
      var query = _db
          .collection('picks')
          .where('seasonKey', isEqualTo: seasonKey)
          .where('dayNumber', isEqualTo: dayNumber);
      if (scopedGroupId.isNotEmpty) {
        query = query.where('groupId', isEqualTo: scopedGroupId);
      }
      final snap = await _withTimeout(
        query.where('uid', whereIn: chunk).get(),
        operation: 'getPicksForMatchday',
      );
      results.addAll(snap.docs.map(PicksDocument.fromFirestore));
    }
    return _dedupePicksDocs(results);
  }

  Stream<List<PicksDocument>> streamPicksForMatchday({
    required String seasonKey,
    required int dayNumber,
  }) {
    return _db
        .collection('picks')
        .where('seasonKey', isEqualTo: seasonKey)
        .where('dayNumber', isEqualTo: dayNumber)
        .snapshots()
        .map(
          (snap) =>
              _dedupePicksDocs(snap.docs.map(PicksDocument.fromFirestore)),
        );
  }

  Future<List<PicksDocument>> getPicksForUser({
    required String uid,
    required String seasonKey,
    String? groupId,
  }) async {
    var query = _db
        .collection('picks')
        .where('uid', isEqualTo: uid)
        .where('seasonKey', isEqualTo: seasonKey);
    final scopedGroupId = groupId?.trim() ?? '';
    if (scopedGroupId.isNotEmpty) {
      query = query.where('groupId', isEqualTo: scopedGroupId);
    }
    final snap = await _withTimeout(query.get(), operation: 'getPicksForUser');
    return _dedupePicksDocs(snap.docs.map(PicksDocument.fromFirestore));
  }

  Future<List<PicksDocument>> getPicksForSeason({
    required String seasonKey,
    String? groupId,
  }) async {
    var query = _db
        .collection('picks')
        .where('seasonKey', isEqualTo: seasonKey);
    final scopedGroupId = groupId?.trim() ?? '';
    if (scopedGroupId.isNotEmpty) {
      query = query.where('groupId', isEqualTo: scopedGroupId);
    }
    final snap = await _withTimeout(
      query.get(),
      operation: 'getPicksForSeason',
    );
    return _dedupePicksDocs(snap.docs.map(PicksDocument.fromFirestore));
  }

  Stream<List<PicksDocument>> streamPicksForSeason({
    required String seasonKey,
    String? groupId,
  }) {
    var query = _db
        .collection('picks')
        .where('seasonKey', isEqualTo: seasonKey);
    final scopedGroupId = groupId?.trim() ?? '';
    if (scopedGroupId.isNotEmpty) {
      query = query.where('groupId', isEqualTo: scopedGroupId);
    }
    return query.snapshots().map(
      (snap) => _dedupePicksDocs(snap.docs.map(PicksDocument.fromFirestore)),
    );
  }

  // ===== MATCHDAY DATA =====

  Future<void> saveMatchdayData({
    required String seasonKey,
    required int dayNumber,
    required List<PredictionMatch> matches,
    required Map<String, MatchOutcome> outcomesByMatchId,
    DateTime? lockTime,
    bool finalized = false,
  }) async {
    await _withTimeout(
      _db
          .collection('seasons')
          .doc(seasonKey)
          .collection('matchdays')
          .doc(dayNumber.toString())
          .set({
            'matches': matches
                .map(FirestoreSerializers.predictionMatchToMap)
                .toList(),
            'outcomesByMatchId': {
              for (final e in outcomesByMatchId.entries) e.key: e.value.name,
            },
            if (lockTime != null) 'lockTime': Timestamp.fromDate(lockTime),
            'updatedAt': FieldValue.serverTimestamp(),
            'finalized': finalized,
          }, SetOptions(merge: true)),
      operation: 'saveMatchdayData',
    );
  }

  Future<MatchdayDocument?> getMatchdayData({
    required String seasonKey,
    required int dayNumber,
  }) async {
    final doc = await _withTimeout(
      _db
          .collection('seasons')
          .doc(seasonKey)
          .collection('matchdays')
          .doc(dayNumber.toString())
          .get(),
      operation: 'getMatchdayData',
    );
    if (!doc.exists) return null;
    return MatchdayDocument.fromFirestore(
      doc,
      seasonKey: seasonKey,
      dayNumber: dayNumber,
    );
  }

  Stream<MatchdayDocument?> streamMatchdayData({
    required String seasonKey,
    required int dayNumber,
  }) {
    return _db
        .collection('seasons')
        .doc(seasonKey)
        .collection('matchdays')
        .doc(dayNumber.toString())
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          return MatchdayDocument.fromFirestore(
            doc,
            seasonKey: seasonKey,
            dayNumber: dayNumber,
          );
        });
  }

  Future<List<ApiFootballStanding>> getSeasonStandings({
    required String seasonKey,
  }) async {
    final doc = await _withTimeout(
      _db
          .collection('seasons')
          .doc(seasonKey)
          .collection('standings')
          .doc('current')
          .get(),
      operation: 'getSeasonStandings',
    );

    if (!doc.exists) return const [];
    final data = doc.data();
    final rows = data?['rows'];
    if (rows is! List) return const [];

    return rows
        .whereType<Map>()
        .map((e) => ApiFootballStanding.fromMap(e.cast<String, dynamic>()))
        .toList();
  }
}
