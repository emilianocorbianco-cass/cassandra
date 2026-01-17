import 'package:flutter/material.dart';
import '../../app/theme/cassandra_colors.dart';
import 'models/mock_prediction_data.dart';
import 'models/pick_option.dart';
import 'models/prediction_match.dart';
import 'models/formatters.dart';
import 'widgets/prediction_match_card.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/scoring_engine.dart';
import 'package:cassandra/app/config/env.dart';
import 'package:cassandra/services/api_football/api_football_client.dart';
import 'package:cassandra/services/api_football/api_football_service.dart';
import 'package:cassandra/features/predictions/adapters/api_football_fixture_adapter.dart';
import '../../app/state/cassandra_scope.dart';
import '../../domain/matchday/matchday_recovery_rules.dart'
    show computeMatchdayProgress;
import '../scoring/adapters/api_football_outcome_adapter.dart';
import '../leaderboards/mock_season_data.dart';
import '../leaderboards/models/matchday_data.dart';
import 'predictions_matchday_page.dart';
import 'predictions_history_page.dart';
import '../scoring/models/score_breakdown.dart';

enum VisibilityChoice { private, public }

class PredictionsPage extends StatefulWidget {
  const PredictionsPage({super.key});
  @override
  State<PredictionsPage> createState() => _PredictionsPageState();
}

class _PredictionsPageState extends State<PredictionsPage> {
  int get _matchdayNumber => CassandraScope.of(context).cassandraMatchdayCursor;
  int? _shownMatchdayNumber;
  int get _effectiveMatchdayNumber => _shownMatchdayNumber ?? _matchdayNumber;
  late List<PredictionMatch> _matches;
  bool _usingRealFixtures = false;
  bool _loadingFixtures = false;
  bool _didLoadFixtures = false;
  DateTime? _fixturesUpdatedAt;
  final Map<String, PickOption> _picks = {};
  int _segment = 0; // 0 = futuri, 1 = passati
  VisibilityChoice? _submittedVisibility;
  DateTime? _submittedAt;
  @override
  void initState() {
    super.initState();
    _matches = mockPredictionMatches();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadFixtures) return;
    _didLoadFixtures = true;
    _tryLoadRealFixtures();
  }

  PickOption _pickFor(String matchId) {
    final appState = CassandraScope.of(context);
    appState.ensureCurrentUserPicksLoaded();
    return appState.currentUserPicksByMatchId[matchId] ?? PickOption.none;
  }

  int get _pickedCount => _matches.where((m) => !_pickFor(m.id).isNone).length;
  int get _missingCount => _matches.length - _pickedCount;
  DateTime get _firstKickoff =>
      _matches.map((m) => m.kickoff).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime get _lockTime => _firstKickoff.subtract(const Duration(minutes: 30));
  bool get _locked => DateTime.now().isAfter(_lockTime);
  String get _matchdayLabel {
    final daysLabel = formatMatchdayDaysItalian(_matches.map((m) => m.kickoff));
    final appState = CassandraScope.of(context);
    final progress = appState.matchdayProgressFor(_effectiveMatchdayNumber);
    final status = progress == null
        ? ''
        : ' • ${String.fromCharCode(0x1F512)} ${progress.isLocked ? "LOCK" : "OPEN"}'
              ' • P:${progress.primaryDone ? "OK" : "..."}'
              ' • F:${progress.finalDone ? "OK" : "..."}'
              ' • ${progress.playedFixtures}/${progress.totalFixtures}'
              '${progress.voidFixtures > 0 ? " • nulle ${progress.voidFixtures}" : ""}'
              ' • ${progress.isValidMatchday ? "valida" : "non valida"}';
    return 'giornata $_effectiveMatchdayNumber - $daysLabel$status';
  }

  double? _oddsForPick(PredictionMatch match, PickOption pick) {
    switch (pick) {
      case PickOption.none:
        return null;
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
    }
  }

  double? get _averageOddsPlayed {
    final values = <double>[];
    for (final match in _matches) {
      final pick = _pickFor(match.id);
      final odds = _oddsForPick(match, pick);
      if (odds != null) values.add(odds);
    }
    if (values.isEmpty) return null;
    final sum = values.reduce((a, b) => a + b);
    return sum / values.length;
  }

  void _setPick(String matchId, PickOption pick) {
    // Lock: non permettere modifiche ai pick se la partita è già iniziata.
    final PredictionMatch? match = _matches.cast<PredictionMatch?>().firstWhere(
      (m) => m?.id == matchId,
      orElse: () => null,
    );
    if (match != null && DateTime.now().isAfter(match.kickoff)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Partita già iniziata: pick bloccato')),
      );
      return;
    }
    setState(() => _picks[matchId] = pick);
    CassandraScope.of(context).setCurrentUserPick(matchId, pick);
  }

  void _clearPick(String matchId) {
    setState(() => _picks.remove(matchId));
    CassandraScope.of(context).setCurrentUserPick(matchId, PickOption.none);
  }

  Future<bool> _confirmSubmitIfMissing(int missing) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text(
            'Hai lasciato $missing partite senza pronostico.\n\n'
            'Regola Cassandra: per ogni partita non giocata verrà applicata '
            'una penalità pari a -quota più alta (tra 1/X/2) in fase di calcolo.\n\n'
            'Vuoi inviare comunque?',
          ),
          actions: [
            IconButton(
              tooltip: 'Storico',
              icon: const Icon(Icons.history),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PredictionsHistoryPage(),
                  ),
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Invia comunque'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _submit(VisibilityChoice visibility) async {
    if (_locked) return;
    final missing = _missingCount;
    if (missing > 0) {
      final ok = await _confirmSubmitIfMissing(missing);
      if (!ok) return;
      if (!mounted) return; // dopo await
    }
    if (!mounted) return;
    setState(() {
      _submittedVisibility = visibility;
      _submittedAt = DateTime.now();
    });
    final label = visibility == VisibilityChoice.public
        ? 'pubblica'
        : 'privata';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Schedina inviata (visibilità: $label)')),
    );
    // Snapshot storico: salva i pick per questa giornata (così "passati" diventa vero)
    final appState = CassandraScope.of(context);
    appState.ensureCurrentUserPicksHistoryLoaded();
    appState.ensureMatchdayMatchesLoaded();
    appState.ensureOutcomesHistoryLoaded();
    appState.saveCurrentUserPicksHistory(
      dayNumber: _effectiveMatchdayNumber,
      picksByMatchId: _picks,
    );
    await appState.saveMatchdayMatchesSnapshot(
      matchdayNumber: _effectiveMatchdayNumber,
      matches: _matches,
    );
    appState.ensureMatchesHistoryLoaded();
    appState.saveMatchesHistory(
      matchdayNumber: _effectiveMatchdayNumber,
      matches: _matches,
    );
    // Se abbiamo outcomes disponibili, salvali anche nello storico (per punteggi stabili)
    final outcomesNow = <String, MatchOutcome>{
      for (final e in appState.effectivePredictionOutcomesByMatchId.entries)
        e.key: e.value,
    };
    if (outcomesNow.isNotEmpty) {
      appState.ensureOutcomesHistoryLoaded();
      appState.saveOutcomesHistory(
        dayNumber: _effectiveMatchdayNumber,
        outcomesByMatchId: outcomesNow,
      );
    }
  }

  Future<void> _showDebugScorePreview() async {
    final rnd = Random();
    const outcomesList = [
      MatchOutcome.home,
      MatchOutcome.draw,
      MatchOutcome.away,
    ];
    final outcomes = <String, MatchOutcome>{};
    for (final m in _matches) {
      outcomes[m.id] = outcomesList[rnd.nextInt(outcomesList.length)];
    }
    final day = CassandraScoringEngine.computeDayScore(
      matches: _matches,
      picksByMatchId: _picks,
      outcomesByMatchId: outcomes,
    );
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final byId = {for (final b in day.matchBreakdowns) b.matchId: b};
        final height = MediaQuery.of(context).size.height * 0.75;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Debug: calcolo punteggio',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text('base: ${formatOdds(day.baseTotal)}'),
                  Text('bonus: ${day.bonusPoints}'),
                  Text('totale: ${formatOdds(day.total)}'),
                  const SizedBox(height: 6),
                  Text('esatti: ${day.correctCount}/10'),
                  Text(
                    'quota media: ${day.averageOddsPlayed == null ? '-' : formatOdds(day.averageOddsPlayed!)}',
                  ),
                  const Divider(height: 20),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _matches.length,
                      itemBuilder: (context, i) {
                        final m = _matches[i];
                        final b = byId[m.id]!;
                        final outcome = outcomes[m.id]!;
                        final pick = _pickFor(m.id);
                        final sign = b.basePoints >= 0 ? '+' : '';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${m.homeTeam} - ${m.awayTeam}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'pick ${pick.label}  •  res ${outcome.label}  •  $sign${formatOdds(b.basePoints)}',
                              ),
                              if (b.note.isNotEmpty)
                                Text(
                                  b.note,
                                  style: const TextStyle(fontSize: 12),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _tryLoadRealFixtures({bool showLoader = false}) async {
    final key = Env.apiFootballKey;
    if (key == null) {
      if (kDebugMode) {
        debugPrint('[fixtures] API_FOOTBALL_KEY is null -> using mock');
      }
      return; // in test o senza key restiamo sui mock
    }
    if (kDebugMode) {
      final tail = key.length >= 4 ? key.substring(key.length - 4) : key;
      debugPrint('[fixtures] key present (…$tail). loading…');
    }
    if (showLoader && mounted) {
      setState(() => _loadingFixtures = true);
    }
    final client = ApiFootballClient(
      apiKey: key,
      baseUrl: Env.baseUrl,
      useRapidApi: Env.useRapidApi,
      rapidApiHost: Env.rapidApiHost,
    );
    try {
      final service = ApiFootballService(client);
      final scope = CassandraScope.of(context);
      final appState = CassandraScope.of(context);
      var dayNumber = appState.cassandraMatchdayCursor;
      // Intorno di partite (passate recenti + future) per scegliere la giornata corretta
      final past = await service.getLastSerieAFixtures(count: 40);
      final next = await service.getNextSerieAFixtures(count: 80);
      final fixtures = [...past, ...next];
      if (kDebugMode) {
        debugPrint('[fixtures] got ${fixtures.length} fixtures (past+next)');
      }
      // Dedup per ID (se l'API restituisce doppioni)
      final seen = <Object?>{};
      final uniqueFixtures = fixtures
          .where((f) => seen.add(f.fixtureId))
          .toList();
      final outcomes = outcomesByMatchIdFromFixtures(uniqueFixtures);
      int? matchdayFromRound(String? round) {
        if (round == null) return null;
        final m = RegExp(r'(\d{1,2})\s*$').firstMatch(round.trim());
        if (m == null) return null;
        return int.tryParse(m.group(1)!);
      }

      // ignore: unused_element
      int? mostRepresentedMatchday(Iterable fixtures) {
        final counts = <int, int>{};
        for (final f in fixtures) {
          final md = matchdayFromRound((f as dynamic).round?.toString());
          if (md == null) continue;
          counts[md] = (counts[md] ?? 0) + 1;
        }
        if (counts.isEmpty) return null;
        var bestMd = counts.keys.first;
        var bestCount = counts[bestMd]!;
        for (final e in counts.entries) {
          if (e.value > bestCount) {
            bestMd = e.key;
            bestCount = e.value;
          }
        }
        return bestMd;
      }

      Duration distanceToInterval(DateTime now, DateTime start, DateTime end) {
        if (now.isBefore(start)) return start.difference(now);
        if (now.isAfter(end)) return now.difference(end);
        return Duration.zero; // siamo dentro l'intervallo della giornata
      }

      int? bestMatchdayByTime(Iterable fixtures) {
        final now = DateTime.now();
        // Cache runtime per lo storico: matchdays reali presenti nella finestra fixtures (past+next).
        final allMds = <int>{};
        for (final f in uniqueFixtures) {
          final md = matchdayFromRound((f as dynamic).round?.toString());
          if (md != null) allMds.add(md);
        }
        final recentMatchesByMd = <int, List<PredictionMatch>>{};
        final recentOutcomesByMd = <int, Map<String, MatchOutcome>>{};
        for (final md in allMds) {
          final ms = predictionMatchesFromFixtures(
            uniqueFixtures,
            matchdayNumber: md,
            useMockIds: false,
          );
          if (ms.isEmpty) continue;
          recentMatchesByMd[md] = ms;
          recentOutcomesByMd[md] = {
            for (final m in ms)
              if (outcomes[m.id] != null) m.id: outcomes[m.id]!,
          };
        }
        final candidates = <int>{};
        for (final f in fixtures) {
          final md = matchdayFromRound((f as dynamic).round?.toString());
          if (md != null) candidates.add(md);
        }
        if (candidates.isEmpty) return null;
        int? bestMd;
        Duration? bestDist;
        for (final md in candidates) {
          final ms = predictionMatchesFromFixtures(
            uniqueFixtures,
            matchdayNumber: md,
            useMockIds: false,
          );
          if (ms.isEmpty) continue;
          final first = ms
              .map((m) => m.kickoff)
              .reduce((a, b) => a.isBefore(b) ? a : b);
          final last = ms
              .map((m) => m.kickoff)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          final dist = distanceToInterval(now, first, last);
          if (bestDist == null || dist < bestDist) {
            bestDist = dist;
            bestMd = md;
          }
        }
        return bestMd;
      }

      final inferredByTime = bestMatchdayByTime(uniqueFixtures);
      if (inferredByTime != null && inferredByTime > dayNumber) {
        if (kDebugMode) {
          debugPrint(
            '[fixtures] sync cursor=$dayNumber -> $inferredByTime (closest by time)',
          );
        }
        await appState.setCassandraMatchdayCursor(inferredByTime);
        dayNumber = inferredByTime;
      }
      var matches = predictionMatchesFromFixtures(
        uniqueFixtures,
        matchdayNumber: dayNumber,
        useMockIds: false,
      );
      if (kDebugMode && matches.isNotEmpty) {
        final first = matches
            .map((m) => m.kickoff)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        final last = matches
            .map((m) => m.kickoff)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        debugPrint(
          '[fixtures] day=$dayNumber matches=${matches.length} range=${first.toIso8601String()}..${last.toIso8601String()} now=${DateTime.now().toIso8601String()}',
        );
      }
      if (matches.isEmpty) return;
      // === MatchdayProgress (48h void / primaryDone / finalDone / >=6) ===
      final now = DateTime.now();
      // Registra origin kickoff (prima volta che vediamo questa fixtureId)
      appState.ensureOriginKickoffsLoaded();
      for (final m in matches) {
        appState.registerOriginKickoff(matchId: m.id, kickoff: m.kickoff);
      }
      String statusFor(PredictionMatch m) =>
          (outcomes[m.id] ?? MatchOutcome.pending).isGraded ? 'FT' : 'NS';
      final progress = computeMatchdayProgress<PredictionMatch>(
        matches,
        now: now,
        kickoff: (m) => m.kickoff,
        originKickoff: (m) => appState.originKickoffFor(
          matchId: m.id,
          fallbackKickoff: m.kickoff,
        ),
        statusShort: (m) => statusFor(m),
      );
      var matchesToShow = matches;
      // Progress da mostrare (coerente con matchesToShow e dayNumber attuale)
      final progressToShow = computeMatchdayProgress<PredictionMatch>(
        matchesToShow,
        now: now,
        kickoff: (m) => m.kickoff,
        originKickoff: (m) => appState.originKickoffFor(
          matchId: m.id,
          fallbackKickoff: m.kickoff,
        ),
        statusShort: (m) => statusFor(m),
      );
      appState.setMatchdayProgress(
        matchdayNumber: dayNumber,
        progress: progressToShow,
      );
      var advanced = false;
      final fromMatchday = dayNumber;
      // Dopo primaryDone la matchday successiva è giocabile (decisione Cassandra)
      // // AUTO-BUMP: primaryDone
      // if (progress.primaryDone && progress.isValidMatchday && dayNumber == appState.cassandraMatchdayCursor) {
      //   await appState.setCassandraMatchdayCursor(dayNumber + 1);
      // }

      // Finalizzazione: quando finalDone e matchday valida (>=6),
      // salviamo snapshot + storico per leaderboard stabile anche con recuperi.
      if (progress.finalDone && progress.isValidMatchday) {
        final voidedIds = <String>{};
        for (final m in matches) {
          final out = outcomes[m.id] ?? MatchOutcome.pending;
          if (out.isGraded) continue;
          final origin = appState.originKickoffFor(
            matchId: m.id,
            fallbackKickoff: m.kickoff,
          );
          if (now.isAfter(origin.add(const Duration(hours: 48)))) {
            voidedIds.add(m.id);
          }
        }
        final effectiveMatches = matches
            .where((m) => !voidedIds.contains(m.id))
            .toList(growable: false);
        final effectiveOutcomes = <String, MatchOutcome>{
          for (final e in outcomes.entries)
            if (!voidedIds.contains(e.key)) e.key: e.value,
        };
        await appState.maybeFinalizeMatchday(
          matchdayNumber: fromMatchday,
          matches: effectiveMatches,
          outcomesByMatchId: effectiveOutcomes,
        );
      }
      if (progress.primaryDone) {
        final nextMatches = predictionMatchesFromFixtures(
          uniqueFixtures,
          matchdayNumber: dayNumber + 1,
          useMockIds: false,
        );
        if (nextMatches.isNotEmpty) {
          for (final m in nextMatches) {
            appState.registerOriginKickoff(matchId: m.id, kickoff: m.kickoff);
          }
          await appState.persistOriginKickoffs();
          dayNumber = fromMatchday + 1;
          matchesToShow = nextMatches;
          advanced = true;
        }
      } else {
        await appState.persistOriginKickoffs();
      }
      if (kDebugMode) {
        debugPrint(
          '[fixtures] progress day=$fromMatchday '
          'primaryDone=${progress.primaryDone} finalDone=${progress.finalDone} '
          'played=${progress.playedFixtures} void=${progress.voidFixtures}',
        );
      }
      // TODO: cablare MatchdayProgress (primaryDone/finalDone) prima di bumpare il cursor automaticamente.
      if (!mounted) return;
      setState(() {
        _shownMatchdayNumber = dayNumber;
        _matches = matchesToShow;
        _usingRealFixtures = true;
        _fixturesUpdatedAt = DateTime.now();
        if (advanced) {
          _picks.clear();
          _submittedAt = null;
          _submittedVisibility = null;
        }
      });
      // Salviamo le fixture reali in cache runtime (per Gruppo / User pages)
      // Aggiorna cache runtime per lo storico (passati)
      // Costruisce cache runtime per storico (passati) nello STESSO scope della call.
      final allMds = <int>{};
      for (final f in uniqueFixtures) {
        final md = matchdayFromRound((f as dynamic).round?.toString());
        if (md != null) allMds.add(md);
      }
      final recentMatchesByMd = <int, List<PredictionMatch>>{};
      final recentOutcomesByMd = <int, Map<String, MatchOutcome>>{};
      for (final md in allMds) {
        final ms = predictionMatchesFromFixtures(
          uniqueFixtures,
          matchdayNumber: md,
          useMockIds: false,
        );
        if (ms.isEmpty) continue;
        recentMatchesByMd[md] = ms;
        recentOutcomesByMd[md] = {
          for (final m in ms)
            if (outcomes[m.id] != null) m.id: outcomes[m.id]!,
        };
      }
      appState.setRecentMatchdayDataBulk(
        matchesByMatchday: recentMatchesByMd,
        outcomesByMatchday: recentOutcomesByMd,
      );
      scope.setCachedPredictionMatches(
        matchesToShow,
        isReal: true,
        updatedAt: _fixturesUpdatedAt,
      );
      scope.setCachedPredictionOutcomesByMatchId(outcomes);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[fixtures] load failed: $e');
        debugPrint('$st');
      }
    } finally {
      client.close();
      if (showLoader && mounted) {
        setState(() => _loadingFixtures = false);
      }
    }
  }

  Map<String, PickOption> _demoPicksForMatchday(
    String seed,
    List<PredictionMatch> matches,
  ) {
    final rnd = Random(seed.hashCode);
    PickOption randomPick() {
      final x = rnd.nextDouble();
      if (x < 0.10) return PickOption.none;
      if (x < 0.75) {
        const singles = [PickOption.home, PickOption.draw, PickOption.away];
        return singles[rnd.nextInt(singles.length)];
      }
      const doubles = [
        PickOption.homeDraw,
        PickOption.drawAway,
        PickOption.homeAway,
      ];
      return doubles[rnd.nextInt(doubles.length)];
    }

    final picks = <String, PickOption>{};
    for (final m in matches) {
      picks[m.id] = randomPick();
    }
    return picks;
  }

  Widget _buildHistory(BuildContext context) {
    final appState = CassandraScope.of(context);
    appState.ensureCurrentUserPicksLoaded();
    final uid = appState.profile.id;
    final liveMatches = appState.cachedPredictionMatches ?? _matches;
    final liveOutcomes =
        appState.hasSavedOutcomesForMatchday(_effectiveMatchdayNumber)
        ? appState.outcomesForMatchday(_effectiveMatchdayNumber)
        : <String, MatchOutcome>{
            for (final m in liveMatches)
              if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
                m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
          };
    final livePicks = appState.currentUserPicksByMatchId.isNotEmpty
        ? appState.currentUserPicksByMatchId
        : _picks;
    final liveMatchday = MatchdayData(
      dayNumber: _effectiveMatchdayNumber,
      matches: liveMatches,
      outcomesByMatchId: liveOutcomes,
    );
    final historyDays = appState.recentMatchesByMatchday.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final demoHistory = mockSeasonMatchdays(
      startDay: 16,
      count: 4,
      demoSeed: appState.demoSeed,
    )..sort((a, b) => b.dayNumber.compareTo(a.dayNumber));
    Widget tileFor(
      MatchdayData md,
      Map<String, PickOption> picks, {
      String? tag,
    }) {
      final daysLabel = formatMatchdayDaysItalian(
        md.matches.map((m) => m.kickoff),
      );
      final total = md.matches.length;
      final graded = md.matches.where((m) {
        final o = md.outcomesByMatchId[m.id] ?? MatchOutcome.pending;
        return !o.isPending;
      }).length;
      final resultsLabel = graded == total
          ? 'risultati: $graded/$total'
          : 'risultati: $graded/$total (parziale)';
      final title = tag == null
          ? 'Giornata ${md.dayNumber}'
          : 'Giornata ${md.dayNumber} ($tag)';
      final appState = CassandraScope.of(context);
      final savedMatches = appState.matchesByMatchday[md.dayNumber];
      final matchesEffective = (savedMatches != null && savedMatches.isNotEmpty)
          ? savedMatches
          : md.matches;
      final savedOutcomes = appState.outcomesByMatchday[md.dayNumber];
      final outcomesEffective =
          (savedOutcomes != null && savedOutcomes.isNotEmpty)
          ? savedOutcomes
          : md.outcomesByMatchId;
      final picksEffective = appState.picksForCurrentUserForMatchday(
        md.dayNumber,
      );
      return Card(
        child: ListTile(
          title: Text(title),
          subtitle: Text('$daysLabel\n$resultsLabel'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PredictionsMatchdayPage(
                  matchdayNumber: md.dayNumber,
                  matches: matchesEffective,
                  outcomesByMatchId: outcomesEffective,
                  picksByMatchId: picksEffective,
                ),
              ),
            );
          },
        ),
      );
    }

    final liveTag = appState.cachedPredictionMatchesAreReal ? 'LIVE' : 'DEMO';
    appState.ensureCurrentUserPicksHistoryLoaded();
    final hasSavedLive = appState.hasSavedPicksForMatchday(
      _effectiveMatchdayNumber,
    );
    final livePicksEffective = hasSavedLive
        ? appState.currentUserPicksForMatchday(_effectiveMatchdayNumber)
        : livePicks;
    final liveTagEffective = hasSavedLive ? 'SALVATI' : liveTag;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Storico pronostici (DEMO)\n'
              'Qui mostriamo 16–19 dai mock. La giornata corrente è visibile sopra (LIVE/DEMO).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: 8),
        tileFor(liveMatchday, livePicksEffective, tag: liveTagEffective),
        const SizedBox(height: 12),
        if (historyDays.isNotEmpty)
          for (final day in historyDays)
            if (day != _matchdayNumber)
              Builder(
                builder: (context) {
                  final savedMatches = appState.matchesByMatchday[day];
                  final recentMatches = appState.recentMatchesByMatchday[day];
                  final matchesEffective =
                      (savedMatches != null && savedMatches.isNotEmpty)
                      ? savedMatches
                      : (recentMatches ?? const <PredictionMatch>[]);
                  if (matchesEffective.isEmpty) return const SizedBox.shrink();
                  final savedOutcomes = appState.outcomesByMatchday[day];
                  final recentOutcomes = appState.recentOutcomesByMatchday[day];
                  final outcomesEffective =
                      (savedOutcomes != null && savedOutcomes.isNotEmpty)
                      ? savedOutcomes
                      : (recentOutcomes ?? const <String, MatchOutcome>{});
                  final picksEffective = appState.hasSavedPicksForMatchday(day)
                      ? appState.currentUserPicksForMatchday(day)
                      : _demoPicksForMatchday(
                          '${uid}_${day}_${appState.demoSeed}',
                          matchesEffective,
                        );
                  final prog = appState.matchdayProgressFor(day);
                  final tag =
                      (prog != null && prog.primaryDone && !prog.finalDone)
                      ? 'RECUPERI'
                      : (appState.hasSavedPicksForMatchday(day)
                            ? 'SALVATI'
                            : 'LIVE');
                  final md = MatchdayData(
                    dayNumber: day,
                    matches: matchesEffective,
                    outcomesByMatchId: outcomesEffective,
                  );
                  return tileFor(md, picksEffective, tag: tag);
                },
              ),
        if (historyDays.isEmpty)
          for (final md in demoHistory)
            tileFor(
              appState.hasSavedOutcomesForMatchday(md.dayNumber)
                  ? MatchdayData(
                      dayNumber: md.dayNumber,
                      matches: md.matches,
                      outcomesByMatchId: appState.outcomesForMatchday(
                        md.dayNumber,
                      ),
                    )
                  : md,
              appState.hasSavedPicksForMatchday(md.dayNumber)
                  ? appState.currentUserPicksForMatchday(md.dayNumber)
                  : _demoPicksForMatchday(
                      '${uid}_${md.dayNumber}_${appState.demoSeed}',
                      md.matches,
                    ),
              tag: appState.hasSavedPicksForMatchday(md.dayNumber)
                  ? 'SALVATI'
                  : 'DEMO',
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = CassandraScope.of(context);
    final lockLabel = _locked
        ? 'giocate bloccate'
        : 'modificabile fino alle ${formatKickoff(_lockTime)}';
    final scoreOutcomesByMatchId = <String, MatchOutcome>{
      for (final m in _matches)
        if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
          m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
    };
    final DayScoreBreakdown dayScore = CassandraScoringEngine.computeDayScore(
      matches: _matches,
      picksByMatchId: {for (final m in _matches) m.id: _pickFor(m.id)},
      outcomesByMatchId: scoreOutcomesByMatchId,
    );
    final bonusSigned = dayScore.bonusPoints == 0
        ? '0'
        : (dayScore.bonusPoints > 0
              ? '+${dayScore.bonusPoints}'
              : '${dayScore.bonusPoints}');
    final scoreAvgLabel = dayScore.averageOddsPlayed == null
        ? '—'
        : formatOdds(dayScore.averageOddsPlayed!);
    final scoreLabel =
        'punti: ${formatOdds(dayScore.total)} (base ${formatOdds(dayScore.baseTotal)} • bonus $bonusSigned)'
        ' • corretti ${dayScore.correctCount}/${dayScore.matchBreakdowns.length}'
        ' • quota media $scoreAvgLabel';
    final avg = _averageOddsPlayed;
    final avgLabel = avg == null ? '-' : formatOdds(avg);
    final dataLabel = _usingRealFixtures ? 'dati: reali (API)' : 'dati: demo';
    final updatedLabel = (_usingRealFixtures && _fixturesUpdatedAt != null)
        ? ' • agg. ${formatKickoff(_fixturesUpdatedAt!)}'
        : '';
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Pronostici'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna match',
            onPressed: _loadingFixtures
                ? null
                : () => _tryLoadRealFixtures(showLoader: true),
            icon: _loadingFixtures
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.calculate),
              onPressed: _showDebugScorePreview,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 1,
                        label: Text('i pronostici passati'),
                      ),
                      ButtonSegment(
                        value: 0,
                        label: Text('i pronostici futuri'),
                      ),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (newSelection) {
                      setState(() => _segment = newSelection.first);
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _matchdayLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(lockLabel, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    scoreLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$dataLabel$updatedLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CassandraColors.slate,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'scelte: $_pickedCount/${_matches.length}  •  quota media: $avgLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CassandraColors.slate,
                    ),
                  ),
                  if (_submittedVisibility != null && _submittedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'ultimo invio: ${formatKickoff(_submittedAt!)} '
                      '(${_submittedVisibility == VisibilityChoice.public ? 'pubblica' : 'privata'})',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CassandraColors.slate,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _segment == 1
                  ? _buildHistory(context)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: _matches.length,
                      itemBuilder: (context, i) {
                        final match = _matches[i];
                        final pick = _pickFor(match.id);
                        return PredictionMatchCard(
                          match: match,
                          pick: pick,
                          locked: _locked,
                          onPick: (p) => _setPick(match.id, p),
                          onClear: () => _clearPick(match.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _segment == 1
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _locked
                            ? null
                            : () => _submit(VisibilityChoice.private),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: CassandraColors.primary,
                          ),
                          foregroundColor: CassandraColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('invia senza mostrare'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _locked
                            ? null
                            : () => _submit(VisibilityChoice.public),
                        style: FilledButton.styleFrom(
                          backgroundColor: CassandraColors.primary,
                          foregroundColor: CassandraColors.bg,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('invia e mostra'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
