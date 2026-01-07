import 'package:flutter/material.dart';

import '../../app/config/env.dart';
import '../predictions/models/formatters.dart';
import '../../services/api_football/api_football_client.dart';
import '../../services/api_football/api_football_service.dart';
import '../../services/api_football/models/api_football_fixture.dart';
import 'adapters/fixture_result_adapter.dart';

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
    try {
      final k = Env.apiFootballKey?.trim();
      if (k == null || k.isEmpty) return null;
      return k;
    } catch (_) {
      // In test env dotEnv può non essere inizializzato → non dobbiamo crashare.
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

      // 10 ultimi e 10 prossimi
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
      appBar: AppBar(title: const Text('Serie A')),
      body: SafeArea(
        child: FutureBuilder<_SerieAData>(
          future: _future,
          builder: (context, snap) {
            final data = snap.data;

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
                    onRefresh: _reload,
                    child: _buildList(context, snap),
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
        children: [
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
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final f = fixtures[i];

        final score = fixtureScoreLabel(f);
        final out = fixtureOutcomeLabel(f); // 1/X/2 oppure ""
        final trailing = out.isEmpty ? score : '$score\n$out';

        // Nomi squadra: supporta sia "homeTeam/awayTeam" che "homeName/awayName" via dynamic.
        final home = _teamName(f, isHome: true);
        final away = _teamName(f, isHome: false);

        final kickoff = _kickoff(f);

        return Card(
          child: ListTile(
            title: Text('$home  vs  $away'),
            subtitle: Text(
              'Kickoff: ${kickoff != null ? formatKickoff(kickoff) : '-'}',
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

  DateTime? _kickoff(ApiFootballFixture f) {
    try {
      // ignore: avoid_dynamic_calls
      return (f as dynamic).kickoff as DateTime?;
    } catch (_) {
      try {
        // ignore: avoid_dynamic_calls
        return (f as dynamic).date as DateTime?;
      } catch (_) {
        return null;
      }
    }
  }

  String _teamName(ApiFootballFixture f, {required bool isHome}) {
    try {
      // ignore: avoid_dynamic_calls
      return (isHome ? (f as dynamic).homeTeam : (f as dynamic).awayTeam)
          as String;
    } catch (_) {}

    try {
      // ignore: avoid_dynamic_calls
      return (isHome ? (f as dynamic).homeName : (f as dynamic).awayName)
          as String;
    } catch (_) {}

    try {
      // ignore: avoid_dynamic_calls
      final teams = (f as dynamic).teams;
      // ignore: avoid_dynamic_calls
      final team = isHome ? teams.home : teams.away;
      // ignore: avoid_dynamic_calls
      return (team.name as String?) ?? (isHome ? 'Home' : 'Away');
    } catch (_) {
      return isHome ? 'Home' : 'Away';
    }
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
