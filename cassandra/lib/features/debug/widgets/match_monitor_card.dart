import 'dart:async';

import 'package:flutter/material.dart';

class MatchMonitorCard extends StatefulWidget {
  final Map<String, dynamic> match;
  final String? outcome;

  const MatchMonitorCard({
    super.key,
    required this.match,
    this.outcome,
  });

  @override
  State<MatchMonitorCard> createState() => _MatchMonitorCardState();
}

class _MatchMonitorCardState extends State<MatchMonitorCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatCountdown(Duration d) {
    if (d.isNegative) return 'Iniziata';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.match['home'] as String? ?? '?';
    final away = widget.match['away'] as String? ?? '?';
    final kickoffStr = widget.match['kickoff'] as String? ?? '';
    final statusShort = widget.match['statusShort'] as String? ?? 'NS';
    final homeGoals = widget.match['homeGoals'];
    final awayGoals = widget.match['awayGoals'];
    final elapsed = widget.match['elapsed'];
    final outcome = widget.outcome;

    final kickoff = DateTime.tryParse(kickoffStr);
    final now = DateTime.now().toUtc();

    final isFinished = statusShort == 'FT' || statusShort == 'AET' ||
        statusShort == 'PEN';
    final isLive = statusShort == '1H' || statusShort == '2H' ||
        statusShort == 'HT';
    final isPending = !isFinished && !isLive;

    Color statusColor;
    String statusLabel;
    if (isFinished) {
      statusColor = Colors.green.shade700;
      statusLabel = 'Terminata';
    } else if (isLive) {
      statusColor = Colors.orange.shade700;
      statusLabel = "${elapsed ?? '?'}'";
    } else if (kickoff != null && now.isAfter(kickoff)) {
      statusColor = Colors.orange.shade700;
      statusLabel = 'In avvio';
    } else {
      statusColor = Colors.grey.shade500;
      statusLabel = kickoff != null
          ? _formatCountdown(kickoff.toUtc().difference(now))
          : 'In attesa';
    }

    final scoreText = (homeGoals != null && awayGoals != null)
        ? '$homeGoals - $awayGoals'
        : '- : -';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Status badge
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            // Teams and score
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$home vs $away',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        scoreText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isFinished
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isFinished
                              ? Colors.black87
                              : Colors.grey.shade600,
                        ),
                      ),
                      if (outcome != null && outcome != 'pending') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            outcome == 'home'
                                ? '1'
                                : outcome == 'draw'
                                    ? 'X'
                                    : outcome == 'away'
                                        ? '2'
                                        : outcome.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Status label
            Text(
              statusLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
