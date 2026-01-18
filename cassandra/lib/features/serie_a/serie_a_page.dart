import 'package:flutter/material.dart';

import '../../app/config/env.dart';
import '../../services/api_football/api_football_client.dart';
import '../../services/api_football/api_football_service.dart';
import '../../services/api_football/models/api_football_fixture.dart';
import '../predictions/models/formatters.dart';
import '../predictions/models/prediction_match.dart';
import '../scoring/models/match_outcome.dart';
import 'adapters/fixture_result_adapter.dart';
import '../../app/state/cassandra_scope.dart';

class SerieAPage extends StatefulWidget {
  const SerieAPage({super.key});

  @override
  State<SerieAPage> createState() => _SerieAPageState();
}

class _SerieAPageState extends State<SerieAPage> {
  int _segment = 0; // 0 = risultati (last), 1 = prossime (next)
  DateTime? _updatedAt;

  late Future<_SerieAData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  String? _safeApiKey() {
    // In test env dotEnv può non essere inizializzato → non dobbiamo crashare.
    try {
      final raw = Env.apiFootballKey;
      final k = raw?.trim();
      if (k == null || k.isEmpty) return null;
      return k;
    } catch (_) {
      return null;
    }
  }

  Future<_SerieAData> _load() async {
    final key = _safeApiKey();
    if (key == null) {
      return const _SerieAData(
        last: [],
        next: [],
        errorMessage: 'API key mancante (Settings → env).',
      );
    }

    final client = ApiFootballClient(
      apiKey: key,
      baseUrl: Env.baseUrl,
      useRapidApi: Env.useRapidApi,
      rapidApiHost: Env.rapidApiHost,
    );

    try {
      final service = ApiFootballService(client);

      final last = await service.getLastSerieAFixtures(count: 10);
      final next = await service.getNextSerieAFixtures(count: 10);

      _updatedAt = DateTime.now();
      return _SerieAData(last: last, next: next);
    } catch (e) {
      return _SerieAData(
        last: const [],
        next: const [],
        errorMessage: 'Errore caricando fixture: $e',
      );
    } finally {
      client.close();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Live')),
      body: SafeArea(
        child: FutureBuilder<_SerieAData>(
          future: _future,
          builder: (context, snap) {
            final data = snap.data;

            final appState = CassandraScope.of(context);
            final demoMatches = appState.cachedPredictionMatches;
            final demoActive =
                demoMatches != null && !appState.cachedPredictionMatchesAreReal;

            final updatedLabel = _updatedAt == null
                ? ''
                : ' • agg. ${formatKickoff(_updatedAt!)}';

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text('risultati')),
                          ButtonSegment(value: 1, label: Text('prossime')),
                        ],
                        selected: {_segment},
                        onSelectionChanged: (s) =>
                            setState(() => _segment = s.first),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data?.errorMessage != null
                            ? data!.errorMessage!
                            : 'dati: reali (API)$updatedLabel',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: demoActive ? () async {} : _reload,
                    child: demoActive
                        ? _buildDemoList(
                            context,
                            _segment,
                            demoMatches,
                            appState.cachedPredictionOutcomesByMatchId,
                          )
                        : _buildList(context, snap),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, AsyncSnapshot<_SerieAData> snap) {
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return ListView(
        children: const [
          SizedBox(height: 240),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    final data =
        snap.data ??
        const _SerieAData(last: [], next: [], errorMessage: 'Nessun dato.');

    final fixtures = _segment == 0 ? data.last : data.next;

    if (fixtures.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: Text('Nessuna partita da mostrare')),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: fixtures.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final f = fixtures[i];

        final score = fixtureScoreLabel(f);
        final out = fixtureOutcomeLabel(f); // 1/X/2 oppure ""
        final trailing = out.isEmpty ? score : '$score\n$out';

        final kickoffLocal = f.kickoffUtc.toLocal();

        final extra = <String>[];
        if (f.round != null && f.round!.trim().isNotEmpty) {
          extra.add(f.round!.trim());
        }
        // Nei "risultati" è utile vedere lo status (FT, AET, ecc.)
        if (_segment == 0 && f.statusShort.trim().isNotEmpty) {
          extra.add(f.statusShort.trim());
        }

        final extraLabel = extra.isEmpty ? '' : ' • ${extra.join(' • ')}';

        return Card(
          child: ListTile(
            title: Text('${f.homeName}  vs  ${f.awayName}'),
            subtitle: Text(
              'Kickoff: ${formatKickoff(kickoffLocal)}$extraLabel',
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
  final List<ApiFootballFixture> last;
  final List<ApiFootballFixture> next;
  final String? errorMessage;

  const _SerieAData({
    required this.last,
    required this.next,
    this.errorMessage,
  });
}

Widget _buildDemoList(
  BuildContext context,
  int segment,
  List<PredictionMatch> all,
  Map<String, MatchOutcome> outcomes,
) {
  final matches = all.where((m) {
    final o = outcomes[m.id] ?? MatchOutcome.pending;
    return segment == 0 ? !o.isPending : o.isPending;
  }).toList()..sort((a, b) => a.kickoff.compareTo(b.kickoff));

  if (matches.isEmpty) {
    return Center(
      child: Text(
        segment == 0 ? 'Nessun risultato' : 'Nessuna partita in programma',
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
      final title = _demoTitleFor(m);
      final subtitle = 'Kickoff: ${formatKickoff(m.kickoff)}';
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
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
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

String _demoTitleFor(PredictionMatch m) {
  final d = m as dynamic;

  String? readStr(Object? Function() f) {
    try {
      final v = f();
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return null;
  }

  String? readTeamName(Object? Function() f) {
    try {
      final v = f();
      if (v is String && v.trim().isNotEmpty) return v.trim();
      final name = (v as dynamic).name;
      if (name is String && name.trim().isNotEmpty) return name.trim();
    } catch (_) {}
    return null;
  }

  final home =
      readStr(() => d.homeTeamName) ??
      readStr(() => d.homeName) ??
      readStr(() => d.home) ??
      readTeamName(() => d.homeTeam) ??
      '?';

  final away =
      readStr(() => d.awayTeamName) ??
      readStr(() => d.awayName) ??
      readStr(() => d.away) ??
      readTeamName(() => d.awayTeam) ??
      '?';

  return '$home  vs  $away';
}

String _demoOutcomeLabel(MatchOutcome o) {
  final raw = o.toString().split('.').last;
  if (raw == 'home') return '1';
  if (raw == 'draw') return 'X';
  if (raw == 'away') return '2';
  return raw.toUpperCase();
}
