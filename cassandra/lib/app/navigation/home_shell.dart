import 'package:flutter/material.dart';

import '../../features/predictions/predictions_page.dart';
import '../../features/group/group_page.dart';
import '../../features/leaderboards/leaderboards_page.dart';
import '../../features/stats/stats_page.dart';
import '../../features/settings/settings_page.dart';
import 'package:cassandra/features/serie_a/serie_a_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
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
            label: 'Serie A',
          ),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
