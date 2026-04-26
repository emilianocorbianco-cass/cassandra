import '../meta_prediction_spec.dart';

/// World Cup group order meta-prediction.
///
/// Predict the finishing order of all 12 groups (4 teams each).
/// +1 point per correct position → max 48 points.
class WorldCupGroupOrderMeta implements MetaPredictionSpec {
  const WorldCupGroupOrderMeta();

  @override
  String get id => 'world-cup-group-order';

  @override
  String get displayName => 'Ordine gironi';

  /// Number of groups in the 2026 World Cup.
  static const int groupCount = 12;

  /// Positions per group to predict.
  static const int positionsPerGroup = 4;

  /// Points per correct position.
  static const int pointsPerCorrect = 1;

  /// Maximum possible points (12 groups × 4 positions × 1 point).
  static const int maxPoints = groupCount * positionsPerGroup * pointsPerCorrect;

  /// Score the user's group order predictions against actual results.
  int score(
    Map<String, List<String>> userPicks,
    Map<String, List<String>> actualOrder,
  ) {
    var points = 0;
    for (final groupId in actualOrder.keys) {
      final predicted = userPicks[groupId];
      final actual = actualOrder[groupId];
      if (predicted == null || actual == null) continue;
      for (var i = 0; i < actual.length && i < predicted.length; i++) {
        if (predicted[i] == actual[i]) points += pointsPerCorrect;
      }
    }
    return points;
  }
}

/// World Cup top 4 meta-prediction.
///
/// Predict the 4 semifinalists before the knockout phase.
/// Scoring: 0 correct = 0, 1 = 2, 2 = 5, 3 = 10, 4 = 20.
class WorldCupTop4Meta implements MetaPredictionSpec {
  const WorldCupTop4Meta();

  @override
  String get id => 'world-cup-top-4';

  @override
  String get displayName => 'Prime 4';

  /// Points awarded based on number of correct teams in top 4.
  static const List<int> pointsTiers = [0, 2, 5, 10, 20];

  /// Score the user's top 4 prediction against actual results.
  int score(List<String> userPicks, List<String> actualTop4) {
    final actualSet = actualTop4.toSet();
    final correctCount =
        userPicks.where((team) => actualSet.contains(team)).length;
    if (correctCount >= pointsTiers.length) return pointsTiers.last;
    return pointsTiers[correctCount];
  }
}
