import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../app/theme/cassandra_colors.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/prediction_match.dart';

class LiveMatchDetailsPage extends StatelessWidget {
  const LiveMatchDetailsPage({super.key, required this.match});

  final PredictionMatch match;

  bool _isNotStarted(String? rawStatus) {
    final status = (rawStatus ?? '').trim().toUpperCase();
    return status.isEmpty ||
        status == 'NS' ||
        status == 'TBD' ||
        status == 'PST';
  }

  String _statusLabel(String? rawStatus, AppLocalizations l10n) {
    if (_isNotStarted(rawStatus)) return '';
    final status = (rawStatus ?? '').trim().toUpperCase();
    if (status == '1H') return l10n.liveStatusFirstHalf;
    if (status == 'HT') return l10n.liveStatusHalftime;
    if (status == '2H' || status == 'ET' || status == 'BT' || status == 'P') {
      return l10n.liveStatusSecondHalf;
    }
    if (status == 'FT' ||
        status == 'AET' ||
        status == 'PEN' ||
        status == 'WO' ||
        status == 'AWD' ||
        status == 'CANC') {
      return l10n.liveStatusFinal;
    }
    return status;
  }

  String _scoreLabel() {
    if (_isNotStarted(match.statusShort)) return '–';
    if (match.homeGoals == null || match.awayGoals == null) return '- – -';
    return '${match.homeGoals} – ${match.awayGoals}';
  }

  IconData _iconForEvent(String type) {
    switch (type) {
      case 'goal':
      case 'penalty_scored':
        return Icons.sports_soccer;
      case 'var_goal':
        return Icons.cancel_outlined;
      case 'penalty_missed':
      case 'penalty_event':
        return Icons.adjust_outlined;
      case 'substitution':
        return Icons.sync_alt;
      case 'yellow_card':
        return Icons.crop_portrait;
      case 'red_card':
        return Icons.stop;
      case 'woodwork':
        return Icons.highlight_off;
      default:
        return Icons.bolt;
    }
  }

  Color _colorForEvent(String type) {
    switch (type) {
      case 'goal':
      case 'penalty_scored':
        return CassandraColors.primary;
      case 'var_goal':
        return Colors.grey.shade600;
      case 'yellow_card':
        return Colors.amber.shade700;
      case 'red_card':
        return Colors.red.shade700;
      case 'penalty_missed':
        return Colors.red.shade400;
      case 'substitution':
        return Colors.green.shade700;
      case 'woodwork':
        return Colors.orange.shade700;
      default:
        return CassandraColors.slate;
    }
  }

  String _eventTypeLabel(String type, AppLocalizations l10n) {
    switch (type) {
      case 'goal':
        return l10n.liveEventGoal;
      case 'penalty_scored':
        return l10n.liveEventPenaltyScored;
      case 'penalty_missed':
        return l10n.liveEventPenaltyMissed;
      case 'var_goal':
        return l10n.liveEventVarGoal;
      case 'substitution':
        return l10n.liveEventSubstitution;
      case 'yellow_card':
        return l10n.liveEventYellowCard;
      case 'red_card':
        return l10n.liveEventRedCard;
      case 'woodwork':
        return l10n.liveEventWoodwork;
      case 'penalty_event':
        return l10n.liveEventPenalty;
      default:
        return l10n.liveEventGeneric;
    }
  }

  String _eventMainLabel(MatchLiveEvent e, AppLocalizations l10n) {
    final label = _eventTypeLabel(e.type, l10n);
    final player = (e.playerName ?? '').trim();
    final assist = (e.assistName ?? '').trim();
    if (e.type == 'substitution') {
      if (player.isNotEmpty && assist.isNotEmpty) {
        return '$label • $player → $assist';
      }
      if (player.isNotEmpty) return '$label • $player';
      return label;
    }
    if (player.isEmpty) return label;
    if (assist.isNotEmpty) return '$label • $player ($assist)';
    return '$label • $player';
  }

  String _eventMinuteLabel(MatchLiveEvent e) {
    final extra = e.extraMinute;
    if (extra == null || extra <= 0) {
      return "${e.minute}'";
    }
    return "${e.minute}+$extra'";
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const fg = CassandraColors.brightSnow;
    final status = _statusLabel(match.statusShort, l10n);
    // Ordine inverso: ultimi eventi in alto.
    final events = List<MatchLiveEvent>.of(match.liveEvents)
      ..sort((a, b) {
        if (a.minute != b.minute) return b.minute.compareTo(a.minute);
        final aExtra = a.extraMinute ?? 0;
        final bExtra = b.extraMinute ?? 0;
        return bExtra.compareTo(aExtra);
      });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: CassandraColors.brightSnow,
        toolbarHeight: 36,
        title: const SizedBox.shrink(),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  Text(
                    formatKickoff(match.kickoff),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (match.homeTeamLogo != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Image.network(
                                  match.homeTeamLogo!,
                                  width: 24,
                                  height: 24,
                                  errorBuilder: (_, e, s) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            Flexible(
                              child: Text(
                                match.homeTeam,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: fg,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          _scoreLabel(),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: fg,
                              ),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                match.awayTeam,
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: fg,
                                    ),
                              ),
                            ),
                            if (match.awayTeamLogo != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Image.network(
                                  match.awayTeamLogo!,
                                  width: 24,
                                  height: 24,
                                  errorBuilder: (_, e, s) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 20,
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: events.isEmpty
                  ? Center(
                      child: Text(
                        l10n.liveNoEvents,
                        style: const TextStyle(color: fg),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: events.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final e = events[index];
                        final detail = (e.detail ?? '').trim();
                        final team = (e.teamName ?? '').trim();
                        final secondary = [
                          if (team.isNotEmpty) team,
                          if (detail.isNotEmpty) detail,
                        ].join(' • ');

                        return Card(
                          color: CassandraColors.platinum,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    _eventMinuteLabel(e),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: CassandraColors.inkBlackV2,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _iconForEvent(e.type),
                                  size: 18,
                                  color: _colorForEvent(e.type),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _eventMainLabel(e, l10n),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: CassandraColors.inkBlackV2,
                                        ),
                                      ),
                                      if (secondary.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          secondary,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: CassandraColors.inkBlackV2
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
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
