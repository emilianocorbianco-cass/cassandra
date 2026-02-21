import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../features/predictions/models/prediction_match.dart';
import '../../../features/scoring/models/match_outcome.dart';
import '../firestore_serializers.dart';

class MatchdayDocument {
  final String seasonKey;
  final int dayNumber;
  final List<PredictionMatch> matches;
  final Map<String, MatchOutcome> outcomesByMatchId;
  final DateTime? lockTime;
  final DateTime updatedAt;
  final bool finalized;

  const MatchdayDocument({
    required this.seasonKey,
    required this.dayNumber,
    required this.matches,
    required this.outcomesByMatchId,
    this.lockTime,
    required this.updatedAt,
    required this.finalized,
  });

  factory MatchdayDocument.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String seasonKey,
    required int dayNumber,
  }) {
    final d = doc.data()!;

    final rawMatches = d['matches'] as List<dynamic>? ?? [];
    final matches = rawMatches
        .cast<Map<String, dynamic>>()
        .map(FirestoreSerializers.predictionMatchFromMap)
        .toList();

    final rawOutcomes = d['outcomesByMatchId'] as Map<String, dynamic>? ?? {};
    final outcomes = <String, MatchOutcome>{};
    for (final e in rawOutcomes.entries) {
      try {
        outcomes[e.key] = MatchOutcome.values.byName(e.value as String);
      } catch (_) {
        // Silenced intentionally: unknown enum value is skipped per-entry so
        // one corrupt record does not discard the whole matchday document.
        // This fires at most once per stored outcome (not a run-time hot path).
        debugPrint(
          '[matchday] unknown MatchOutcome "${e.value}" for match ${e.key}, skipping',
        );
      }
    }

    return MatchdayDocument(
      seasonKey: seasonKey,
      dayNumber: dayNumber,
      matches: matches,
      outcomesByMatchId: outcomes,
      lockTime: (d['lockTime'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      finalized: d['finalized'] as bool? ?? false,
    );
  }
}
