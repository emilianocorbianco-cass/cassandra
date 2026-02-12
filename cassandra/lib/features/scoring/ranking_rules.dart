int compareCassandraRanking({
  required double aTotal,
  required double bTotal,
  required double? aAverageOddsPlayed,
  required double? bAverageOddsPlayed,
  required String aTeamName,
  required String bTeamName,
}) {
  final totalCompare = bTotal.compareTo(aTotal);
  if (totalCompare != 0) return totalCompare;

  final aAvg = aAverageOddsPlayed ?? -1;
  final bAvg = bAverageOddsPlayed ?? -1;
  final avgCompare = bAvg.compareTo(aAvg);
  if (avgCompare != 0) return avgCompare;

  return aTeamName.compareTo(bTeamName);
}
