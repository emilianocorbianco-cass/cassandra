enum BadgeType {
  crown, // 👑 primo del gruppo
  eyes, // 👁️ 10/10 esatti
  owl, // 🦉 gufata sulla squadra del cuore
  loser, // L ultimo
}

extension BadgeTypeX on BadgeType {
  /// Priorità di visualizzazione: più basso = più importante.
  int get priority {
    switch (this) {
      case BadgeType.crown:
        return 0;
      case BadgeType.eyes:
        return 1;
      case BadgeType.owl:
        return 2;
      case BadgeType.loser:
        return 3;
    }
  }

  String get titleIt {
    switch (this) {
      case BadgeType.crown:
        return 'Corona di Re';
      case BadgeType.eyes:
        return 'Gli occhi di Cassandra';
      case BadgeType.owl:
        return 'Gufo';
      case BadgeType.loser:
        return 'Loser';
    }
  }

  String title({required bool english}) {
    if (!english) return titleIt;
    switch (this) {
      case BadgeType.crown:
        return 'King\'s Crown';
      case BadgeType.eyes:
        return 'Cassandra\'s Eyes';
      case BadgeType.owl:
        return 'Owl';
      case BadgeType.loser:
        return 'Loser';
    }
  }
}
