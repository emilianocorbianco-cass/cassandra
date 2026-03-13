class MatchScoreBreakdown {
  final String matchId;

  /// Punti base della singola partita (senza bonus giornata)
  final double basePoints;

  /// True se il pronostico è corretto (conta per il bonus)
  final bool correct;

  /// Quota “giocata” ai fini della quota media (spareggio).
  /// - null se non hai giocato la partita
  /// - null se la partita è voided (0 per tutti; niente rischio reale)
  final double? playedOdds;

  /// Nota diagnostica (utile per debug)
  final String note;

  const MatchScoreBreakdown({
    required this.matchId,
    required this.basePoints,
    required this.correct,
    required this.playedOdds,
    required this.note,
  });
}

class DayScoreBreakdown {
  final List<MatchScoreBreakdown> matchBreakdowns;

  final double baseTotal;

  /// Somma dei due bonus (odds + correct count).
  final int bonusPoints;

  /// Bonus basato sulla somma delle quote vincenti.
  final int oddsBonusPoints;

  /// Bonus basato sul numero di pronostici corretti.
  final int correctBonusPoints;

  final double total;

  final int correctCount;
  final double? averageOddsPlayed;

  const DayScoreBreakdown({
    required this.matchBreakdowns,
    required this.baseTotal,
    required this.bonusPoints,
    required this.oddsBonusPoints,
    required this.correctBonusPoints,
    required this.total,
    required this.correctCount,
    required this.averageOddsPlayed,
  });
}
