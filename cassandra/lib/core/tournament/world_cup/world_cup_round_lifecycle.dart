import '../round_lifecycle.dart';

/// World Cup group stage: lock 30 min before kickoff (same as Serie A).
class WorldCupGroupRoundLifecycle implements RoundLifecycle {
  const WorldCupGroupRoundLifecycle();

  @override
  Duration get lockOffset => const Duration(minutes: 30);

  @override
  Duration get clusterGapThreshold => const Duration(hours: 60);

  @override
  Duration get suddenPostponeWindow => const Duration(hours: 48);
}

/// World Cup knockout: lock 5 min before first match of the block.
/// Unlock next round 30 min after the last match of the block.
class WorldCupKnockoutRoundLifecycle implements RoundLifecycle {
  const WorldCupKnockoutRoundLifecycle();

  @override
  Duration get lockOffset => const Duration(minutes: 5);

  @override
  Duration get clusterGapThreshold => const Duration(hours: 60);

  @override
  Duration get suddenPostponeWindow => const Duration(hours: 48);
}
