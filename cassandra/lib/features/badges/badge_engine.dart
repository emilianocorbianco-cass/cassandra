import '../group/models/group_member.dart';
import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/models/score_breakdown.dart';
import 'models/badge_type.dart';

class CassandraBadgeEngine {
  static List<BadgeType> badgesForGroupMatchday({
    required GroupMember member,
    required int rank, // 1-based
    required int totalPlayers,
    required List<PredictionMatch> matches,
    required Map<String, PickOption> picksByMatchId,
    required Map<String, MatchOutcome> outcomesByMatchId,
    required DayScoreBreakdown day,
  }) {
    final badges = <BadgeType>[];

    // 👑 primo del gruppo
    if (rank == 1) badges.add(BadgeType.crown);

    // L ultimo del gruppo (solo se >1 giocatore)
    if (totalPlayers > 1 && rank == totalPlayers) badges.add(BadgeType.loser);

    // 👁️ 10/10 esatti
    if (day.correctCount == 10) badges.add(BadgeType.eyes);

    // 🦉 gufata sulla squadra del cuore
    if (_isOwl(member, matches, picksByMatchId, outcomesByMatchId)) {
      badges.add(BadgeType.owl);
    }

    badges.sort((a, b) => a.priority.compareTo(b.priority));
    return badges;
  }

  static bool _isOwl(
    GroupMember member,
    List<PredictionMatch> matches,
    Map<String, PickOption> picksByMatchId,
    Map<String, MatchOutcome> outcomesByMatchId,
  ) {
    final fav = member.favoriteTeam;
    if (fav == null || fav.trim().isEmpty) return false;

    final favLower = fav.trim().toLowerCase();

    for (final m in matches) {
      final isHome = m.homeTeam.toLowerCase() == favLower;
      final isAway = m.awayTeam.toLowerCase() == favLower;

      if (!isHome && !isAway) continue;

      final pick = picksByMatchId[m.id] ?? PickOption.none;
      final outcome = outcomesByMatchId[m.id] ?? MatchOutcome.voided;

      if (outcome.isVoided) continue;

      // “dai per vincente” → contiamo solo singola 1 o 2
      if (isHome && pick == PickOption.home && outcome == MatchOutcome.away) {
        return true;
      }
      if (isAway && pick == PickOption.away && outcome == MatchOutcome.home) {
        return true;
      }
    }

    return false;
  }
}
