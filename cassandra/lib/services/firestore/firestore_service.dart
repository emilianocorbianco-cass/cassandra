import 'dart:async';
import 'dart:math';

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
  static const String _kGroupInvitesCollection = 'group_invites';
  static const int _kDefaultGroupMaxMembers = 50;

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
      'language': cassandraLanguageToStorage(language),
      'defaultVisibility': predictionVisibilityToStorage(defaultVisibility),
      'avatarSeed': avatarSeed,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Only include nullable fields when non-null so that merge: true does not
    // overwrite existing Firestore values with null.
    if (profile.favoriteTeam != null) {
      data['favoriteTeam'] = profile.favoriteTeam;
    }
    if (profile.email != null) {
      data['email'] = profile.email;
    }
    if (profile.photoUrl != null) {
      data['photoUrl'] = profile.photoUrl;
    }
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

  /// Returns the UID of an existing user doc whose `email` matches [email]
  /// but whose document ID is different from [currentUid], or `null` if no
  /// such duplicate exists.
  ///
  /// This is used at sign-in time to detect stale accounts left behind by
  /// a previous Firebase Auth deletion-then-recreation cycle.
  Future<String?> findExistingUidForEmail({
    required String email,
    required String currentUid,
  }) async {
    if (email.isEmpty) return null;
    try {
      final snap = await _withTimeout(
        _db.collection('users').where('email', isEqualTo: email).limit(2).get(),
        operation: 'findExistingUidForEmail',
      );
      for (final doc in snap.docs) {
        if (doc.id != currentUid) return doc.id;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[findExistingUidForEmail] query failed: $e');
      }
    }
    return null;
  }

  /// Migrates Firestore data from a stale (deleted-auth) user to the current
  /// user.  This covers:
  ///
  /// 1. **groupIds** — merges old user's group list into the new user doc.
  /// 2. **member docs** — for each group the old UID belongs to, creates a new
  ///    member doc under [toUid] (copying the old doc's data) and deletes the
  ///    old one.  Also updates `adminUid` on the group doc if the old UID was
  ///    the admin.
  /// 3. **picks** — re-writes each pick doc so that `uid` points to [toUid].
  ///    Because the doc-ID encodes the UID, we create a new doc and delete the
  ///    old one.
  /// 4. **old user doc** — deleted after the migration completes.
  Future<void> migrateStaleUserData({
    required String fromUid,
    required String toUid,
    required String displayName,
    required String teamName,
    required int avatarSeed,
    String? favoriteTeam,
    String? photoUrl,
  }) async {
    if (fromUid == toUid) return;
    try {
      // 1. Read old user doc to get its groupIds.
      final oldUserSnap = await _db.collection('users').doc(fromUid).get();
      if (!oldUserSnap.exists) return;
      final oldData = oldUserSnap.data() ?? {};
      final oldGroupIds = List<String>.from(
        (oldData['groupIds'] as List<dynamic>?) ?? [],
      );

      // 2. For each group, migrate the member doc and fix adminUid if needed.
      for (final groupId in oldGroupIds) {
        try {
          final oldMemberRef = _db
              .collection('groups')
              .doc(groupId)
              .collection('members')
              .doc(fromUid);
          final oldMemberSnap = await oldMemberRef.get();
          if (oldMemberSnap.exists) {
            final memberData = Map<String, dynamic>.from(
              oldMemberSnap.data() ?? {},
            );
            final wasAdmin = memberData['role'] == 'admin';

            // Check if the new UID already has a member doc.
            final newMemberRef = _db
                .collection('groups')
                .doc(groupId)
                .collection('members')
                .doc(toUid);
            final newMemberSnap = await newMemberRef.get();

            if (!newMemberSnap.exists) {
              // Create new member doc preserving the old data.
              memberData['displayName'] = displayName;
              memberData['teamName'] = teamName;
              memberData['avatarSeed'] = avatarSeed;
              memberData['favoriteTeam'] = favoriteTeam;
              memberData['photoUrl'] = photoUrl;
              memberData['updatedAt'] = FieldValue.serverTimestamp();
              await newMemberRef.set(memberData);
            } else if (wasAdmin) {
              // New member already exists — just promote to admin.
              await newMemberRef.update({'role': 'admin'});
            }

            // Delete old member doc.
            await oldMemberRef.delete();

            // If old UID was admin, transfer ownership.
            if (wasAdmin) {
              await _db.collection('groups').doc(groupId).update({
                'adminUid': toUid,
              });
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '[migrateStaleUserData] member migration failed for '
              'group $groupId: $e',
            );
          }
        }
      }

      // 3. Migrate picks: re-key each pick doc from fromUid to toUid.
      try {
        final picksSnap = await _db
            .collection('picks')
            .where('uid', isEqualTo: fromUid)
            .get();
        for (final pickDoc in picksSnap.docs) {
          final pickData = Map<String, dynamic>.from(pickDoc.data());
          pickData['uid'] = toUid;
          pickData['migratedFrom'] = fromUid;
          pickData['migratedAt'] = FieldValue.serverTimestamp();

          // Build new doc ID by replacing the UID prefix.
          final oldDocId = pickDoc.id;
          final newDocId = oldDocId.replaceFirst(fromUid, toUid);

          // Only create if the target doesn't already exist.
          final existingPick = await _db
              .collection('picks')
              .doc(newDocId)
              .get();
          if (!existingPick.exists) {
            await _db.collection('picks').doc(newDocId).set(pickData);
          }
          await pickDoc.reference.delete();
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[migrateStaleUserData] picks migration failed: $e');
        }
      }

      // 4. Merge groupIds into the new user doc and delete the old one.
      if (oldGroupIds.isNotEmpty) {
        await _db.collection('users').doc(toUid).set({
          'groupIds': FieldValue.arrayUnion(oldGroupIds),
        }, SetOptions(merge: true));
      }
      await _db.collection('users').doc(fromUid).delete();

      if (kDebugMode) {
        debugPrint(
          '[migrateStaleUserData] migrated $fromUid → $toUid '
          '(groups: ${oldGroupIds.length})',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[migrateStaleUserData] failed: $e');
      }
    }
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
    int maxMembers = _kDefaultGroupMaxMembers,
    String? creatorDisplayName,
    String? creatorTeamName,
    int? creatorAvatarSeed,
    String? creatorFavoriteTeam,
    String? creatorPhotoUrl,
  }) async {
    final normalizedInviteCode = inviteCode.trim().toUpperCase();
    final groupRef = _db.collection('groups').doc();
    final inviteRef = _db
        .collection(_kGroupInvitesCollection)
        .doc(normalizedInviteCode);
    final hasCreatorMembership = creatorAvatarSeed != null;

    await _withTimeout(
      _db.runTransaction((txn) async {
        final inviteSnap = await txn.get(inviteRef);
        if (inviteSnap.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'already-exists',
            message: 'Invite code already exists',
          );
        }

        txn.set(groupRef, {
          'name': name,
          'inviteCode': normalizedInviteCode,
          'adminUid': adminUid,
          'maxMembers': maxMembers,
          'deleting': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'memberCount': hasCreatorMembership ? 1 : 0,
          'competitions': ['serie-a'],
        });
        txn.set(inviteRef, {
          'groupId': groupRef.id,
          'groupName': name,
          'inviteCode': normalizedInviteCode,
          'adminUid': adminUid,
          'maxMembers': maxMembers,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (hasCreatorMembership) {
          final memberRef = groupRef.collection('members').doc(adminUid);
          final userRef = _db.collection('users').doc(adminUid);
          txn.set(memberRef, {
            'displayName': (creatorDisplayName ?? '').trim(),
            'teamName': (creatorTeamName ?? '').trim(),
            'photoUrl': creatorPhotoUrl,
            'avatarSeed': creatorAvatarSeed,
            'favoriteTeam': creatorFavoriteTeam,
            'joinedAt': FieldValue.serverTimestamp(),
            'role': 'admin',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          txn.set(userRef, {
            'groupIds': FieldValue.arrayUnion([groupRef.id]),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }),
      operation: 'createGroup',
    );
    return groupRef.id;
  }

  Future<GroupDocument?> getGroupByInviteCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return null;

    final inviteSnap = await _withTimeout(
      _db.collection(_kGroupInvitesCollection).doc(normalized).get(),
      operation: 'getGroupByInviteCode',
    );

    if (inviteSnap.exists) {
      final data = inviteSnap.data() ?? const <String, dynamic>{};
      final groupId = (data['groupId'] as String? ?? '').trim();
      if (groupId.isNotEmpty) {
        final groupName = (data['groupName'] as String? ?? '').trim();
        final adminUid = (data['adminUid'] as String? ?? '').trim();
        final maxMembers = (data['maxMembers'] as num?)?.toInt() ?? 50;
        final createdAt =
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        final updatedAt =
            (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        return GroupDocument(
          id: groupId,
          name: groupName,
          inviteCode: normalized,
          adminUid: adminUid,
          createdAt: createdAt,
          updatedAt: updatedAt,
          memberCount: 0,
          maxMembers: maxMembers,
        );
      }
    }

    // ── Fallback: group_invites doc missing — query groups by inviteCode ──
    // The group_invites collection may be empty if the maintenance backfill
    // hasn't run yet. Fall back to a direct query on the groups collection.
    // This may fail if security rules don't allow the query for non-members.
    if (kDebugMode) {
      debugPrint(
        '[firestore] invite doc missing for $normalized, '
        'falling back to groups query',
      );
    }

    try {
      final groupQuery = await _withTimeout(
        _db
            .collection('groups')
            .where('inviteCode', isEqualTo: normalized)
            .limit(1)
            .get(),
        operation: 'getGroupByInviteCode.fallback',
      );
      if (groupQuery.docs.isEmpty) return null;

      final groupDoc = groupQuery.docs.first;
      final groupData = groupDoc.data();

      // Self-heal: recreate the missing group_invites document.
      final adminUid = (groupData['adminUid'] as String? ?? '').trim();
      final groupName = (groupData['name'] as String? ?? '').trim();
      unawaited(
        _db
            .collection(_kGroupInvitesCollection)
            .doc(normalized)
            .set({
              'groupId': groupDoc.id,
              'groupName': groupName,
              'inviteCode': normalized,
              'adminUid': adminUid,
              'maxMembers': (groupData['maxMembers'] as num?)?.toInt() ?? 50,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            })
            .catchError((_) {
              // Best-effort: rules may prevent this write for non-admins.
            }),
      );

      return GroupDocument.fromFirestore(groupDoc);
    } catch (e) {
      // Security rules may block the query for non-members.
      if (kDebugMode) {
        debugPrint('[firestore] invite fallback query failed: $e');
      }
      return null;
    }
  }

  Future<GroupDocument?> getGroup(String groupId) async {
    final doc = await _withTimeout(
      _db.collection('groups').doc(groupId).get(),
      operation: 'getGroup',
    );
    if (!doc.exists) return null;
    return GroupDocument.fromFirestore(doc);
  }

  /// Fetches multiple [GroupDocument]s by their IDs in batch.
  /// Firestore `whereIn` supports up to 30 IDs per query, so we chunk
  /// automatically.
  Future<List<GroupDocument>> getGroups(List<String> groupIds) async {
    if (groupIds.isEmpty) return const [];
    final results = <GroupDocument>[];
    for (var i = 0; i < groupIds.length; i += 30) {
      final chunk = groupIds.sublist(i, min(i + 30, groupIds.length));
      final snap = await _withTimeout(
        _db
            .collection('groups')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
        operation: 'getGroups',
      );
      results.addAll(snap.docs.map(GroupDocument.fromFirestore));
    }
    return results;
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
        final currentCount =
            (groupSnap.data()?['memberCount'] as num?)?.toInt() ?? 0;
        final maxMembers =
            (groupSnap.data()?['maxMembers'] as num?)?.toInt() ?? 0;
        final deleting = groupSnap.data()?['deleting'] == true;
        if (deleting) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'failed-precondition',
            message: 'Group is being deleted',
          );
        }
        if (!memberSnap.exists &&
            maxMembers > 0 &&
            currentCount >= maxMembers) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'resource-exhausted',
            message: 'Group is full',
          );
        }
        final baseMemberData = <String, dynamic>{
          'displayName': displayName,
          'teamName': teamName,
          'photoUrl': photoUrl,
          'avatarSeed': avatarSeed,
          'favoriteTeam': favoriteTeam,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (!memberSnap.exists) {
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
        final memberRefs = chunkGroupIds
            .map(
              (groupId) => _db
                  .collection('groups')
                  .doc(groupId)
                  .collection('members')
                  .doc(uid),
            )
            .toList(growable: false);
        final memberSnapshots = await _withTimeout(
          Future.wait(memberRefs.map((ref) => ref.get())),
          operation: 'updateGroupMemberProfileInGroups.prefetchMembers',
        );

        final existingMemberRefs = memberSnapshots
            .where((snap) => snap.exists)
            .map((snap) => snap.reference)
            .toList(growable: false);
        if (existingMemberRefs.isEmpty) {
          return;
        }

        final batch = _db.batch();
        for (final memberRef in existingMemberRefs) {
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
    final inviteCode = (data?['inviteCode'] as String? ?? '')
        .trim()
        .toUpperCase();
    if (actualAdminUid != adminUid) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Only group admin can delete the group',
      );
    }

    await _withTimeout(
      groupRef.set({
        'deleting': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      operation: 'deleteGroupAsAdmin.markDeleting',
    );

    if (inviteCode.isNotEmpty) {
      try {
        await _withTimeout(
          _db.collection(_kGroupInvitesCollection).doc(inviteCode).delete(),
          operation: 'deleteGroupAsAdmin.deleteInviteEarly',
        );
      } on FirebaseException catch (e) {
        if (e.code != 'not-found') rethrow;
      }
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

    // Defensive cleanup: remove any stale invite docs still pointing to groupId.
    final staleInvites = await _withTimeout(
      _db
          .collection(_kGroupInvitesCollection)
          .where('groupId', isEqualTo: groupId)
          .limit(20)
          .get(),
      operation: 'deleteGroupAsAdmin.findStaleInvites',
    );
    if (staleInvites.docs.isNotEmpty) {
      final staleBatch = _db.batch();
      for (final doc in staleInvites.docs) {
        staleBatch.delete(doc.reference);
      }
      await _withTimeout(
        staleBatch.commit(),
        operation: 'deleteGroupAsAdmin.deleteStaleInvites',
      );
    }
  }

  Future<void> resumeDeletingGroupsForAdmin({
    required String adminUid,
    int limit = 30,
  }) async {
    final uid = adminUid.trim();
    if (uid.isEmpty) return;

    final groupsSnap = await _withTimeout(
      _db
          .collection('groups')
          .where('adminUid', isEqualTo: uid)
          .limit(limit)
          .get(),
      operation: 'resumeDeletingGroupsForAdmin.query',
    );
    if (groupsSnap.docs.isEmpty) return;

    for (final groupDoc in groupsSnap.docs) {
      final data = groupDoc.data();
      if (data['deleting'] != true) continue;
      try {
        await deleteGroupAsAdmin(groupId: groupDoc.id, adminUid: uid);
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[groups] resumeDeletingGroupsForAdmin failed '
            'group=${groupDoc.id}: $e',
          );
        }
      }
    }
  }

  Future<List<GroupMemberDocument>> getGroupMembers(String groupId) async {
    final snap = await _withTimeout(
      _db.collection('groups').doc(groupId).collection('members').get(),
      operation: 'getGroupMembers',
    );
    return snap.docs.map(GroupMemberDocument.fromFirestore).toList();
  }

  /// Repairs group membership consistency for the given [uid].
  ///
  /// 1. For every groupId in the user doc, verifies that a member doc exists
  ///    in that group's subcollection. If missing, recreates it.
  /// 2. Discovers orphaned memberships (member docs that exist in groups not
  ///    listed in the user doc) and adds them back to the user's groupIds.
  ///
  /// This runs at most once per app session (controlled by the caller).
  Future<void> repairGroupMembershipIfNeeded({
    required String uid,
    required String displayName,
    required String teamName,
    required int avatarSeed,
    String? favoriteTeam,
    String? photoUrl,
  }) async {
    if (uid.trim().isEmpty) return;

    try {
      // 1. Read user doc groupIds
      final userDoc = await _withTimeout(
        _db.collection('users').doc(uid).get(),
        operation: 'repairMembership.readUser',
      );
      final userGroupIds = <String>{};
      if (userDoc.exists) {
        final raw = userDoc.data()?['groupIds'];
        if (raw is List) {
          for (final id in raw) {
            final s = (id as String? ?? '').trim();
            if (s.isNotEmpty) userGroupIds.add(s);
          }
        }
      }

      // 2. Discover membership via collectionGroup query
      final discoveredGroupIds = await findGroupIdsForMember(uid);

      // 3. Merge: union of user doc groupIds and discovered memberships
      final allGroupIds = <String>{...userGroupIds, ...discoveredGroupIds};
      if (allGroupIds.isEmpty) return;

      // 4. Verify each membership and repair if needed.
      //    Each group is checked independently so a permission error on one
      //    group doesn't abort the entire repair.
      final missingMemberDocs =
          <String>[]; // groups where member doc is missing
      final orphanedGroupIds = <String>[]; // discovered but not in user doc

      for (final groupId in allGroupIds) {
        try {
          final memberRef = _db
              .collection('groups')
              .doc(groupId)
              .collection('members')
              .doc(uid);
          final memberSnap = await memberRef.get();

          if (!memberSnap.exists) {
            // Check if the group itself still exists
            final groupSnap = await _db.collection('groups').doc(groupId).get();
            if (groupSnap.exists && groupSnap.data()?['deleting'] != true) {
              missingMemberDocs.add(groupId);
            }
          }
        } catch (e) {
          // permission-denied means we have no member doc — treat as missing.
          if (kDebugMode) {
            debugPrint('[repair] could not verify membership in $groupId: $e');
          }
          missingMemberDocs.add(groupId);
        }

        if (!userGroupIds.contains(groupId)) {
          orphanedGroupIds.add(groupId);
        }
      }

      // 5. Recreate missing member docs
      for (final groupId in missingMemberDocs) {
        try {
          await joinGroup(
            groupId: groupId,
            uid: uid,
            displayName: displayName,
            teamName: teamName,
            avatarSeed: avatarSeed,
            favoriteTeam: favoriteTeam,
            photoUrl: photoUrl,
          );
          if (kDebugMode) {
            debugPrint('[repair] recreated member doc in $groupId for $uid');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[repair] failed to recreate member in $groupId: $e');
          }
        }
      }

      // 6. Add orphaned groupIds back to user doc
      if (orphanedGroupIds.isNotEmpty) {
        await _db.collection('users').doc(uid).set({
          'groupIds': FieldValue.arrayUnion(orphanedGroupIds),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (kDebugMode) {
          debugPrint(
            '[repair] added ${orphanedGroupIds.length} orphaned groupIds '
            'back to user doc',
          );
        }
      }

      if (kDebugMode &&
          (missingMemberDocs.isNotEmpty || orphanedGroupIds.isNotEmpty)) {
        debugPrint(
          '[repair] membership repair complete: '
          'recreated=${missingMemberDocs.length} '
          'orphans=${orphanedGroupIds.length}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[repair] membership repair failed: $e');
      }
    }
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

  Future<bool> isInviteCodeTaken(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    final doc = await _withTimeout(
      _db.collection(_kGroupInvitesCollection).doc(normalized).get(),
      operation: 'isInviteCodeTaken',
    );
    return doc.exists;
  }

  Future<List<String>> findGroupIdsForMember(String uid) async {
    // Discovery via collectionGroup is not reliable because
    // FieldPath.documentId in a collection group query matches the full
    // document path, not just the document name.  The primary discovery
    // source is the user doc's groupIds list; this method probes each
    // known group instead.
    try {
      final userDoc = await _withTimeout(
        _db.collection('users').doc(uid).get(),
        operation: 'findGroupIdsForMember.readUser',
      );
      if (!userDoc.exists) return const [];
      final raw = userDoc.data()?['groupIds'];
      if (raw is! List) return const [];
      final ids = <String>[];
      for (final id in raw) {
        final s = (id as String? ?? '').trim();
        if (s.isNotEmpty) ids.add(s);
      }
      return ids;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[findGroupIdsForMember] query failed: $e');
      }
      return const [];
    }
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
    // Wrapped in try-catch so that a failure in legacy cleanup never shadows
    // the already-successful main write above.
    final legacyDocId = _legacyPicksDocId(uid, seasonKey, dayNumber);
    if (legacyDocId == docId) return;
    try {
      final legacyRef = _db.collection('picks').doc(legacyDocId);
      final legacy = await _withTimeout(
        legacyRef.get(),
        operation: 'savePicks.legacyGet',
      );
      if (!legacy.exists) return;

      final legacyGroupId =
          (legacy.data()?['groupId'] as String?)?.trim() ?? '';
      final legacyIsSameScope =
          legacyGroupId.isEmpty || legacyGroupId == normalizedGroupId;
      if (legacyIsSameScope) {
        await _withTimeout(
          legacyRef.delete(),
          operation: 'savePicks.legacyDelete',
        );
      }
    } catch (e) {
      // Best-effort: the main write already succeeded.
      debugPrint('[savePicks] legacy cleanup failed (non-fatal): $e');
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

  Stream<List<ApiFootballStanding>> streamSeasonStandings({
    required String seasonKey,
  }) {
    return _db
        .collection('seasons')
        .doc(seasonKey)
        .collection('standings')
        .doc('current')
        .snapshots()
        .map((doc) {
          if (!doc.exists) return const <ApiFootballStanding>[];
          final data = doc.data();
          final rows = data?['rows'];
          if (rows is! List) return const <ApiFootballStanding>[];
          return rows
              .whereType<Map>()
              .map(
                (e) => ApiFootballStanding.fromMap(e.cast<String, dynamic>()),
              )
              .toList();
        });
  }

  // ---------------------------------------------------------------------------
  // Dev / test data seeding
  // ---------------------------------------------------------------------------

  /// Aggiunge due utenti mock al gruppo identificato da [inviteCode] con pick
  /// per la giornata [dayNumber] della stagione [seasonKey].
  ///
  /// Utile per testare leaderboard e UI di gruppo senza creare account reali.
  /// Restituisce un messaggio di esito leggibile dall'operatore.
  Future<String> seedMockGroupMembers({
    required String inviteCode,
    required String seasonKey,
    required int dayNumber,
  }) async {
    // 1. Trova il gruppo tramite invite code
    final group = await getGroupByInviteCode(inviteCode);
    if (group == null) {
      return 'Gruppo non trovato per il codice: $inviteCode';
    }
    final groupId = group.id;

    // 2. Recupera i match ID dalla giornata
    final matchday = await getMatchdayData(
      seasonKey: seasonKey,
      dayNumber: dayNumber,
    );
    if (matchday == null || matchday.matches.isEmpty) {
      return 'Giornata $dayNumber non trovata o vuota per la stagione $seasonKey';
    }
    final matchIds = matchday.matches.map((m) => m.id).toList();

    // 3. Definizione utenti mock
    const mockUsers = [
      (
        uid: 'mock_topolino_test',
        displayName: 'Topolino',
        teamName: 'Juventus',
        avatarSeed: 42,
      ),
      (
        uid: 'mock_pippo_test',
        displayName: 'Pippo',
        teamName: 'Inter',
        avatarSeed: 77,
      ),
    ];

    // Sequenze di pick variabili per simulare scelte diverse
    const pickSequences = [
      ['home', 'draw', 'away', 'homeDraw', 'drawAway', 'homeAway'],
      ['away', 'homeDraw', 'home', 'drawAway', 'draw', 'homeAway'],
    ];

    for (var i = 0; i < mockUsers.length; i++) {
      final user = mockUsers[i];
      final seq = pickSequences[i % pickSequences.length];

      // Membro del gruppo
      await _withTimeout(
        _db
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc(user.uid)
            .set({
              'displayName': user.displayName,
              'teamName': user.teamName,
              'photoUrl': null,
              'avatarSeed': user.avatarSeed,
              'favoriteTeam': null,
              'joinedAt': FieldValue.serverTimestamp(),
              'role': 'member',
            }),
        operation: 'seedMockGroupMembers.addMember',
      );

      // Pick per la giornata
      final picksByMatchId = <String, String>{};
      for (var j = 0; j < matchIds.length; j++) {
        picksByMatchId[matchIds[j]] = seq[j % seq.length];
      }

      final docId = '${user.uid}_${seasonKey}_${dayNumber}_$groupId';
      await _withTimeout(
        _db.collection('picks').doc(docId).set({
          'uid': user.uid,
          'seasonKey': seasonKey,
          'dayNumber': dayNumber,
          'picksByMatchId': picksByMatchId,
          'submittedAt': FieldValue.serverTimestamp(),
          'visibility': 'public',
          'groupId': groupId,
        }),
        operation: 'seedMockGroupMembers.savePicks',
      );

      if (kDebugMode) {
        debugPrint(
          '[seed] ${user.displayName} (${user.uid}) aggiunto a $groupId '
          'con ${picksByMatchId.length} pick',
        );
      }
    }

    return 'Seeding completato: ${mockUsers.map((u) => u.displayName).join(", ")} '
        'aggiunti al gruppo $groupId (${matchIds.length} pick ciascuno)';
  }
}
