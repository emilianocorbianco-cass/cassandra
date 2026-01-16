import 'package:flutter/material.dart';

import '../../features/predictions/predictions_page.dart';
import '../../features/group/group_page.dart';
import '../../features/leaderboards/leaderboards_page.dart';
import '../../features/stats/stats_page.dart';
import '../../features/settings/settings_page.dart';
import 'package:cassandra/features/serie_a/serie_a_page.dart';
import 'package:cassandra/app/config/env.dart';
import 'package:cassandra/app/state/cassandra_scope.dart';
import 'package:cassandra/features/predictions/adapters/api_football_fixture_adapter.dart';
import 'package:cassandra/services/api_football/api_football_client.dart';
import 'package:cassandra/services/api_football/api_football_service.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool _prefetchStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefetchStarted) return;

    // Se la cache è già reale (es. arrivata da un'altra pagina), non richiamiamo l'API.
    final app = CassandraScope.of(context);
    if (app.cachedPredictionMatches != null &&
        app.cachedPredictionMatchesAreReal) {
      _prefetchStarted = true;
      return;
    }

    _prefetchStarted = true;
    _prefetchNextFixtures();
  }

  Future<void> _prefetchNextFixtures() async {
    // Nei test può succedere che dotenv non sia inizializzato.
    String? key;
    try {
      key = Env.apiFootballKey;
    } catch (_) {
      return;
    }
    if (key == null) return;
    final app = CassandraScope.of(context);

    final client = ApiFootballClient(
      apiKey: key,
      baseUrl: Env.baseUrl,
      useRapidApi: Env.useRapidApi,
      rapidApiHost: Env.rapidApiHost,
    );

    try {
      final service = ApiFootballService(client);
      final fixtures = await service.getNextSerieAFixtures(count: 10);
      if (fixtures.isEmpty) return;

      final matches = predictionMatchesFromFixtures(
        fixtures,
        useMockIds: false,
      );

      app.setCachedPredictionMatches(
        matches,
        isReal: true,
        updatedAt: DateTime.now(),
      );
    } catch (_) {
      // Silenzioso: fallback su mock nelle pagine.
    } finally {
      client.close();
    }
  }

  int _index = 0;

  static final _pages = <Widget>[
    PredictionsPage(),
    GroupPage(),
    LeaderboardsPage(),
    SerieAPage(),
    StatsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack: mantiene lo stato delle pagine quando cambi tab.
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sports_soccer),
            label: 'Pronostici',
          ),
          NavigationDestination(icon: Icon(Icons.groups), label: 'Gruppo'),
          NavigationDestination(
            icon: Icon(Icons.emoji_events),
            label: 'Classifiche',
          ),
          NavigationDestination(
            icon: Icon(Icons.format_list_bulleted),
            label: 'Live',
          ),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
