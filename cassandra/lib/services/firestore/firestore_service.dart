import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/state/app_settings.dart';
import '../../app/state/user_profile.dart';
import '../../features/predictions/models/pick_option.dart';
import '../../features/predictions/models/prediction_match.dart';
import '../../features/scoring/models/match_outcome.dart';
import '../../features/scoring/models/score_breakdown.dart';
import '../api_football/models/api_football_standing.dart';
import 'firestore_serializers.dart';
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
    List<String> groupIds = const [],
  }) async {
    await _db.collection('users').doc(uid).set({
      'displayName': profile.displayName,
      'teamName': profile.teamName,
      'favoriteTeam': profile.favoriteTeam,
      'email': profile.email,
      'photoUrl': profile.photoUrl,
      'language': cassandraLanguageToStorage(language),
      'defaultVisibility': predictionVisibilityToStorage(defaultVisibility),
      'avatarSeed': avatarSeed,
      'groupIds': groupIds,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
      'memberCount': 1,
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

  Future<void> joinGroup({
    required String groupId,
    required String uid,
    required String displayName,
    required String teamName,
    required int avatarSeed,
    String? favoriteTeam,
  }) async {
    final batch = _db.batch();

    // Add member subcollection doc
    batch.set(
      _db.collection('groups').doc(groupId).collection('members').doc(uid),
      {
        'displayName': displayName,
        'teamName': teamName,
        'avatarSeed': avatarSeed,
        'favoriteTeam': favoriteTeam,
        'joinedAt': FieldValue.serverTimestamp(),
        'role': 'member',
      },
    );

    // Increment memberCount
    batch.update(_db.collection('groups').doc(groupId), {
      'memberCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Add groupId to user's groupIds
    batch.update(_db.collection('users').doc(uid), {
      'groupIds': FieldValue.arrayUnion([groupId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> leaveGroup({
    required String groupId,
    required String uid,
  }) async {
    final batch = _db.batch();

    batch.delete(
      _db.collection('groups').doc(groupId).collection('members').doc(uid),
    );

    batch.update(_db.collection('groups').doc(groupId), {
      'memberCount': FieldValue.increment(-1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.update(_db.collection('users').doc(uid), {
      'groupIds': FieldValue.arrayRemove([groupId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
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

  Future<bool> isInviteCodeTaken(String code) async {
    final snap = await _db
        .collection('groups')
        .where('inviteCode', isEqualTo: code)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
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
    DayScoreBreakdown? score,
  }) async {
    final docId = _picksDocId(uid, seasonKey, dayNumber);

    final data = <String, dynamic>{
      'uid': uid,
      'seasonKey': seasonKey,
      'dayNumber': dayNumber,
      'picksByMatchId': {
        for (final e in picksByMatchId.entries) e.key: e.value.name,
      },
      'submittedAt': FieldValue.serverTimestamp(),
      'visibility': visibility,
    };

    if (score != null) {
      data['score'] = {
        'baseTotal': score.baseTotal,
        'bonusPoints': score.bonusPoints,
        'total': score.total,
        'correctCount': score.correctCount,
        if (score.averageOddsPlayed != null)
          'averageOddsPlayed': score.averageOddsPlayed,
      };
    }

    await _db.collection('picks').doc(docId).set(data);
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
  }) async {
    if (uids.isEmpty) return [];

    // Firestore 'whereIn' supports max 30 items
    final results = <PicksDocument>[];
    for (var i = 0; i < uids.length; i += 30) {
      final chunk = uids.sublist(
        i,
        i + 30 > uids.length ? uids.length : i + 30,
      );
      final snap = await _db
          .collection('picks')
          .where('seasonKey', isEqualTo: seasonKey)
          .where('dayNumber', isEqualTo: dayNumber)
          .where('uid', whereIn: chunk)
          .get();
      results.addAll(snap.docs.map(PicksDocument.fromFirestore));
    }
    return results;
  }

  Future<List<PicksDocument>> getPicksForUser({
    required String uid,
    required String seasonKey,
  }) async {
    final snap = await _db
        .collection('picks')
        .where('uid', isEqualTo: uid)
        .where('seasonKey', isEqualTo: seasonKey)
        .get();
    return snap.docs.map(PicksDocument.fromFirestore).toList();
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
