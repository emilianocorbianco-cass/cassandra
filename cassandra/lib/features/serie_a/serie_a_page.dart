import 'package:flutter/material.dart';

import '../../app/config/env.dart';
import '../../services/api_football/api_football_client.dart';
import '../../services/api_football/api_football_exceptions.dart';
import '../../services/api_football/api_football_service.dart';
import '../../services/api_football/models/api_football_fixture.dart';

class SerieAPage extends StatefulWidget {
  const SerieAPage({super.key});

  @override
  State<SerieAPage> createState() => _SerieAPageState();
}

class _SerieAPageState extends State<SerieAPage> {
  late Future<List<ApiFootballFixture>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ApiFootballFixture>> _load() async {
    final key = Env.apiFootballKey;
    if (key == null) {
      throw Exception(
        'API_FOOTBALL_KEY mancante.\n'
        'Vai in root del progetto e compila .env (non .env.example).',
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
      return await service.getNextSerieAFixtures(count: 10);
    } finally {
      client.close();
    }
  }

  String _fmtKickoff(DateTime utc) {
    final local = utc.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Serie A'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = _load()),
          ),
        ],
      ),
      body: FutureBuilder<List<ApiFootballFixture>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            final err = snap.error;
            // Mostriamo informazioni utili se l'API risponde con HTTP error
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Errore caricando i match',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(err.toString()),
                const SizedBox(height: 16),
                const Text(
                  'Suggerimenti:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• Controlla che .env esista e abbia API_FOOTBALL_KEY\n'
                  '• Controlla pubspec.yaml: assets include - .env\n'
                  '• Se usi RapidAPI: API_FOOTBALL_USE_RAPIDAPI=true\n'
                  '• Se la diagnostica funziona ma qui no, incolla l’errore\n',
                ),
                if (err is ApiFootballHttpException) ...[
                  const SizedBox(height: 16),
                  Text('HTTP status: ${err.statusCode}'),
                  const SizedBox(height: 8),
                  Text('Body:\n${err.responseBody}'),
                ],
              ],
            );
          }

          final fixtures = snap.data ?? const <ApiFootballFixture>[];
          if (fixtures.isEmpty) {
            return const Center(child: Text('Nessun match trovato.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: fixtures.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final f = fixtures[i];

              final hasScore = f.homeGoals != null && f.awayGoals != null;
              final trailing = hasScore
                  ? '${f.homeGoals}-${f.awayGoals}'
                  : (f.statusShort.isEmpty ? '-' : f.statusShort);

              return Card(
                child: ListTile(
                  title: Text('${f.homeName}  vs  ${f.awayName}'),
                  subtitle: Text(
                    '${_fmtKickoff(f.kickoffUtc)}'
                    '${f.round != null ? ' • ${f.round}' : ''}',
                  ),
                  trailing: Text(
                    trailing,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
