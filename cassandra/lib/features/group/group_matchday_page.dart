import 'package:flutter/material.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../leaderboards/models/matchday_data.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/scoring_engine.dart';
import '../scoring/models/score_breakdown.dart';
import 'mock_group_data.dart';
import 'models/group_member.dart';

class GroupMatchdayPage extends StatelessWidget {
  const GroupMatchdayPage({
    super.key,
    required this.matchday,
    required this.members,
    required this.groupName,
  });

  final MatchdayData matchday;
  final List<GroupMember> members;
  final String groupName;

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  Map<String, MatchOutcome> _effectiveOutcomes(dynamic appState) {
    final saved = appState.hasSavedOutcomesForMatchday(matchday.dayNumber)
        ? appState.outcomesForMatchday(matchday.dayNumber)
        : const <String, MatchOutcome>{};

    if (saved.isEmpty) return matchday.outcomesByMatchId;

    return <String, MatchOutcome>{...matchday.outcomesByMatchId, ...saved};
  }

  Map<String, PickOption> _picksForMember(
    dynamic appState,
    GroupMember member,
    List<PredictionMatch> matches,
  ) {
    final uid = appState.profile.id;

    // Tu: preferisci i picks salvati per quella giornata
    if (member.id == uid) {
      if (appState.hasSavedPicksForMatchday(matchday.dayNumber)) {
        return appState.currentUserPicksForMatchday(matchday.dayNumber);
      }

      // fallback: se non hai ancora salvato, usa i picks correnti (se esistono)
      final current =
          appState.currentUserPicksByMatchId as Map<String, PickOption>?;
      if (current != null && current.isNotEmpty) return current;
    }

    // Altri membri: DEMO deterministico per (memberId + dayNumber)
    return mockPicksForMember('${member.id}_${matchday.dayNumber}', matches);
  }

  @override
  Widget build(BuildContext context) {
    final appState = CassandraScope.of(context);

    // non notificano: safe in build
    appState.ensureCurrentUserPicksHistoryLoaded();
    appState.ensureOutcomesHistoryLoaded();
    appState.ensureCurrentUserPicksLoaded();

    final outcomes = _effectiveOutcomes(appState);
    final matches = matchday.matches;

    final totalMatches = matches.length;
    final gradedCount = matches.where((m) {
      final o = outcomes[m.id] ?? MatchOutcome.pending;
      return !o.isPending;
    }).length;

    final daysLabel = formatMatchdayDaysItalian(matches.map((m) => m.kickoff));
    final resultsLabel = gradedCount == totalMatches
        ? 'risultati: $gradedCount/$totalMatches'
        : 'risultati: $gradedCount/$totalMatches (parziale)';

    final savedOutcomes = appState.hasSavedOutcomesForMatchday(
      matchday.dayNumber,
    );
    final outcomesTag = savedOutcomes ? 'OUT: SALVATI' : 'OUT: runtime';

    final rows = members.map((member) {
      final picks = _picksForMember(appState, member, matches);
      final day = CassandraScoringEngine.computeDayScore(
        matches: matches,
        picksByMatchId: picks,
        outcomesByMatchId: outcomes,
      );
      return _Row(member: member, picks: picks, day: day);
    }).toList();

    rows.sort((a, b) {
      final t = b.day.total.compareTo(a.day.total);
      if (t != 0) return t;

      final aAvg = a.day.averageOddsPlayed ?? -1;
      final bAvg = b.day.averageOddsPlayed ?? -1;
      final o = bAvg.compareTo(aAvg);
      if (o != 0) return o;

      return a.member.teamName.compareTo(b.member.teamName);
    });

    final uid = appState.profile.id;

    return Scaffold(
      appBar: AppBar(
        title: Text('Giornata ${matchday.dayNumber} • $groupName'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        daysLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        resultsLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: CassandraColors.slate,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        outcomesTag,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: CassandraColors.slate,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final isMe = r.member.id == uid;

                  final total = formatOdds(r.day.total);
                  final avg = r.day.averageOddsPlayed == null
                      ? '-'
                      : formatOdds(r.day.averageOddsPlayed!);

                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _avatarColorFromSeed(
                          r.member.avatarSeed,
                        ).withAlpha(40),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: CassandraColors.primary,
                          ),
                        ),
                      ),
                      title: Text(
                        isMe ? '${r.member.teamName} (tu)' : r.member.teamName,
                      ),
                      subtitle: Text(
                        '${r.member.displayName}\n'
                        'esatti: ${r.day.correctCount}/$totalMatches • bonus: ${r.day.bonusPoints} • quota media: $avg',
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        total,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row {
  _Row({required this.member, required this.picks, required this.day});

  final GroupMember member;
  final Map<String, PickOption> picks;
  final DayScoreBreakdown day;
}
