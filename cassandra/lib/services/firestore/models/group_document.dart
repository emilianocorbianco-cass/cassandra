import 'package:cloud_firestore/cloud_firestore.dart';

class GroupDocument {
  final String id;
  final String name;
  final String inviteCode;
  final String adminUid;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int memberCount;

  const GroupDocument({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.adminUid,
    this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.memberCount,
  });

  factory GroupDocument.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    return GroupDocument(
      id: doc.id,
      name: d['name'] as String? ?? '',
      inviteCode: d['inviteCode'] as String? ?? '',
      adminUid: d['adminUid'] as String? ?? '',
      imageUrl: d['imageUrl'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      // Use num? → toInt() so Firestore double values (e.g. 1.0 from a Cloud
      // Function) are accepted without a TypeError.
      memberCount: (d['memberCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class GroupMemberDocument {
  final String uid;
  final String displayName;
  final String teamName;
  final String? photoUrl;
  final int avatarSeed;
  final String? favoriteTeam;
  final DateTime joinedAt;
  final String role;

  const GroupMemberDocument({
    required this.uid,
    required this.displayName,
    required this.teamName,
    this.photoUrl,
    required this.avatarSeed,
    this.favoriteTeam,
    required this.joinedAt,
    required this.role,
  });

  factory GroupMemberDocument.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    return GroupMemberDocument(
      uid: doc.id,
      displayName: d['displayName'] as String? ?? '',
      teamName: d['teamName'] as String? ?? '',
      photoUrl: d['photoUrl'] as String?,
      avatarSeed: (d['avatarSeed'] as num?)?.toInt() ?? 0,
      favoriteTeam: d['favoriteTeam'] as String?,
      joinedAt: (d['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      role: d['role'] as String? ?? 'member',
    );
  }
}
