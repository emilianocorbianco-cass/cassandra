/// Regole Cassandra per matchday con recuperi/posticipi.
///
/// Obiettivi:
/// - lock: -30 min dal primo kickoff della matchday
/// - "primaryDone": finito il primo cluster (gruppo principale) => sblocca matchday successiva
/// - "finalDone": finite (o nulle) tutte le partite della matchday => calcola classifica matchday
/// - rinvio improvviso: se non final entro 48h dal kickoff originario => partita nulla
/// - matchday valida: >= 6 partite valide giocate
///
/// Nota: questo file è *model-agnostic*: integra passando getter/callback.

library;

enum FixtureResolution { pending, finalResult, voidNull }

class MatchdayProgress {
  final DateTime lockAt;
  final bool isLocked;

  /// Primo cluster completato (tutte final oppure nulle)
  final bool primaryDone;

  /// Tutte le partite della matchday risolte (final oppure nulle)
  final bool finalDone;

  final int totalFixtures;

  /// Partite effettivamente giocate e finite (non nulle)
  final int playedFixtures;

  /// Partite nulle (rinvio improvviso non recuperato entro 48h, cancellate, ecc.)
  final int voidFixtures;

  const MatchdayProgress({
    required this.lockAt,
    required this.isLocked,
    required this.primaryDone,
    required this.finalDone,
    required this.totalFixtures,
    required this.playedFixtures,
    required this.voidFixtures,
  });

  bool get isValidMatchday => playedFixtures >= 6;
}

/// Clusterizza per kickoff: nuovo cluster se tra due kickoff consecutivi c’è un gap > [gapThreshold].
List<List<T>> clusterByKickoff<T>(
  Iterable<T> items, {
  required DateTime Function(T) kickoff,
  Duration gapThreshold = const Duration(hours: 60),
}) {
  final sorted = items.toList()
    ..sort((a, b) => kickoff(a).compareTo(kickoff(b)));
  if (sorted.isEmpty) return const [];

  final clusters = <List<T>>[
    <T>[sorted.first],
  ];

  for (var i = 1; i < sorted.length; i++) {
    final prev = sorted[i - 1];
    final curr = sorted[i];
    final gap = kickoff(curr).difference(kickoff(prev));

    if (gap > gapThreshold) {
      clusters.add(<T>[curr]);
    } else {
      clusters.last.add(curr);
    }
  }

  return clusters;
}

bool defaultIsFinalStatus(String statusShort) {
  // API-Football tipicamente: FT, AET, PEN
  return statusShort == 'FT' || statusShort == 'AET' || statusShort == 'PEN';
}

bool defaultIsImmediatelyVoidStatus(String statusShort) {
  // CANC spesso è "Cancelled". Se hai altri codici, aggiungili nel wiring.
  return statusShort == 'CANC';
}

/// Risoluzione partita secondo regola Cassandra:
/// - final => finalResult
/// - cancellata => voidNull subito
/// - altrimenti: se non final entro 48h dal kickoff originario => voidNull
/// - altrimenti pending
FixtureResolution resolveFixture<T>(
  T fixture, {
  required DateTime now,
  required DateTime Function(T) kickoff,
  required String Function(T) statusShort,
  required DateTime Function(T) originKickoff,
  bool Function(String) isFinalStatus = defaultIsFinalStatus,
  bool Function(String) isImmediatelyVoidStatus =
      defaultIsImmediatelyVoidStatus,
  Duration suddenPostponeWindow = const Duration(hours: 48),
}) {
  final st = statusShort(fixture);
  final origin = originKickoff(fixture);
  final scheduled = kickoff(fixture);

  if (isFinalStatus(st)) {
    // Se è stato giocato oltre la finestra 48h dal kickoff originario => NULLA (anche se FT)
    if (scheduled.isAfter(origin.add(suddenPostponeWindow))) {
      return FixtureResolution.voidNull;
    }
    return FixtureResolution.finalResult;
  }
  if (isImmediatelyVoidStatus(st)) {
    return FixtureResolution.voidNull;
  }

  final deadline = origin.add(suddenPostponeWindow);

  if (now.isAfter(deadline)) {
    return FixtureResolution.voidNull;
  }
  return FixtureResolution.pending;
}

/// Calcola stato matchday (lock/primaryDone/finalDone) con logica recuperi.
MatchdayProgress computeMatchdayProgress<T>(
  Iterable<T> fixtures, {
  required DateTime now,
  required DateTime Function(T) kickoff,
  required DateTime Function(T) originKickoff,
  required String Function(T) statusShort,
  Duration lockOffset = const Duration(minutes: 30),
  Duration clusterGapThreshold = const Duration(hours: 60),
  Duration suddenPostponeWindow = const Duration(hours: 48),
  bool Function(String) isFinalStatus = defaultIsFinalStatus,
  bool Function(String) isImmediatelyVoidStatus =
      defaultIsImmediatelyVoidStatus,
}) {
  final list = fixtures.toList();
  if (list.isEmpty) {
    // Matchday vuota: considerala non giocabile/chiusa.
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return MatchdayProgress(
      lockAt: epoch,
      isLocked: true,
      primaryDone: true,
      finalDone: true,
      totalFixtures: 0,
      playedFixtures: 0,
      voidFixtures: 0,
    );
  }

  final sorted = list..sort((a, b) => kickoff(a).compareTo(kickoff(b)));
  final firstKickoff = kickoff(sorted.first);
  final lockAt = firstKickoff.subtract(lockOffset);

  final clusters = clusterByKickoff(
    sorted,
    kickoff: kickoff,
    gapThreshold: clusterGapThreshold,
  );
  final primaryCluster = clusters.isNotEmpty ? clusters.first : <T>[];

  FixtureResolution res(T f) => resolveFixture(
    f,
    now: now,
    kickoff: kickoff,
    statusShort: statusShort,
    originKickoff: originKickoff,
    suddenPostponeWindow: suddenPostponeWindow,
    isFinalStatus: isFinalStatus,
    isImmediatelyVoidStatus: isImmediatelyVoidStatus,
  );

  final primaryDone = primaryCluster.every(
    (f) => res(f) != FixtureResolution.pending,
  );
  final finalDone = sorted.every((f) => res(f) != FixtureResolution.pending);

  final played = sorted
      .where((f) => res(f) == FixtureResolution.finalResult)
      .length;
  final voided = sorted
      .where((f) => res(f) == FixtureResolution.voidNull)
      .length;

  return MatchdayProgress(
    lockAt: lockAt,
    isLocked: now.isAfter(lockAt),
    primaryDone: primaryDone,
    finalDone: finalDone,
    totalFixtures: sorted.length,
    playedFixtures: played,
    voidFixtures: voided,
  );
}

/// Bonus scaling richiesto da TASKS:
/// scala “corretti” su 0..10 rispetto alle partite effettivamente giocate.
int scaleCorrectToTen({required int correct, required int playedFixtures}) {
  if (playedFixtures <= 0) return 0;
  final raw = (correct * 10) / playedFixtures;
  final rounded = raw.round();
  if (rounded < 0) return 0;
  if (rounded > 10) return 10;
  return rounded;
}
