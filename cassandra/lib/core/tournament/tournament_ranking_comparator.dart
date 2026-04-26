import 'ranking_comparator.dart';

/// Tournament ranking (World Cup / Champions):
/// total → correctCount → metaPredictionPoints → name.
class TournamentRankingComparator implements RankingComparator {
  const TournamentRankingComparator();

  @override
  int compare(RankingEntry a, RankingEntry b) {
    final totalCmp = b.total.compareTo(a.total);
    if (totalCmp != 0) return totalCmp;

    final correctCmp = b.correctCount.compareTo(a.correctCount);
    if (correctCmp != 0) return correctCmp;

    final aMeta = a.metaPredictionPoints ?? -1;
    final bMeta = b.metaPredictionPoints ?? -1;
    final metaCmp = bMeta.compareTo(aMeta);
    if (metaCmp != 0) return metaCmp;

    return a.displayName.compareTo(b.displayName);
  }
}
