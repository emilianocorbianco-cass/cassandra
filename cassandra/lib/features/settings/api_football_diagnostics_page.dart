import 'package:flutter/material.dart';

import '../../app/config/env.dart';
import '../../services/api_football/api_football_client.dart';
import '../../services/api_football/api_football_exceptions.dart';
import '../../services/api_football/api_football_service.dart';
import '../../services/api_football/models/api_football_fixture.dart';

class ApiFootballDiagnosticsPage extends StatefulWidget {
  const ApiFootballDiagnosticsPage({super.key});

  @override
  State<ApiFootballDiagnosticsPage> createState() =>
      _ApiFootballDiagnosticsPageState();
}

class _ApiFootballDiagnosticsPageState
    extends State<ApiFootballDiagnosticsPage> {
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
        '1) Compila .env (non .env.example)\n'
        '2) Verifica che .env sia negli assets in pubspec.yaml\n',
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

  String _fmt(DateTime utc) {
    final d = utc.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API-FOOTBALL diagnostica'),
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
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Errore chiamata API',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(err.toString()),
                const SizedBox(height: 16),
                const Text(
                  'Checklist:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• .env esiste nella root?\n'
                  '• API_FOOTBALL_KEY è compilata?\n'
                  '• pubspec.yaml include assets: - .env ?\n'
                  '• Hai fatto flutter pub get ?\n'
                  '• Se usi RapidAPI: API_FOOTBALL_USE_RAPIDAPI=true\n',
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
            return const Center(child: Text('Nessun fixture trovato.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: fixtures.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final f = fixtures[i];
              return Card(
                child: ListTile(
                  title: Text('${f.homeName}  vs  ${f.awayName}'),
                  subtitle: Text(
                    '${_fmt(f.kickoffUtc)}'
                    '${f.round != null ? ' • ${f.round}' : ''}',
                  ),
                  trailing: Text(
                    f.statusShort.isEmpty ? '-' : f.statusShort,
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
