import 'package:flutter/material.dart';
import '../../app/theme/cassandra_colors.dart';
import '../../app/widgets/demo_banner.dart';
import '../../app/widgets/team_name.dart';
import 'models/mock_prediction_data.dart';
import 'models/pick_option.dart';
import 'models/prediction_match.dart';
import 'models/formatters.dart';
import 'widgets/prediction_match_card.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../scoring/models/match_outcome.dart';
import '../scoring/scoring_engine.dart';
import '../../app/state/app_settings.dart';
import '../../app/state/cassandra_scope.dart';
import '../../domain/matchday/matchday_recovery_rules.dart'
    show computeMatchdayProgress;
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

class _PredictionsPageState extends State<PredictionsPage>
    with AutomaticKeepAliveClientMixin {
  bool _forceDemoFixtures = false;

  bool _isLoadingRealFixtures = false;

  @override
  bool get wantKeepAlive => true;

  bool _isEnglish() {
    final app = CassandraScope.of(context);
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  String _t(String it, String en) => _isEnglish() ? en : it;

  bool _didLoadRealFixtures = false;

  bool get demoActive {
    final appState = CassandraScope.of(context);
    return appState.cachedPredictionMatches != null &&
        !appState.cachedPredictionMatchesAreReal;
  }

  List<PredictionMatch> get matches {
    final appState = CassandraScope.of(context);
    final cached = appState.cachedPredictionMatches;
    if (cached != null && !appState.cachedPredictionMatchesAreReal) {
      return cached;
    }
    if (_matches.isNotEmpty) return _matches;
    return cached ?? _matches;
  }

  String get matchdayLabel {
    final appState = CassandraScope.of(context);
    if (demoActive) {
      return '${_t('giornata', 'matchday')} ${appState.uiMatchdayNumber} - '
          '${formatMatchdayDays(matches.map((m) => m.kickoff), english: _isEnglish())}';
    }
    return _matchdayLabel;
  }

  int get _matchdayNumber => CassandraScope.of(context).cassandraMatchdayCursor;
  int? _shownMatchdayNumber;
  int get _effectiveMatchdayNumber {
    if (demoActive) return CassandraScope.of(context).uiMatchdayNumber;
    return _shownMatchdayNumber ?? _matchdayNumber;
  }

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
    if (kDebugMode) {
      debugPrint('[predictions] initState ${identityHashCode(this)}');
    }
    _matches = mockPredictionMatches();
  }

  @override
  void dispose() {
    if (kDebugMode) {
      debugPrint('[predictions] dispose ${identityHashCode(this)}');
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadRealFixtures) return;
    _didLoadRealFixtures = true;

    // Se home_shell ha già caricato dati reali in cache, sincronizziamo subito
    // lo stato locale così il badge "dati: reali" appare immediatamente.
    final scope = CassandraScope.of(context);
    final cached = scope.cachedPredictionMatches;
    if (cached != null &&
        cached.isNotEmpty &&
        scope.cachedPredictionMatchesAreReal) {
      _usingRealFixtures = true;
      _fixturesUpdatedAt =
          scope.cachedPredictionMatchesUpdatedAt ?? DateTime.now();
    }

    if (_didLoadFixtures) return;
    _tryLoadRealFixturesOnce();
  }

  PickOption _pickFor(String matchId) {
    final appState = CassandraScope.of(context);
    appState.cachedPredictionMatches != null &&
        !appState.cachedPredictionMatchesAreReal;

    appState.ensureCurrentUserPicksLoaded();
    return appState.currentUserPicksByMatchId[matchId] ?? PickOption.none;
  }

  int get _pickedCount => matches.where((m) => !_pickFor(m.id).isNone).length;
  int get _missingCount => matches.length - _pickedCount;
  DateTime? get _firstKickoff => matches.isEmpty
      ? null
      : matches.map((m) => m.kickoff).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get _lockTime =>
      _firstKickoff?.subtract(const Duration(minutes: 30));
  bool get _locked => _lockTime != null && DateTime.now().isAfter(_lockTime!);
  String get _matchdayLabel {
    final daysLabel = formatMatchdayDays(
      matches.map((m) => m.kickoff),
      english: _isEnglish(),
    );
    final appState = CassandraScope.of(context);
    final progress = appState.matchdayProgressFor(_effectiveMatchdayNumber);
    final status = progress == null
        ? ''
        : ' • ${String.fromCharCode(0x1F512)} ${progress.isLocked ? "LOCK" : "OPEN"}'
              ' • P:${progress.primaryDone ? "OK" : "..."}'
              ' • F:${progress.finalDone ? "OK" : "..."}'
              ' • ${progress.playedFixtures}/${progress.totalFixtures}'
              '${progress.voidFixtures > 0 ? " • ${_t('nulle', 'void')} ${progress.voidFixtures}" : ""}'
              ' • ${progress.isValidMatchday ? _t("valida", "valid") : _t("non valida", "invalid")}';
    return '${_t('giornata', 'matchday')} $_effectiveMatchdayNumber - $daysLabel$status';
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
    final PredictionMatch? match = matches.cast<PredictionMatch?>().firstWhere(
      (m) => m?.id == matchId,
      orElse: () => null,
    );
    if (match != null && DateTime.now().isAfter(match.kickoff)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Partita già iniziata: pick bloccato',
              'Match already started: pick locked',
            ),
          ),
        ),
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
            _t(
              'Hai lasciato $missing partite senza pronostico.\n\n'
                  'Regola Cassandra: per ogni partita non giocata verrà applicata '
                  'una penalità pari a -quota più alta (tra 1/X/2) in fase di calcolo.\n\n'
                  'Vuoi inviare comunque?',
              'You left $missing matches without a prediction.\n\n'
                  'Cassandra rule: for each unplayed match a penalty equal to '
                  '-highest odds (among 1/X/2) will be applied when scoring.\n\n'
                  'Submit anyway?',
            ),
          ),
          actions: [
            IconButton(
              tooltip: _t('Storico', 'History'),
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
              child: Text(_t('Annulla', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_t('Invia comunque', 'Submit anyway')),
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
        ? _t('pubblica', 'public')
        : _t('privata', 'private');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            'Schedina inviata (visibilità: $label)',
            'Slip submitted (visibility: $label)',
          ),
        ),
      ),
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
      matches: matches,
    );
    appState.ensureMatchesHistoryLoaded();
    appState.saveMatchesHistory(
      matchdayNumber: _effectiveMatchdayNumber,
      matches: matches,
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

    // Firestore sync (fire-and-forget)
    DayScoreBreakdown? scoreCache;
    if (outcomesNow.isNotEmpty) {
      scoreCache = CassandraScoringEngine.computeDayScore(
        matches: matches,
        picksByMatchId: _picks,
        outcomesByMatchId: outcomesNow,
      );
    }
    final visLabel = visibility == VisibilityChoice.public
        ? 'public'
        : 'private';
    appState.submitPicksToFirestore(
      dayNumber: _effectiveMatchdayNumber,
      picksByMatchId: _picks,
      visibility: visLabel,
      score: scoreCache,
    );
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
                              Row(
                                children: [
                                  Expanded(
                                    child: TeamName(
                                      name: m.homeTeam,
                                      logoUrl: m.homeTeamLogo,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const Text(' - '),
                                  Expanded(
                                    child: TeamName(
                                      name: m.awayTeam,
                                      logoUrl: m.awayTeamLogo,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      reversed: true,
                                    ),
                                  ),
                                ],
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
    final appState = CassandraScope.of(context);
    final fs = appState.firestoreService;

    if (showLoader && mounted) {
      setState(() => _loadingFixtures = true);
    }

    try {
      final scope = appState;
      // DEV: se abbiamo cache DEMO (isReal=false), non sovrascrivere con backend cache
      final cached = scope.cachedPredictionMatches;
      if (cached != null && !scope.cachedPredictionMatchesAreReal) {
        if (mounted) {
          setState(() {
            _shownMatchdayNumber = scope.uiMatchdayNumber;
            _matches = cached;
            _usingRealFixtures = false;
            _fixturesUpdatedAt =
                scope.cachedPredictionMatchesUpdatedAt ?? DateTime.now();
          });
        }
        // Compute MatchdayProgress for demo fixtures
        final demoNow = DateTime.now();
        final demoAppState = scope;
        demoAppState.ensureOriginKickoffsLoaded();
        final demoOutcomes = demoAppState.effectivePredictionOutcomesByMatchId;
        String demoStatusFor(PredictionMatch m) =>
            (demoOutcomes[m.id] ?? MatchOutcome.pending).isGraded ? 'FT' : 'NS';
        final demoProgress = computeMatchdayProgress<PredictionMatch>(
          cached,
          now: demoNow,
          kickoff: (m) => m.kickoff,
          originKickoff: (m) => demoAppState.originKickoffFor(
            matchId: m.id,
            fallbackKickoff: m.kickoff,
          ),
          statusShort: (m) => demoStatusFor(m),
        );
        demoAppState.setMatchdayProgress(
          matchdayNumber: demoAppState.uiMatchdayNumber,
          progress: demoProgress,
        );
        if (kDebugMode) {
          debugPrint(
            '[fixtures/demo] progress day=${demoAppState.uiMatchdayNumber} '
            'played=${demoProgress.playedFixtures} void=${demoProgress.voidFixtures}',
          );
        }
        return;
      }

      if (fs == null) {
        if (kDebugMode) {
          debugPrint('[fixtures] firestore unavailable -> using local/demo');
        }
        return;
      }

      final dayNumber = appState.cassandraMatchdayCursor;
      final doc = await fs.getMatchdayData(
        seasonKey: appState.currentSeasonKey,
        dayNumber: dayNumber,
      );

      if (doc == null || doc.matches.isEmpty) {
        if (kDebugMode) {
          debugPrint('[fixtures] no firestore data for day=$dayNumber');
        }
        return;
      }

      final matches = doc.matches;
      final outcomes = doc.outcomesByMatchId;
      final now = DateTime.now();

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
      await appState.persistOriginKickoffs();
      appState.setMatchdayProgress(
        matchdayNumber: doc.dayNumber,
        progress: progress,
      );

      if (kDebugMode) {
        debugPrint(
          '[fixtures] progress day=${doc.dayNumber} '
          'primaryDone=${progress.primaryDone} finalDone=${progress.finalDone} '
          'played=${progress.playedFixtures} void=${progress.voidFixtures}',
        );
      }

      if (!mounted) return;
      setState(() {
        _shownMatchdayNumber = doc.dayNumber;
        _matches = matches;
        _usingRealFixtures = true;
        _fixturesUpdatedAt = doc.updatedAt;
      });
      scope.setCachedPredictionMatches(
        matches,
        isReal: true,
        updatedAt: doc.updatedAt,
      );
      scope.setCachedPredictionOutcomesByMatchId(outcomes);
      appState.setRecentMatchdayDataBulk(
        matchesByMatchday: {doc.dayNumber: matches},
        outcomesByMatchday: {doc.dayNumber: outcomes},
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[fixtures] load failed: $e');
        debugPrint('$st');
      }
    } finally {
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
      final en = _isEnglish();
      final daysLabel = formatMatchdayDays(
        md.matches.map((m) => m.kickoff),
        english: en,
      );
      final total = md.matches.length;
      final graded = md.matches.where((m) {
        final o = md.outcomesByMatchId[m.id] ?? MatchOutcome.pending;
        return !o.isPending;
      }).length;
      final resultsLabel = graded == total
          ? '${en ? 'results' : 'risultati'}: $graded/$total'
          : '${en ? 'results' : 'risultati'}: $graded/$total (${en ? 'partial' : 'parziale'})';
      final mdLabel = en ? 'Matchday' : 'Giornata';
      final title = tag == null
          ? '$mdLabel ${md.dayNumber}'
          : '$mdLabel ${md.dayNumber} ($tag)';
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
              _t(
                'Storico pronostici (DEMO)\n'
                    'Qui mostriamo 16–19 dai mock. La giornata corrente è visibile sopra (LIVE/DEMO).',
                'Predictions history (DEMO)\n'
                    'Showing 16–19 from mocks. Current matchday is visible above (LIVE/DEMO).',
              ),
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
    super.build(context);

    final appState = CassandraScope.of(context);

    // Mentre i dati reali si caricano, mostra spinner
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(_t('Pronostici', 'Predictions')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final voidedByPostponement = <String>{};
    for (final m in matches) {
      final origin = appState.originKickoffFor(
        matchId: m.id,
        fallbackKickoff: m.kickoff,
      );
      final diff = m.kickoff.difference(origin);
      if (diff > const Duration(hours: 48)) {
        voidedByPostponement.add(m.id);
      }
    }
    final scoringMatches = matches
        .where((m) => !voidedByPostponement.contains(m.id))
        .toList(growable: false);
    final pickedCountForScoring = scoringMatches
        .where((m) => !_pickFor(m.id).isNone)
        .length;
    final lockLabel = _locked
        ? _t('giocate bloccate', 'picks locked')
        : _lockTime != null
        ? _t(
            'modificabile fino alle ${formatKickoff(_lockTime!)}',
            'editable until ${formatKickoff(_lockTime!)}',
          )
        : '';
    final scoreOutcomesByMatchId = <String, MatchOutcome>{
      for (final m in scoringMatches)
        if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
          m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
    };
    final DayScoreBreakdown dayScore = CassandraScoringEngine.computeDayScore(
      matches: scoringMatches,
      picksByMatchId: {for (final m in scoringMatches) m.id: _pickFor(m.id)},
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
    final scoreLabel = _isEnglish()
        ? 'points: ${formatOdds(dayScore.total)} (base ${formatOdds(dayScore.baseTotal)} • bonus $bonusSigned)'
              ' • correct ${dayScore.correctCount}/${dayScore.matchBreakdowns.length}'
              ' • avg odds $scoreAvgLabel'
        : 'punti: ${formatOdds(dayScore.total)} (base ${formatOdds(dayScore.baseTotal)} • bonus $bonusSigned)'
              ' • corretti ${dayScore.correctCount}/${dayScore.matchBreakdowns.length}'
              ' • quota media $scoreAvgLabel';
    final avg = _averageOddsPlayed;
    final avgLabel = avg == null ? '-' : formatOdds(avg);
    final dataLabel = (demoActive || _forceDemoFixtures)
        ? _t('dati: demo', 'data: demo')
        : (_usingRealFixtures
              ? _t('dati: reali (cache backend)', 'data: real (backend cache)')
              : _t('dati: demo', 'data: demo'));
    final updatedLabel =
        (_usingRealFixtures && !demoActive && _fixturesUpdatedAt != null)
        ? ' • ${_t('agg.', 'upd.')} ${formatKickoff(_fixturesUpdatedAt!)}'
        : '';
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(_t('Pronostici', 'Predictions')),
        actions: [
          IconButton(
            tooltip: _t('Aggiorna match', 'Refresh matches'),
            onPressed: (_loadingFixtures || demoActive || _forceDemoFixtures)
                ? null
                : () => _tryLoadRealFixturesOnce(showLoader: true, force: true),
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
              tooltip: _forceDemoFixtures
                  ? _t('Usa cache backend', 'Use backend cache')
                  : _t('Forza dati demo', 'Force demo data'),
              icon: Icon(_forceDemoFixtures ? Icons.public : Icons.science),
              onPressed: () async {
                final enableDemo = !_forceDemoFixtures;
                setState(() {
                  _forceDemoFixtures = enableDemo;
                  if (enableDemo) {
                    _usingRealFixtures = false;
                    _matches = mockPredictionMatches();
                  }
                });
                if (!enableDemo) {
                  await _tryLoadRealFixturesOnce(showLoader: true, force: true);
                }
              },
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
            if (!_usingRealFixtures)
              DemoBanner(
                label: _t(
                  'Dati di esempio \u2014 attendi sincronizzazione backend',
                  'Sample data \u2014 wait for backend sync',
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 1,
                        label: Text(
                          _t('i pronostici passati', 'past predictions'),
                        ),
                      ),
                      ButtonSegment(
                        value: 0,
                        label: Text(
                          _t('i pronostici futuri', 'upcoming predictions'),
                        ),
                      ),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (newSelection) {
                      setState(() => _segment = newSelection.first);
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    matchdayLabel,
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
                  const SizedBox(height: 4),
                  if (kDebugMode)
                    Builder(
                      builder: (context) {
                        var shifted = 0;
                        var under48 = 0;
                        var over48 = 0;
                        for (final m in matches) {
                          final origin = appState.originKickoffFor(
                            matchId: m.id,
                            fallbackKickoff: m.kickoff,
                          );
                          if (!m.kickoff.isAtSameMomentAs(origin)) {
                            shifted++;
                            final d = m.kickoff.difference(origin);
                            if (d < const Duration(hours: 48)) {
                              under48++;
                            } else {
                              over48++;
                            }
                          }
                        }
                        return Text(
                          'debug: shiftate $shifted • <48h $under48 • >48h $over48',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: CassandraColors.slate),
                        );
                      },
                    ),

                  if (kDebugMode)
                    Text(
                      "debug: giocate ${appState.matchdayProgressFor(_effectiveMatchdayNumber)?.playedFixtures ?? '-'}"
                      " • nulle ${appState.matchdayProgressFor(_effectiveMatchdayNumber)?.voidFixtures ?? '-'}",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 6),
                  Text(
                    '${_t('scelte', 'picks')}: $pickedCountForScoring/${scoringMatches.length}  •  ${_t('quota media', 'avg odds')}: $avgLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CassandraColors.slate,
                    ),
                  ),
                  if (_submittedVisibility != null && _submittedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${_t('ultimo invio', 'last submit')}: ${formatKickoff(_submittedAt!)} '
                      '(${_submittedVisibility == VisibilityChoice.public ? _t('pubblica', 'public') : _t('privata', 'private')})',
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
                      itemCount: matches.length,
                      itemBuilder: (context, i) {
                        final match = matches[i];
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
                        child: Text(
                          _t('invia senza mostrare', 'submit without showing'),
                        ),
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
                        child: Text(_t('invia e mostra', 'submit and show')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _tryLoadRealFixturesOnce({
    bool showLoader = false,
    bool force = false,
  }) async {
    if (_isLoadingRealFixtures) {
      return;
    }
    if (_didLoadFixtures && !force) {
      return;
    }
    _isLoadingRealFixtures = true;
    try {
      await _tryLoadRealFixtures(showLoader: showLoader);
      _didLoadFixtures = true;
    } finally {
      _isLoadingRealFixtures = false;
    }
  }
}
