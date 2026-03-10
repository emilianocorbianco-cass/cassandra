import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../badges/widgets/avatar_with_badges.dart';
import '../leaderboards/models/matchday_data.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/models/score_breakdown.dart';
import '../scoring/ranking_rules.dart';
import '../scoring/scoring_engine.dart';
import 'models/group_member.dart';

class GroupMatchdayMemberPage extends StatelessWidget {
  const GroupMatchdayMemberPage({
    super.key,
    required this.matchday,
    required this.member,
    this.picksByMatchId = const <String, PickOption>{},
    this.members = const [],
    this.allPicksByMemberId = const {},
  });

  final MatchdayData matchday;
  final GroupMember member;
  final Map<String, PickOption> picksByMatchId;

  /// All group members (for matchday leaderboard).
  final List<GroupMember> members;

  /// Picks for every member keyed by memberId (for matchday leaderboard).
  final Map<String, Map<String, PickOption>> allPicksByMemberId;

  Map<String, MatchOutcome> _effectiveOutcomes(dynamic appState) {
    final saved = appState.hasSavedOutcomesForMatchday(matchday.dayNumber)
        ? appState.outcomesForMatchday(matchday.dayNumber)
        : const <String, MatchOutcome>{};

    if (saved.isEmpty) return matchday.outcomesByMatchId;

    return <String, MatchOutcome>{...matchday.outcomesByMatchId, ...saved};
  }

  Map<String, PickOption> _picksForMember(dynamic appState) {
    if (picksByMatchId.isNotEmpty) return picksByMatchId;

    final uid = appState.profile.id;

    if (member.id == uid) {
      if (appState.hasSavedPicksForMatchday(matchday.dayNumber)) {
        return appState.currentUserPicksForMatchday(matchday.dayNumber);
      }

      final current =
          appState.currentUserPicksByMatchId as Map<String, PickOption>?;
      if (current != null && current.isNotEmpty) return current;
    }

    return const <String, PickOption>{};
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = CassandraScope.of(context);
    final en = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('en');

    appState.ensureCurrentUserPicksHistoryLoaded();
    appState.ensureOutcomesHistoryLoaded();
    appState.ensureCurrentUserPicksLoaded();

    final matches = List.of(matchday.matches)
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    final outcomes = _effectiveOutcomes(appState);
    final picks = _picksForMember(appState);

    final DayScoreBreakdown day = CassandraScoringEngine.computeDayScore(
      matches: matches,
      picksByMatchId: picks,
      outcomesByMatchId: outcomes,
    );

    // Check if matchday is finalized (all matches finished or voided).
    final isFinalized = matches.every((m) {
      final o = outcomes[m.id];
      if (o != null && o.isVoided) return true;
      final s = m.statusShort;
      return s == 'FT' || s == 'AET' || s == 'PEN';
    });

    final bonusSigned = day.bonusPoints >= 0
        ? '+${day.bonusPoints}'
        : '${day.bonusPoints}';

    // Build matchday leaderboard rows.
    final leaderboardRows = _buildLeaderboardRows(
      appState: appState,
      matches: matches,
      outcomes: outcomes,
    );

    return Scaffold(
      backgroundColor: CassandraColors.charcoal,
      appBar: AppBar(
        backgroundColor: CassandraColors.charcoal,
        foregroundColor: Colors.white,
        title: Text(
          '${member.teamName} • ${l10n.groupMatchdayTitle(matchday.dayNumber)}',
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Hero card ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: _HeroCard(
                  dayScore: day,
                  matches: matches,
                  outcomesByMatchId: outcomes,
                  picks: picks,
                  isFinalized: isFinalized,
                  bonusSigned: bonusSigned,
                  isEnglish: en,
                  matchdayNumber: matchday.dayNumber,
                ),
              ),
            ),

            // ── Match cards ────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final m = matches[i];
                    final pick = picks[m.id] ?? PickOption.none;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PostLockMatchCard(
                        match: m,
                        pick: pick,
                        outcome: outcomes[m.id],
                      ),
                    );
                  },
                  childCount: matches.length,
                ),
              ),
            ),

            // ── Matchday leaderboard ───────────────────────────────
            if (leaderboardRows.isNotEmpty)
              SliverToBoxAdapter(
                child: _MatchdayLeaderboardSection(
                  rows: leaderboardRows,
                  isEnglish: en,
                ),
              ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }

  List<_LeaderboardRow> _buildLeaderboardRows({
    required dynamic appState,
    required List<PredictionMatch> matches,
    required Map<String, MatchOutcome> outcomes,
  }) {
    if (members.isEmpty) return [];

    final uid = appState.profile.id as String;
    final rows = <_LeaderboardRow>[];

    for (final m in members) {
      Map<String, PickOption> memberPicks;
      if (m.id == member.id) {
        memberPicks = _picksForMember(appState);
      } else {
        final override = allPicksByMemberId[m.id];
        if (override != null && override.isNotEmpty) {
          memberPicks = override;
        } else if (m.id == uid) {
          if (appState.hasSavedPicksForMatchday(matchday.dayNumber)) {
            memberPicks = appState.currentUserPicksForMatchday(
              matchday.dayNumber,
            );
          } else {
            final current = appState.currentUserPicksByMatchId
                as Map<String, PickOption>?;
            memberPicks = current ?? const <String, PickOption>{};
          }
        } else {
          memberPicks = const <String, PickOption>{};
        }
      }

      final dayScore = CassandraScoringEngine.computeDayScore(
        matches: matches,
        picksByMatchId: memberPicks,
        outcomesByMatchId: outcomes,
      );

      rows.add(_LeaderboardRow(member: m, day: dayScore));
    }

    rows.sort((a, b) {
      return compareCassandraRanking(
        aTotal: a.day.total,
        bTotal: b.day.total,
        aAverageOddsPlayed: a.day.averageOddsPlayed,
        bAverageOddsPlayed: b.day.averageOddsPlayed,
        aTeamName: a.member.teamName,
        bTeamName: b.member.teamName,
      );
    });

    return rows;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Leaderboard Row Data
// ─────────────────────────────────────────────────────────────────────────────

class _LeaderboardRow {
  _LeaderboardRow({required this.member, required this.day});

  final GroupMember member;
  final DayScoreBreakdown day;
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Card
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.dayScore,
    required this.matches,
    required this.outcomesByMatchId,
    required this.picks,
    required this.isFinalized,
    required this.bonusSigned,
    required this.isEnglish,
    required this.matchdayNumber,
  });

  final DayScoreBreakdown dayScore;
  final List<PredictionMatch> matches;
  final Map<String, MatchOutcome> outcomesByMatchId;
  final Map<String, PickOption> picks;
  final bool isFinalized;
  final String bonusSigned;
  final bool isEnglish;
  final int matchdayNumber;

  static const _fg = CassandraColors.brightSnow;

  List<Color> _segmentColors() {
    const liveStatuses = {'1H', 'HT', '2H', 'ET', 'BT', 'LIVE'};
    return matches.map((m) {
      final outcome = outcomesByMatchId[m.id];
      final isPending = outcome == null || outcome.isPending;
      final isVoided = outcome?.isVoided ?? false;
      if (isVoided) return Colors.transparent;
      if (isPending) {
        final s = m.statusShort;
        if (s != null &&
            liveStatuses.contains(s) &&
            m.homeGoals != null &&
            m.awayGoals != null) {
          final liveOutcome = m.homeGoals! > m.awayGoals!
              ? MatchOutcome.home
              : m.homeGoals! < m.awayGoals!
                  ? MatchOutcome.away
                  : MatchOutcome.draw;
          final pick = picks[m.id] ?? PickOption.none;
          final correct = _isPickCorrect(pick, liveOutcome);
          return correct ? CassandraColors.mintLeaf : CassandraColors.primary;
        }
        return CassandraColors.charcoal;
      }
      final pick = picks[m.id] ?? PickOption.none;
      final correct = _isPickCorrect(pick, outcome);
      return correct ? CassandraColors.mintLeaf : CassandraColors.primary;
    }).toList();
  }

  List<bool> _segmentVoided() {
    return matches.map((m) {
      final outcome = outcomesByMatchId[m.id];
      return outcome?.isVoided ?? false;
    }).toList();
  }

  List<bool> _segmentLive() {
    return matches.map((m) {
      final s = m.statusShort;
      return s != null &&
          const {'1H', 'HT', '2H', 'ET', 'BT', 'LIVE'}.contains(s);
    }).toList();
  }

  static Color _valueColor(double value) {
    if (value > 0) return const Color(0xFF00B884);
    if (value < 0) return const Color(0xFFE01E48);
    return _fg;
  }

  @override
  Widget build(BuildContext context) {
    final correctCount = dayScore.correctCount;
    final matchCount = matches.length;
    final totalPoints = isFinalized ? formatOdds(dayScore.total) : '-';

    final segColors = _segmentColors();
    final segVoided = _segmentVoided();
    final segLive = _segmentLive();

    final matchdayTitle = isEnglish
        ? 'Matchday $matchdayNumber'
        : 'Giornata $matchdayNumber';

    const ringSize = 126.0;

    final basePoints = dayScore.baseTotal;
    final bonusVal = dayScore.bonusPoints.toDouble();
    final totalVal = dayScore.total;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: CassandraColors.inkBlackV2,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left: title + ring ──────────────────────────────────
          Expanded(
            flex: 50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  matchdayTitle,
                  style: const TextStyle(
                    color: _fg,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 21),
                SizedBox(
                  width: ringSize,
                  height: ringSize,
                  child: CustomPaint(
                    painter: _RingPainter(
                      segmentColors: segColors,
                      segmentVoided: segVoided,
                      segmentLive: segLive,
                    ),
                    child: Center(
                      child: Text(
                        '$correctCount/$matchCount',
                        style: const TextStyle(
                          color: _fg,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Right: breakdown ────────────────────────────────────
          Expanded(
            flex: 50,
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    isEnglish ? 'Points' : 'Punti',
                    style: const TextStyle(
                      color: _fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatOdds(basePoints),
                    style: TextStyle(
                      color: _valueColor(basePoints),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isEnglish ? 'Bonus points' : 'Punti bonus',
                    style: const TextStyle(
                      color: _fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isFinalized ? bonusSigned : '-',
                    style: TextStyle(
                      color: isFinalized ? _valueColor(bonusVal) : _fg,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isEnglish ? 'Total points' : 'Punti totali',
                    style: const TextStyle(
                      color: _fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    totalPoints,
                    style: TextStyle(
                      color: isFinalized ? _valueColor(totalVal) : _fg,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ring Painter (segmented donut)
// ─────────────────────────────────────────────────────────────────────────────

bool _isPickCorrect(PickOption pick, MatchOutcome outcome) {
  switch (pick) {
    case PickOption.home:
      return outcome == MatchOutcome.home;
    case PickOption.draw:
      return outcome == MatchOutcome.draw;
    case PickOption.away:
      return outcome == MatchOutcome.away;
    case PickOption.homeDraw:
      return outcome == MatchOutcome.home || outcome == MatchOutcome.draw;
    case PickOption.drawAway:
      return outcome == MatchOutcome.draw || outcome == MatchOutcome.away;
    case PickOption.homeAway:
      return outcome == MatchOutcome.home || outcome == MatchOutcome.away;
    case PickOption.none:
      return false;
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.segmentColors,
    required this.segmentVoided,
    required this.segmentLive,
  });

  final List<Color> segmentColors;
  final List<bool> segmentVoided;
  final List<bool> segmentLive;

  static const double _gapDeg = 2.5;
  static const double _gapRad = _gapDeg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const thickness = 19.0;
    final outerR = size.width / 2 * 1.10;
    final innerR = outerR - thickness;

    final count = segmentColors.length;
    if (count == 0) return;

    final segSweep = (2 * math.pi - count * _gapRad) / count;
    final startOffset = -math.pi / 2 + _gapRad / 2;

    for (var i = 0; i < count; i++) {
      final startA = startOffset + i * (segSweep + _gapRad);
      _drawSegment(canvas, center, innerR, outerR, startA, segSweep, i);
    }
  }

  void _drawSegment(
    Canvas canvas,
    Offset center,
    double innerR,
    double outerR,
    double startAngle,
    double sweepAngle,
    int index,
  ) {
    final path = _annularSector(center, innerR, outerR, startAngle, sweepAngle);
    final isVoided = index < segmentVoided.length && segmentVoided[index];

    if (isVoided) {
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = CassandraColors.cardBg.withValues(alpha: 0.30);
      canvas.drawPath(path, borderPaint);
      return;
    }

    final baseColor = index < segmentColors.length
        ? segmentColors[index]
        : CassandraColors.charcoal;
    final isLive = index < segmentLive.length && segmentLive[index];
    final isColored = baseColor != CassandraColors.charcoal &&
        baseColor != Colors.transparent;

    if (isLive && isColored) {
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = CassandraColors.brightSnow;
      canvas.drawPath(path, fillPaint);

      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = baseColor;
      canvas.drawPath(path, borderPaint);
      return;
    }

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = baseColor;
    canvas.drawPath(path, paint);
  }

  Path _annularSector(
    Offset center,
    double innerR,
    double outerR,
    double startAngle,
    double sweepAngle,
  ) {
    return Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: outerR),
        startAngle,
        sweepAngle,
      )
      ..arcTo(
        Rect.fromCircle(center: center, radius: innerR),
        startAngle + sweepAngle,
        -sweepAngle,
        false,
      )
      ..close();
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.segmentColors != segmentColors ||
        oldDelegate.segmentVoided != segmentVoided ||
        oldDelegate.segmentLive != segmentLive;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Post-Lock Match Card
// ─────────────────────────────────────────────────────────────────────────────

class _PostLockMatchCard extends StatelessWidget {
  const _PostLockMatchCard({
    required this.match,
    required this.pick,
    this.outcome,
  });

  final PredictionMatch match;
  final PickOption pick;
  final MatchOutcome? outcome;

  bool get _isLive {
    final s = match.statusShort;
    return s != null &&
        const {'1H', 'HT', '2H', 'ET', 'BT', 'LIVE'}.contains(s);
  }

  bool get _isFT {
    final s = match.statusShort;
    return s == 'FT' || s == 'AET' || s == 'PEN';
  }

  bool get _isStarted => _isLive || _isFT;

  double get _winOdds {
    if (pick.isNone) return 0;
    switch (pick) {
      case PickOption.home:
        return match.odds.home;
      case PickOption.draw:
        return match.odds.draw;
      case PickOption.away:
        return match.odds.away;
      case PickOption.homeDraw:
        return match.odds.homeDraw;
      case PickOption.drawAway:
        return match.odds.drawAway;
      case PickOption.homeAway:
        return match.odds.homeAway;
      case PickOption.none:
        return 0;
    }
  }

  double get _loseOdds {
    if (pick.isNone) return 0;
    if (pick.isSingle) {
      switch (pick) {
        case PickOption.home:
          return match.odds.drawAway;
        case PickOption.draw:
          return match.odds.homeAway;
        case PickOption.away:
          return match.odds.homeDraw;
        default:
          return 0;
      }
    }
    switch (pick) {
      case PickOption.homeDraw:
        return match.odds.away;
      case PickOption.drawAway:
        return match.odds.home;
      case PickOption.homeAway:
        return match.odds.draw;
      default:
        return 0;
    }
  }

  String _opposingPickLabel() {
    switch (pick) {
      case PickOption.home:
        return 'X2';
      case PickOption.draw:
        return '12';
      case PickOption.away:
        return '1X';
      case PickOption.homeDraw:
        return '2';
      case PickOption.drawAway:
        return '1';
      case PickOption.homeAway:
        return 'X';
      case PickOption.none:
        return '-';
    }
  }

  bool get _isCurrentlyCorrect {
    final h = match.homeGoals ?? 0;
    final a = match.awayGoals ?? 0;
    switch (pick) {
      case PickOption.home:
        return h > a;
      case PickOption.draw:
        return h == a;
      case PickOption.away:
        return a > h;
      case PickOption.homeDraw:
        return h >= a;
      case PickOption.drawAway:
        return a >= h;
      case PickOption.homeAway:
        return h != a;
      case PickOption.none:
        return false;
    }
  }

  static const _mintLeaf = Color(0xFF00B884);
  static const _amaranth = Color(0xFFE01E48);

  Color? get _playedBubbleBg {
    if (pick.isNone || !_isFT) return null;
    return _isCurrentlyCorrect ? _mintLeaf : null;
  }

  Color? get _opposingBubbleBg {
    if (pick.isNone || !_isFT) return null;
    return _isCurrentlyCorrect ? null : _amaranth;
  }

  Color? get _playedBubbleBorder {
    if (pick.isNone || !_isLive) return null;
    return _isCurrentlyCorrect ? _mintLeaf : null;
  }

  Color? get _opposingBubbleBorder {
    if (pick.isNone || !_isLive) return null;
    return _isCurrentlyCorrect ? null : _amaranth;
  }

  @override
  Widget build(BuildContext context) {
    final homeInitial = match.homeTeam.isNotEmpty ? match.homeTeam[0] : '?';
    final awayInitial = match.awayTeam.isNotEmpty ? match.awayTeam[0] : '?';
    final hasPick = !pick.isNone;

    return Container(
      decoration: BoxDecoration(
        color: CassandraColors.inkBlackV2,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: CassandraColors.platinum,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // ── Left: date/time or live status ────────────────
            _MatchStatusColumn(match: match),
            const SizedBox(width: 4),

            // ── Center: team rows ─────────────────────────────
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _TeamLogo(
                        url: match.homeTeamLogo,
                        initial: homeInitial,
                        teamName: match.homeTeam,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          match.homeTeam,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: CassandraColors.inkBlackV2,
                          ),
                        ),
                      ),
                      if (_isStarted)
                        Padding(
                          padding: const EdgeInsets.only(right: 13),
                          child: Text(
                            '${match.homeGoals ?? 0}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: CassandraColors.inkBlackV2,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _TeamLogo(
                        url: match.awayTeamLogo,
                        initial: awayInitial,
                        teamName: match.awayTeam,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          match.awayTeam,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: CassandraColors.inkBlackV2,
                          ),
                        ),
                      ),
                      if (_isStarted)
                        Padding(
                          padding: const EdgeInsets.only(right: 13),
                          child: Text(
                            '${match.awayGoals ?? 0}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: CassandraColors.inkBlackV2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Right: pick bubbles ───────────────────────────
            const SizedBox(width: 8),
            if (hasPick) ...[
              _PostLockPickBubble(
                label: pick.label,
                odds: _winOdds,
                bgColor: _playedBubbleBg,
                borderColor: _playedBubbleBorder,
              ),
              const SizedBox(width: 4),
              _PostLockPickBubble(
                label: _opposingPickLabel(),
                odds: -_loseOdds,
                bgColor: _opposingBubbleBg,
                borderColor: _opposingBubbleBorder,
              ),
            ] else
              const SizedBox(width: 114),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Match Status Column
// ─────────────────────────────────────────────────────────────────────────────

class _MatchStatusColumn extends StatelessWidget {
  const _MatchStatusColumn({required this.match});

  final PredictionMatch match;

  @override
  Widget build(BuildContext context) {
    final s = match.statusShort;
    final isEn = Localizations.localeOf(context).languageCode == 'en';

    if (s == 'HT') {
      return SizedBox(
        width: 50,
        child: Center(
          child: Text(
            isEn ? 'HT' : 'INT',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: CassandraColors.inkBlackV2,
            ),
          ),
        ),
      );
    }
    if (s == 'FT' || s == 'AET' || s == 'PEN') {
      return SizedBox(
        width: 50,
        child: Center(
          child: Text(
            isEn ? 'FT' : 'FINE',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: CassandraColors.inkBlackV2,
            ),
          ),
        ),
      );
    }

    if (s == '1H' || s == '2H' || s == 'ET' || s == 'BT' || s == 'LIVE') {
      final apiElapsed = match.elapsed;
      final int minute;
      final String halfLabel;
      if (s == '1H' || s == 'LIVE') {
        minute = apiElapsed?.clamp(1, 45) ??
            (DateTime.now().difference(match.kickoff).inMinutes + 1)
                .clamp(1, 45);
        halfLabel = isEn ? '1H' : '1T';
      } else if (s == '2H') {
        minute = apiElapsed?.clamp(46, 90) ??
            (DateTime.now().difference(match.kickoff).inMinutes - 21)
                .clamp(46, 90);
        halfLabel = isEn ? '2H' : '2T';
      } else {
        minute = apiElapsed?.clamp(91, 120) ??
            (DateTime.now().difference(match.kickoff).inMinutes - 36)
                .clamp(91, 120);
        halfLabel = isEn ? 'ET' : 'TS';
      }
      return SizedBox(
        width: 50,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "$minute'",
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: CassandraColors.inkBlackV2,
              ),
            ),
            Text(
              halfLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: CassandraColors.inkBlackV2,
              ),
            ),
          ],
        ),
      );
    }

    final kickoff = match.kickoff.toLocal();
    final dateStr =
        '${kickoff.day.toString().padLeft(2, '0')}/${kickoff.month.toString().padLeft(2, '0')}';
    final timeStr =
        '${kickoff.hour.toString().padLeft(2, '0')}:${kickoff.minute.toString().padLeft(2, '0')}';
    return SizedBox(
      width: 50,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dateStr,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: CassandraColors.inkBlackV2,
            ),
          ),
          Text(
            timeStr,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: CassandraColors.inkBlackV2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Team Logo
// ─────────────────────────────────────────────────────────────────────────────

class _TeamLogo extends StatelessWidget {
  const _TeamLogo({required this.url, required this.initial, this.teamName});

  final String? url;
  final String initial;
  final String? teamName;

  static const Map<String, String> _bundledOverrides = {
    'juventus': 'assets/logos/juventus_mark.svg',
  };

  String? _bundledAssetFor(String? name) {
    if (name == null) return null;
    final key = name.trim().toLowerCase();
    for (final entry in _bundledOverrides.entries) {
      if (key.contains(entry.key)) return entry.value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const size = 30.0;

    final bundled = _bundledAssetFor(teamName);
    if (bundled != null) {
      final widget = bundled.endsWith('.svg')
          ? SvgPicture.asset(
              bundled,
              width: size,
              height: size,
              fit: BoxFit.contain,
            )
          : Image.asset(
              bundled,
              width: size,
              height: size,
              fit: BoxFit.contain,
            );
      return SizedBox(width: size, height: size, child: widget);
    }

    if (url != null && url!.isNotEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipOval(
          child: Image.network(
            url!,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _fallback(size),
          ),
        ),
      );
    }
    return _fallback(size);
  }

  Widget _fallback(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: CassandraColors.cardBg,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: CassandraColors.slate,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Post-Lock Pick Bubble
// ─────────────────────────────────────────────────────────────────────────────

class _PostLockPickBubble extends StatelessWidget {
  const _PostLockPickBubble({
    required this.label,
    required this.odds,
    this.bgColor,
    this.borderColor,
  });

  final String label;
  final double odds;
  final Color? bgColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final hasFill = bgColor != null;
    final bg = bgColor ?? CassandraColors.brightSnow;
    final border = borderColor ?? CassandraColors.inkBlackV2;
    final fg = hasFill
        ? CassandraColors.brightSnow
        : CassandraColors.inkBlackV2;
    return Container(
      width: 55,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: border,
          width: borderColor != null ? 2.0 : 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            formatOdds(odds),
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Matchday Leaderboard Section
// ─────────────────────────────────────────────────────────────────────────────

class _MatchdayLeaderboardSection extends StatelessWidget {
  const _MatchdayLeaderboardSection({
    required this.rows,
    required this.isEnglish,
  });

  final List<_LeaderboardRow> rows;
  final bool isEnglish;

  Color _avatarColorFromSeed(int seed) {
    final hue = (seed % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.45, 0.65).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final totalMatches = rows.isNotEmpty
        ? rows.first.day.matchBreakdowns.length
        : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8, left: 4),
            child: Text(
              isEnglish ? 'Matchday ranking' : 'Classifica giornata',
              style: const TextStyle(
                color: CassandraColors.brightSnow,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (var i = 0; i < rows.length; i++)
            _leaderboardTile(rows[i], i, l10n, totalMatches),
        ],
      ),
    );
  }

  Widget _leaderboardTile(
    _LeaderboardRow row,
    int index,
    AppLocalizations l10n,
    int totalMatches,
  ) {
    final pts = formatOdds(row.day.total);

    return Card(
      child: ListTile(
        leading: SizedBox(
          width: 64,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: CassandraColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AvatarWithBadges(
                radius: 18,
                backgroundColor: _avatarColorFromSeed(row.member.avatarSeed),
                text: row.member.avatarInitial,
                badges: const [],
                imagePathOrUrl: row.member.photoUrl,
              ),
            ],
          ),
        ),
        title: Text(row.member.uiName),
        subtitle: Text(
          '${l10n.statsCorrect}: ${row.day.correctCount}/$totalMatches • bonus: ${row.day.bonusPoints}',
        ),
        trailing: Text(
          pts,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: row.day.total >= 0
                ? CassandraColors.inkBlack
                : CassandraColors.primary,
          ),
        ),
      ),
    );
  }
}
