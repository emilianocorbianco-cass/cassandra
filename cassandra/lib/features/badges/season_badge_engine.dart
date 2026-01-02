import '../leaderboards/models/season_leaderboard_entry.dart';
import 'models/badge_type.dart';

class CassandraSeasonBadgeEngine {
  static List<BadgeType> badgesForSeason({
    required SeasonLeaderboardEntry entry,
    required int rank,
    required int totalPlayers,
  }) {
    final badges = <BadgeType>[];

    if (rank == 1) badges.add(BadgeType.crown);
    if (totalPlayers > 1 && rank == totalPlayers) badges.add(BadgeType.loser);

    final hasPerfect = entry.matchdays.any((d) => d.day.correctCount == 10);
    if (hasPerfect) badges.add(BadgeType.eyes);

    // “Owl” season: se è successo almeno una volta in stagione.
    // Per ora lo semplifichiamo: se nelle breakdown di qualche giornata c'è stato un delta
    // negativo su una partita che coinvolge favorite team + pick singola vincente sbagliata
    // lo calcoliamo meglio quando colleghiamo i match reali e un profilo utente completo.
    // Quindi: per ora NIENTE owl qui (evitiamo falsi positivi).
    // badges.add(BadgeType.owl);

    badges.sort((a, b) => a.priority.compareTo(b.priority));
    return badges;
  }
}
