import 'ranking_comparator.dart';

/// Serie A ranking: total → averageOddsPlayed → name.
///
/// Delegates to the same logic as `compareCassandraRanking()`.
class SerieARankingComparator implements RankingComparator {
  const SerieARankingComparator();

  @override
  int compare(RankingEntry a, RankingEntry b) {
    final totalCmp = b.total.compareTo(a.total);
    if (totalCmp != 0) return totalCmp;

    final aAvg = a.averageOddsPlayed ?? -1;
    final bAvg = b.averageOddsPlayed ?? -1;
    final avgCmp = bAvg.compareTo(aAvg);
    if (avgCmp != 0) return avgCmp;

    return a.displayName.compareTo(b.displayName);
  }
}
