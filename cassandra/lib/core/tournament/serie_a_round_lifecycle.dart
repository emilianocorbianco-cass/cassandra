import 'round_lifecycle.dart';

/// Serie A round lifecycle: lock 30min before kickoff, 60h cluster gap,
/// 48h sudden-postpone window.
class SerieARoundLifecycle implements RoundLifecycle {
  const SerieARoundLifecycle();

  @override
  Duration get lockOffset => const Duration(minutes: 30);

  @override
  Duration get clusterGapThreshold => const Duration(hours: 60);

  @override
  Duration get suddenPostponeWindow => const Duration(hours: 48);
}
