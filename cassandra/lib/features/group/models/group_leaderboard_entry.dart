import '../../predictions/models/pick_option.dart';
import '../../scoring/models/score_breakdown.dart';
import 'group_member.dart';

class GroupLeaderboardEntry {
  final GroupMember member;

  /// Scelte dell’utente (matchId -> PickOption)
  final Map<String, PickOption> picksByMatchId;

  /// Risultato scoring completo della giornata (base + bonus + totale)
  final DayScoreBreakdown day;

  const GroupLeaderboardEntry({
    required this.member,
    required this.picksByMatchId,
    required this.day,
  });
}
