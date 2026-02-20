import 'package:cloud_firestore/cloud_firestore.dart';

enum GroupChatMessageType { text, sticker, image }

class GroupChatMessageDocument {
  final String id;
  final String senderUid;
  final String senderDisplayName;
  final String senderTeamName;
  final GroupChatMessageType type;
  final String? text;
  final String? imageBase64;
  final DateTime createdAt;

  const GroupChatMessageDocument({
    required this.id,
    required this.senderUid,
    required this.senderDisplayName,
    required this.senderTeamName,
    required this.type,
    this.text,
    this.imageBase64,
    required this.createdAt,
  });

  factory GroupChatMessageDocument.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawType = (data['type'] as String? ?? 'text').trim();
    final parsedType = GroupChatMessageType.values
        .where((v) {
          return v.name == rawType;
        })
        .fold<GroupChatMessageType?>(null, (acc, value) => value);

    return GroupChatMessageDocument(
      id: doc.id,
      senderUid: (data['senderUid'] as String? ?? '').trim(),
      senderDisplayName: (data['senderDisplayName'] as String? ?? '').trim(),
      senderTeamName: (data['senderTeamName'] as String? ?? '').trim(),
      type: parsedType ?? GroupChatMessageType.text,
      text: (data['text'] as String?)?.trim(),
      imageBase64: (data['imageBase64'] as String?)?.trim(),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  String get senderLabel {
    final team = senderTeamName.trim();
    if (team.isNotEmpty) return team;
    final display = senderDisplayName.trim();
    if (display.isNotEmpty) return display;
    return 'User';
  }
}
