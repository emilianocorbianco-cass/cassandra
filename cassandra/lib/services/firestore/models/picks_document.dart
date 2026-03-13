import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../features/predictions/models/pick_option.dart';

class PicksScoreCache {
  final double baseTotal;
  final int bonusPoints;
  final int oddsBonusPoints;
  final int correctBonusPoints;
  final double total;
  final int correctCount;
  final double? averageOddsPlayed;

  const PicksScoreCache({
    required this.baseTotal,
    required this.bonusPoints,
    required this.oddsBonusPoints,
    required this.correctBonusPoints,
    required this.total,
    required this.correctCount,
    this.averageOddsPlayed,
  });

  factory PicksScoreCache.fromMap(Map<String, dynamic> m) {
    return PicksScoreCache(
      baseTotal: (m['baseTotal'] as num?)?.toDouble() ?? 0,
      // Use num? → toInt() so that Firestore double values (e.g. 2.0, -1.0)
      // are accepted without throwing a TypeError from a direct `as int?` cast.
      bonusPoints: (m['bonusPoints'] as num?)?.toInt() ?? 0,
      oddsBonusPoints: (m['oddsBonusPoints'] as num?)?.toInt() ?? 0,
      correctBonusPoints: (m['correctBonusPoints'] as num?)?.toInt() ?? 0,
      total: (m['total'] as num?)?.toDouble() ?? 0,
      correctCount: (m['correctCount'] as num?)?.toInt() ?? 0,
      averageOddsPlayed: (m['averageOddsPlayed'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'baseTotal': baseTotal,
      'bonusPoints': bonusPoints,
      'oddsBonusPoints': oddsBonusPoints,
      'correctBonusPoints': correctBonusPoints,
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

    // Use is-Map guard instead of direct cast so a corrupt field (e.g. a List)
    // produces an empty picks map rather than a TypeError crash.
    final rawPicksRaw = d['picksByMatchId'];
    final rawPicks = rawPicksRaw is Map
        ? Map<String, dynamic>.from(rawPicksRaw)
        : <String, dynamic>{};
    final picks = <String, PickOption>{};
    for (final e in rawPicks.entries) {
      try {
        picks[e.key] = PickOption.values.byName(e.value as String);
      } catch (_) {
        // Silenced intentionally: unknown enum value is skipped per-entry so
        // one corrupt pick does not discard the whole PicksDocument.
        // Expected during schema evolution when new enum variants are not yet
        // known to older clients.
        debugPrint(
          '[picks] unknown PickOption "${e.value}" for match ${e.key} in doc ${doc.id}, skipping',
        );
      }
    }

    // Use is-Map guard so a corrupt 'score' field doesn't throw a CastError.
    final rawScoreRaw = d['score'];
    final rawScore = rawScoreRaw is Map
        ? Map<String, dynamic>.from(rawScoreRaw)
        : null;

    // Use is-String guard so a corrupt 'groupId' field (e.g. a number stored
    // by a buggy client) degrades to null rather than throwing a CastError.
    final rawGroupId = d['groupId'];
    final groupIdTrimmed = rawGroupId is String ? rawGroupId.trim() : null;

    return PicksDocument(
      docId: doc.id,
      uid: d['uid'] as String? ?? '',
      seasonKey: d['seasonKey'] as String? ?? '',
      dayNumber: d['dayNumber'] as int? ?? 0,
      groupId: (groupIdTrimmed == null || groupIdTrimmed.isEmpty)
          ? null
          : groupIdTrimmed,
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
