import 'package:flutter/material.dart';

import '../../features/predictions/predictions_page.dart';
import '../../features/group/group_page.dart';

import '../../features/stats/stats_page.dart';
import '../../features/settings/settings_page.dart';
import 'package:cassandra/features/serie_a/serie_a_page.dart';
import 'package:cassandra/app/state/cassandra_scope.dart';
import 'package:flutter/foundation.dart';
import '../state/app_settings.dart';
import '../theme/app_colors.dart';

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
    final app = CassandraScope.of(context);

    // ── Firestore fast path: try cached matchday data first ──
    final fs = app.firestoreService;
    if (fs != null) {
      try {
        final doc = await fs.getMatchdayData(
          seasonKey: app.currentSeasonKey,
          dayNumber: app.cassandraMatchdayCursor,
        );
        if (doc != null && doc.matches.isNotEmpty) {
          app.setCachedPredictionMatches(
            doc.matches,
            isReal: true,
            updatedAt: doc.updatedAt,
          );
          app.setCachedPredictionOutcomesByMatchId(doc.outcomesByMatchId);

          // If data is fresh (< 65 min), skip API call
          if (DateTime.now().difference(doc.updatedAt).inMinutes < 65) {
            if (kDebugMode) {
              debugPrint(
                '[prefetch] Firestore data fresh '
                '(${doc.matches.length} matches, '
                '${DateTime.now().difference(doc.updatedAt).inMinutes}min old)',
              );
            }
            return;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[prefetch] Firestore read failed: $e');
        }
      }
    }

    // Backend-only mode: niente fallback API lato client.
  }

  bool _isEnglish() {
    final app = CassandraScope.of(context);
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  int _index = 0;

  static final _pages = <Widget>[
    PredictionsPage(),
    GroupPage(),
    SerieAPage(),
    StatsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final appState = CassandraScope.of(context);

    return Scaffold(
      // IndexedStack: mantiene lo stato delle pagine quando cambi tab.
      body: AnimatedBuilder(
        animation: appState,
        builder: (context, _) => IndexedStack(index: _index, children: _pages),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.navBarBg,
          indicatorColor: AppColors.navBarBg,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          iconTheme: WidgetStateProperty.all(
            const IconThemeData(color: Color(0xFFF6F4EF)),
          ),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(color: Color(0xFFF6F4EF)),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.sports_soccer),
              label: _isEnglish() ? 'Predictions' : 'Pronostici',
            ),
            NavigationDestination(
              icon: const Icon(Icons.groups),
              label: _isEnglish() ? 'Group' : 'Gruppo',
            ),
            NavigationDestination(
              icon: const Icon(Icons.format_list_bulleted),
              label: 'Live',
            ),
            NavigationDestination(
              icon: const Icon(Icons.bar_chart),
              label: 'Stats',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
