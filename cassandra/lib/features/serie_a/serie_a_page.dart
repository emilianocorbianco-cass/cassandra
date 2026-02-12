import 'package:flutter/material.dart';

import '../../app/state/app_settings.dart';
import '../../app/state/app_state.dart';
import '../../app/widgets/team_name.dart';
import '../group/mock_group_data.dart';
import '../group/models/group_member.dart';
import '../group/widgets/group_matchday_leaderboard.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/pick_option.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';
import '../../app/state/cassandra_scope.dart';

class SerieAPage extends StatefulWidget {
  const SerieAPage({super.key});

  @override
  State<SerieAPage> createState() => _SerieAPageState();
}

class _SerieAPageState extends State<SerieAPage> {
  int _segment = 0; // 0 = risultati (last), 1 = classifica gruppo
  DateTime? _updatedAt;
  bool _didLoad = false;

  late Future<_SerieAData> _future;

  bool _isEnglish(AppState app) {
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  String _t(AppState app, String it, String en) => _isEnglish(app) ? en : it;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _future = _load();
  }

  Future<_SerieAData> _load() async {
    final app = CassandraScope.of(context);

    if (app.cachedPredictionMatches != null &&
        app.cachedPredictionMatches!.isNotEmpty &&
        app.cachedPredictionMatchesAreReal) {
      _updatedAt = app.cachedPredictionMatchesUpdatedAt;
      return _SerieAData(
        matches: app.cachedPredictionMatches!,
        outcomesByMatchId: {
          for (final m in app.cachedPredictionMatches!)
            if (app.effectivePredictionOutcomesByMatchId[m.id] != null)
              m.id: app.effectivePredictionOutcomesByMatchId[m.id]!,
        },
        fromBackend: true,
      );
    }

    final fs = app.firestoreService;
    if (fs == null) {
      return const _SerieAData(
        matches: [],
        outcomesByMatchId: {},
        fromBackend: false,
      );
    }

    try {
      final doc = await fs.getMatchdayData(
        seasonKey: app.currentSeasonKey,
        dayNumber: app.cassandraMatchdayCursor,
      );
      if (doc == null || doc.matches.isEmpty) {
        return const _SerieAData(
          matches: [],
          outcomesByMatchId: {},
          fromBackend: false,
        );
      }

      _updatedAt = doc.updatedAt;
      app.setCachedPredictionMatches(
        doc.matches,
        isReal: true,
        updatedAt: doc.updatedAt,
      );
      app.setCachedPredictionOutcomesByMatchId(doc.outcomesByMatchId);
      return _SerieAData(
        matches: doc.matches,
        outcomesByMatchId: doc.outcomesByMatchId,
        fromBackend: true,
      );
    } catch (e) {
      return _SerieAData(
        matches: const [],
        outcomesByMatchId: const {},
        fromBackend: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _reload() async {
    setState(() {
      _future = _load();
    });
    await _future;
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Live')),
      body: SafeArea(
        child: FutureBuilder<_SerieAData>(
          future: _future,
          builder: (context, snap) {
            final data = snap.data;

            final demoMatches = app.cachedPredictionMatches;
            final demoActive =
                demoMatches != null && !app.cachedPredictionMatchesAreReal;

            final updatedLabel = _updatedAt == null
                ? ''
                : ' \u2022 ${_t(app, 'agg.', 'upd.')} ${formatKickoff(_updatedAt!)}';

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<int>(
                        segments: [
                          ButtonSegment(
                            value: 0,
                            label: Text(_t(app, 'risultati', 'results')),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text(_t(app, 'classifica', 'standings')),
                          ),
                        ],
                        selected: {_segment},
                        onSelectionChanged: (s) =>
                            setState(() => _segment = s.first),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        demoActive
                            ? _t(app, 'dati: demo', 'data: demo')
                            : (data?.errorMessage != null
                                  ? _t(
                                      app,
                                      'Errore caricando cache backend: ${data?.errorMessage}',
                                      'Error loading backend cache: ${data?.errorMessage}',
                                    )
                                  : (data?.fromBackend == true
                                        ? _t(
                                            app,
                                            'dati: cache backend$updatedLabel',
                                            'data: backend cache$updatedLabel',
                                          )
                                        : _t(app, 'dati: demo', 'data: demo'))),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _segment == 1
                      ? _buildGroupLeaderboard(context, app)
                      : RefreshIndicator(
                          onRefresh: demoActive ? () async {} : _reload,
                          child: demoActive
                              ? _buildDemoList(
                                  context,
                                  _segment,
                                  demoMatches,
                                  app.cachedPredictionOutcomesByMatchId,
                                  app,
                                )
                              : _buildList(
                                  context,
                                  data ??
                                      const _SerieAData(
                                        matches: [],
                                        outcomesByMatchId: {},
                                        fromBackend: false,
                                      ),
                                  app,
                                ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGroupLeaderboard(BuildContext context, AppState appState) {
    final cachedMatches = appState.cachedPredictionMatches;
    if (cachedMatches == null || cachedMatches.isEmpty) {
      return Center(
        child: Text(
          _t(
            appState,
            'Nessun dato partite disponibile',
            'No match data available',
          ),
        ),
      );
    }

    final outcomesByMatchId = appState.cachedPredictionMatchesAreReal
        ? <String, MatchOutcome>{
            for (final m in cachedMatches)
              if (appState.effectivePredictionOutcomesByMatchId[m.id] != null)
                m.id: appState.effectivePredictionOutcomesByMatchId[m.id]!,
          }
        : <String, MatchOutcome>{};

    final overrideMember = GroupMember(
      id: appState.profile.id,
      displayName: appState.profile.displayName,
      teamName: appState.profile.teamName,
      avatarSeed: appState.currentUserAvatarSeed,
      favoriteTeam: appState.profile.favoriteTeam,
    );

    final members = mockGroupMembers(overrideMember: overrideMember);

    appState.ensureCurrentUserPicksLoaded();
    appState.ensureMemberPicksLoaded();

    final currentUserPicks = appState.currentUserPicksByMatchId;

    final overridePicksByMemberId = <String, Map<String, PickOption>>{
      ...appState.memberPicksByMemberId,
      overrideMember.id: currentUserPicks,
    };

    return GroupMatchdayLeaderboard(
      matches: cachedMatches,
      outcomesByMatchId: outcomesByMatchId,
      members: members,
      overridePicksByMemberId: overridePicksByMemberId,
    );
  }

  Widget _buildList(BuildContext context, _SerieAData data, AppState app) {
    final matches = List<PredictionMatch>.of(data.matches)
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    if (matches.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(
              _t(app, 'Nessuna partita da mostrare', 'No matches to show'),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: matches.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = matches[i];
        final o = data.outcomesByMatchId[m.id] ?? MatchOutcome.pending;
        final trailing = o.isPending ? '—' : o.label.toUpperCase();

        return Card(
          child: ListTile(
            title: Row(
              children: [
                Expanded(
                  child: TeamName(
                    name: m.homeTeam,
                    logoUrl: m.homeTeamLogo,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Text('  vs  '),
                Expanded(
                  child: TeamName(
                    name: m.awayTeam,
                    logoUrl: m.awayTeamLogo,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    reversed: true,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${_t(app, 'Kickoff', 'Kickoff')}: ${formatKickoff(m.kickoff)}',
            ),
            trailing: Text(
              trailing,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }
}

class _SerieAData {
  final List<PredictionMatch> matches;
  final Map<String, MatchOutcome> outcomesByMatchId;
  final bool fromBackend;
  final String? errorMessage;

  const _SerieAData({
    required this.matches,
    required this.outcomesByMatchId,
    required this.fromBackend,
    this.errorMessage,
  });
}

bool _isEnglishTop(BuildContext context, AppState app) {
  final code = app.language == CassandraLanguage.system
      ? Localizations.localeOf(context).languageCode
      : (app.language == CassandraLanguage.en ? 'en' : 'it');
  return code.toLowerCase().startsWith('en');
}

String _tTop(BuildContext context, AppState app, String it, String en) =>
    _isEnglishTop(context, app) ? en : it;

Widget _buildDemoList(
  BuildContext context,
  int segment,
  List<PredictionMatch> all,
  Map<String, MatchOutcome> outcomes,
  AppState app,
) {
  final matches = all.where((m) {
    final o = outcomes[m.id] ?? MatchOutcome.pending;
    return segment == 0 ? !o.isPending : o.isPending;
  }).toList()..sort((a, b) => a.kickoff.compareTo(b.kickoff));

  if (matches.isEmpty) {
    return Center(
      child: Text(
        segment == 0
            ? _tTop(context, app, 'Nessun risultato', 'No results')
            : _tTop(
                context,
                app,
                'Nessuna partita in programma',
                'No upcoming matches',
              ),
      ),
    );
  }

  return ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    itemCount: matches.length,
    separatorBuilder: (context, index) => const SizedBox(height: 12),
    itemBuilder: (context, i) {
      final m = matches[i];
      final o = outcomes[m.id] ?? MatchOutcome.pending;
      final subtitle =
          '${_tTop(context, app, 'Kickoff', 'Kickoff')}: ${formatKickoff(m.kickoff)}';
      final trailing = o.isPending ? '' : _demoOutcomeLabel(o);

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TeamName(
                            name: m.homeTeam,
                            logoUrl: m.homeTeamLogo,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '  vs  ',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Expanded(
                          child: TeamName(
                            name: m.awayTeam,
                            logoUrl: m.awayTeamLogo,
                            style: Theme.of(context).textTheme.titleMedium,
                            reversed: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (trailing.isNotEmpty)
                Text(trailing, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      );
    },
  );
}

String _demoOutcomeLabel(MatchOutcome o) {
  final raw = o.toString().split('.').last;
  if (raw == 'home') return '1';
  if (raw == 'draw') return 'X';
  if (raw == 'away') return '2';
  return raw.toUpperCase();
}
