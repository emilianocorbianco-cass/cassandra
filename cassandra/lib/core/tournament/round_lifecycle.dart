/// Configuration values for round lock/unlock timing.
///
/// These values are passed to `computeMatchdayProgress()` which remains
/// a pure, generic function. This class only carries the tournament-specific
/// parameters.
abstract class RoundLifecycle {
  /// How long before the first kickoff predictions are locked.
  Duration get lockOffset;

  /// Gap between consecutive kickoffs that triggers a new cluster.
  Duration get clusterGapThreshold;

  /// Window after original kickoff beyond which a postponed match is voided.
  Duration get suddenPostponeWindow;
}
