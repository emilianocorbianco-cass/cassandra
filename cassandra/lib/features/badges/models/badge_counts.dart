import 'badge_type.dart';

class BadgeCounts {
  final Map<BadgeType, int> byType;

  BadgeCounts._(this.byType);

  factory BadgeCounts.empty() {
    return BadgeCounts._({for (final t in BadgeType.values) t: 0});
  }

  int of(BadgeType type) => byType[type] ?? 0;

  void add(BadgeType type, [int amount = 1]) {
    byType[type] = (byType[type] ?? 0) + amount;
  }

  int get total => byType.values.fold(0, (a, b) => a + b);
}
