enum MatchOutcome {
  home, // 1
  draw, // X
  away, // 2
  voided, // partita non giocata/annullata
}

extension MatchOutcomeX on MatchOutcome {
  String get label {
    switch (this) {
      case MatchOutcome.home:
        return '1';
      case MatchOutcome.draw:
        return 'X';
      case MatchOutcome.away:
        return '2';
      case MatchOutcome.voided:
        return 'Ø';
    }
  }

  bool get isVoided => this == MatchOutcome.voided;
}
