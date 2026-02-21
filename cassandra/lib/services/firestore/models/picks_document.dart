import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../features/predictions/models/pick_option.dart';

class PicksScoreCache {
  final double baseTotal;
  final int bonusPoints;
  final double total;
  final int correctCount;
  final double? averageOddsPlayed;

  const PicksScoreCache({
    required this.baseTotal,
    required this.bonusPoints,
    required this.total,
    required this.correctCount,
    this.averageOddsPlayed,
  });

  factory PicksScoreCache.fromMap(Map<String, dynamic> m) {
    return PicksScoreCache(
      baseTotal: (m['baseTotal'] as num?)?.toDouble() ?? 0,
      bonusPoints: m['bonusPoints'] as int? ?? 0,
      total: (m['total'] as num?)?.toDouble() ?? 0,
      correctCount: m['correctCount'] as int? ?? 0,
      averageOddsPlayed: (m['averageOddsPlayed'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'baseTotal': baseTotal,
      'bonusPoints': bonusPoints,
      'total': total,
      'correctCount': correctCount,
      if (averageOddsPlayed != null) 'averageOddsPlayed': averageOddsPlayed,
    };
  }
}

class PicksDocument {
  final String docId;
  final String uid;
  final String seasonKey;
  final int dayNumber;
  final String? groupId;
  final Map<String, PickOption> picksByMatchId;
  final DateTime submittedAt;
  final String visibility;
  final PicksScoreCache? score;

  const PicksDocument({
    required this.docId,
    required this.uid,
    required this.seasonKey,
    required this.dayNumber,
    this.groupId,
    required this.picksByMatchId,
    required this.submittedAt,
    required this.visibility,
    this.score,
  });

  factory PicksDocument.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;

    final rawPicks = d['picksByMatchId'] as Map<String, dynamic>? ?? {};
    final picks = <String, PickOption>{};
    for (final e in rawPicks.entries) {
      try {
        picks[e.key] = PickOption.values.byName(e.value as String);
      } catch (_) {}
    }

    final rawScore = d['score'] as Map<String, dynamic>?;

    return PicksDocument(
      docId: doc.id,
      uid: d['uid'] as String? ?? '',
      seasonKey: d['seasonKey'] as String? ?? '',
      dayNumber: d['dayNumber'] as int? ?? 0,
      groupId: (d['groupId'] as String?)?.trim().isEmpty ?? true
          ? null
          : (d['groupId'] as String?)!.trim(),
      picksByMatchId: picks,
      submittedAt: (d['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      visibility: d['visibility'] as String? ?? 'friends',
      score: rawScore != null ? PicksScoreCache.fromMap(rawScore) : null,
    );
  }
}

/// Deduplicates [docs] keeping the most recent entry per
/// (uid, seasonKey, dayNumber, groupId) tuple.
///
/// When two docs share the same tuple, the one with the later [PicksDocument.submittedAt]
/// wins. Equal timestamps are broken by [PicksDocument.docId] lexicographic order
/// (higher wins).
List<PicksDocument> deduplicatePicks(Iterable<PicksDocument> docs) {
  final byKey = <String, PicksDocument>{};
  for (final doc in docs) {
    final key =
        '${doc.uid}|${doc.seasonKey}|${doc.dayNumber}|${doc.groupId?.trim() ?? ''}';
    final prev = byKey[key];
    if (prev == null ||
        doc.submittedAt.isAfter(prev.submittedAt) ||
        (doc.submittedAt.isAtSameMomentAs(prev.submittedAt) &&
            doc.docId.compareTo(prev.docId) > 0)) {
      byKey[key] = doc;
    }
  }
  return byKey.values.toList(growable: false);
}
