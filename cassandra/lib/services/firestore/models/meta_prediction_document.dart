/// Score cache for meta-predictions.
class MetaPredictionScoreCache {
  final int? groupOrderPoints;
  final int? top8Points;
  final int? qualified16Points;
  final int? top4Points;
  final int totalPoints;

  const MetaPredictionScoreCache({
    this.groupOrderPoints,
    this.top8Points,
    this.qualified16Points,
    this.top4Points,
    required this.totalPoints,
  });

  factory MetaPredictionScoreCache.fromMap(Map<String, dynamic> m) {
    return MetaPredictionScoreCache(
      groupOrderPoints: m['groupOrderPoints'] as int?,
      top8Points: m['top8Points'] as int?,
      qualified16Points: m['qualified16Points'] as int?,
      top4Points: m['top4Points'] as int?,
      totalPoints: (m['totalPoints'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    if (groupOrderPoints != null) 'groupOrderPoints': groupOrderPoints,
    if (top8Points != null) 'top8Points': top8Points,
    if (qualified16Points != null) 'qualified16Points': qualified16Points,
    if (top4Points != null) 'top4Points': top4Points,
    'totalPoints': totalPoints,
  };
}

/// Firestore document for meta-predictions (group order, top 8, top 4, etc.).
///
/// Document ID: `{uid}_{tournamentId}`
/// Collection: `meta_predictions`
class MetaPredictionDocument {
  final String docId;
  final String uid;
  final String tournamentId;

  /// World Cup / Champions group stage: groupId → ordered list of team names.
  final Map<String, List<String>>? groupOrderPicks;

  /// Champions league phase: predicted top 8 direct qualifiers.
  final List<String>? top8Picks;

  /// Champions league phase: predicted 16 teams qualifying to R16.
  final List<String>? qualified16Picks;

  /// World Cup + Champions knockout: predicted top 4.
  final List<String>? top4Picks;

  /// Backend-computed score cache.
  final MetaPredictionScoreCache? scoreCache;

  final DateTime? submittedAt;

  const MetaPredictionDocument({
    required this.docId,
    required this.uid,
    required this.tournamentId,
    this.groupOrderPicks,
    this.top8Picks,
    this.qualified16Picks,
    this.top4Picks,
    this.scoreCache,
    this.submittedAt,
  });

  factory MetaPredictionDocument.fromMap(String docId, Map<String, dynamic> m) {
    Map<String, List<String>>? groupOrder;
    final rawGroupOrder = m['groupOrderPicks'];
    if (rawGroupOrder is Map) {
      groupOrder = {};
      for (final entry in rawGroupOrder.entries) {
        if (entry.key is String && entry.value is List) {
          groupOrder[entry.key as String] =
              (entry.value as List).whereType<String>().toList();
        }
      }
    }

    return MetaPredictionDocument(
      docId: docId,
      uid: (m['uid'] as String?) ?? '',
      tournamentId: (m['tournamentId'] as String?) ?? '',
      groupOrderPicks: groupOrder,
      top8Picks: (m['top8Picks'] as List?)?.whereType<String>().toList(),
      qualified16Picks:
          (m['qualified16Picks'] as List?)?.whereType<String>().toList(),
      top4Picks: (m['top4Picks'] as List?)?.whereType<String>().toList(),
      scoreCache: m['scoreCache'] is Map
          ? MetaPredictionScoreCache.fromMap(
              Map<String, dynamic>.from(m['scoreCache'] as Map),
            )
          : null,
      submittedAt: m['submittedAt'] is DateTime
          ? m['submittedAt'] as DateTime
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'tournamentId': tournamentId,
    if (groupOrderPicks != null) 'groupOrderPicks': groupOrderPicks,
    if (top8Picks != null) 'top8Picks': top8Picks,
    if (qualified16Picks != null) 'qualified16Picks': qualified16Picks,
    if (top4Picks != null) 'top4Picks': top4Picks,
  };
}
