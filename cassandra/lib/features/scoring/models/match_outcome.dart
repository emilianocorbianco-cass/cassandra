enum MatchOutcome {
  /// Risultato non ancora disponibile (partita non conclusa o outcome non caricato).
  pending,

  /// 1
  home,

  /// X
  draw,

  /// 2
  away,

  /// Partita annullata / non valida ai fini del punteggio.
  voided,
}

extension MatchOutcomeX on MatchOutcome {
  bool get isPending => this == MatchOutcome.pending;
  bool get isVoided => this == MatchOutcome.voided;

  /// “Graded” = abbiamo un outcome definitivo (anche voided).
  bool get isGraded => !isPending;

  /// Etichetta breve per UI (coerente con PickOption.label)
  String get label =>
      const {
        MatchOutcome.home: '1',
        MatchOutcome.draw: 'X',
        MatchOutcome.away: '2',
        MatchOutcome.pending: '-',
        MatchOutcome.voided: 'ann.',
      }[this] ??
      name; // fallback se un domani aggiungi valori all'enum
}

/// When the match was decided — relevant only for knockout tournament formats.
/// Serie A ignores this entirely.
enum DecidedIn {
  regulation,
  extraTime,
  penalties,
}

/// A [MatchOutcome] optionally paired with [DecidedIn] for knockout scoring.
///
/// Serie A code continues to use bare [MatchOutcome]; this wrapper exists
/// for tournament formats where the *when* matters for scoring.
class MatchResult {
  final MatchOutcome outcome;
  final DecidedIn? decidedIn;

  const MatchResult(this.outcome, [this.decidedIn]);

  bool get isPending => outcome.isPending;
  bool get isVoided => outcome.isVoided;
  bool get isGraded => outcome.isGraded;
}
