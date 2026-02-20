import 'package:cloud_firestore/cloud_firestore.dart';

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
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

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

    await _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  Future<void> updateUserField(String uid, Map<String, dynamic> fields) async {
    fields['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection('users').doc(uid).update(fields);
  }

  Future<void> mergeUserField(String uid, Map<String, dynamic> fields) async {
    fields['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection('users').doc(uid).set(fields, SetOptions(merge: true));
  }

  Future<void> addUserFcmToken({
    required String uid,
    required String token,
  }) async {
    final cleaned = token.trim();
    if (cleaned.isEmpty) return;
    await _db.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([cleaned]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeUserFcmToken({
    required String uid,
    required String token,
  }) async {
    final cleaned = token.trim();
    if (cleaned.isEmpty) return;
    await _db.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayRemove([cleaned]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ===== GROUPS =====

  Future<String> createGroup({
    required String name,
    required String adminUid,
    required String inviteCode,
  }) async {
    final docRef = await _db.collection('groups').add({
      'name': name,
      'inviteCode': inviteCode,
      'adminUid': adminUid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'memberCount': 0,
    });
    return docRef.id;
  }

  Future<GroupDocument?> getGroupByInviteCode(String code) async {
    final snap = await _db
        .collection('groups')
        .where('inviteCode', isEqualTo: code)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return GroupDocument.fromFirestore(snap.docs.first);
  }

  Future<GroupDocument?> getGroup(String groupId) async {
    final doc = await _db.collection('groups').doc(groupId).get();
    if (!doc.exists) return null;
    return GroupDocument.fromFirestore(doc);
  }

  Future<void> updateGroupImageUrl({
    required String groupId,
    required String? imageUrl,
  }) async {
    final cleaned = (imageUrl ?? '').trim();
    await _db.collection('groups').doc(groupId).set({
      'imageUrl': cleaned.isEmpty ? null : cleaned,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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

    await _db.runTransaction((txn) async {
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
    });
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

    var batch = _db.batch();
    var pendingWrites = 0;
    for (final groupId in uniqueGroupIds) {
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
      pendingWrites += 1;

      if (pendingWrites >= 350) {
        await batch.commit();
        batch = _db.batch();
        pendingWrites = 0;
      }
    }

    if (pendingWrites > 0) {
      await batch.commit();
    }
  }

  Future<void> leaveGroup({
    required String groupId,
    required String uid,
  }) async {
    final groupRef = _db.collection('groups').doc(groupId);
    final memberRef = groupRef.collection('members').doc(uid);
    final userRef = _db.collection('users').doc(uid);

    await _db.runTransaction((txn) async {
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
    });
  }

  Future<void> deleteGroupAsAdmin({
    required String groupId,
    required String adminUid,
  }) async {
    final groupRef = _db.collection('groups').doc(groupId);
    final groupSnap = await groupRef.get();
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

    final membersSnap = await groupRef.collection('members').get();
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
      await batch.commit();
    }

    await groupRef.delete();
  }

  Future<List<GroupMemberDocument>> getGroupMembers(String groupId) async {
    final snap = await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .get();
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
        final doc = await _db.collection('users').doc(uid).get();
        if (!doc.exists) continue;
        final data = doc.data();
        final photo = (data?['photoUrl'] as String?)?.trim() ?? '';
        if (photo.isEmpty) continue;
        out[doc.id] = photo;
      } catch (_) {
        // Some profiles may be unreadable by security rules (e.g. not self).
        // Ignore and continue with available member-level photoUrl data.
      }
    }
    return out;
  }

  Future<bool> isInviteCodeTaken(String code) async {
    final snap = await _db
        .collection('groups')
        .where('inviteCode', isEqualTo: code)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<List<String>> findGroupIdsForMember(String uid) async {
    final snap = await _db
        .collectionGroup('members')
        .where(FieldPath.documentId, isEqualTo: uid)
        .get();

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
    await _db.collection('groups').doc(groupId).collection('chatMessages').add({
      'senderUid': senderUid,
      'senderDisplayName': senderDisplayName,
      'senderTeamName': senderTeamName,
      'type': type.name,
      if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
      if (imageBase64 != null && imageBase64.trim().isNotEmpty)
        'imageBase64': imageBase64.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });
  }

  // ===== PICKS =====

  String _picksDocId(String uid, String seasonKey, int dayNumber) =>
      '${uid}_${seasonKey}_$dayNumber';

  Future<void> savePicks({
    required String uid,
    required String seasonKey,
    required int dayNumber,
    required Map<String, PickOption> picksByMatchId,
    required String visibility,
    String? groupId,
    Object? score,
  }) async {
    final docId = _picksDocId(uid, seasonKey, dayNumber);
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
      if ((groupId ?? '').trim().isNotEmpty) 'groupId': groupId!.trim(),
    };
    // score/scoredAt are backend-authoritative and must not be written by client.
    await _db.collection('picks').doc(docId).set(data, SetOptions(merge: true));
  }

  Future<PicksDocument?> getPicks({
    required String uid,
    required String seasonKey,
    required int dayNumber,
  }) async {
    final docId = _picksDocId(uid, seasonKey, dayNumber);
    final doc = await _db.collection('picks').doc(docId).get();
    if (!doc.exists) return null;
    return PicksDocument.fromFirestore(doc);
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
      final snap = await query.where('uid', whereIn: chunk).get();
      results.addAll(snap.docs.map(PicksDocument.fromFirestore));
    }
    return results;
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
          (snap) => snap.docs
              .map(PicksDocument.fromFirestore)
              .toList(growable: false),
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
    final snap = await query.get();
    return snap.docs.map(PicksDocument.fromFirestore).toList();
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
    final snap = await query.get();
    return snap.docs.map(PicksDocument.fromFirestore).toList(growable: false);
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
      (snap) =>
          snap.docs.map(PicksDocument.fromFirestore).toList(growable: false),
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
    await _db
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
        }, SetOptions(merge: true));
  }

  Future<MatchdayDocument?> getMatchdayData({
    required String seasonKey,
    required int dayNumber,
  }) async {
    final doc = await _db
        .collection('seasons')
        .doc(seasonKey)
        .collection('matchdays')
        .doc(dayNumber.toString())
        .get();
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
    final doc = await _db
        .collection('seasons')
        .doc(seasonKey)
        .collection('standings')
        .doc('current')
        .get();

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
