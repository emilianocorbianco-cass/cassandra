/// A single entry in a leaderboard, carrying all data needed for tiebreaks.
class RankingEntry {
  final double total;
  final int correctCount;
  final double? averageOddsPlayed;
  final int? metaPredictionPoints;
  final String displayName;

  const RankingEntry({
    required this.total,
    required this.correctCount,
    this.averageOddsPlayed,
    this.metaPredictionPoints,
    required this.displayName,
  });
}

/// Abstract ranking comparator — different tournaments have different
/// tiebreak rules.
///
/// Serie A: total → averageOddsPlayed → name.
/// Tournaments: total → correctCount → metaPredictionPoints → name.
abstract class RankingComparator {
  int compare(RankingEntry a, RankingEntry b);
}
