import 'package:cassandra/app/state/app_settings.dart';
import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/app/state/cassandra_scope.dart';
import 'package:flutter/material.dart';

import 'api_football_diagnostics_page.dart';
import 'package:cassandra/app/config/env.dart';
import 'package:cassandra/features/predictions/adapters/api_football_fixture_adapter.dart';
import 'package:cassandra/features/predictions/models/formatters.dart';
import 'package:cassandra/services/api_football/api_football_client.dart';
import 'package:cassandra/services/api_football/api_football_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _fixturesRefreshing = false;

  final _teamNameCtrl = TextEditingController();
  final _favoriteTeamCtrl = TextEditingController();

  bool _initialized = false;

  CassandraLanguage _language = CassandraLanguage.system;
  PredictionVisibility _defaultVisibility = PredictionVisibility.friends;

  @override
  void dispose() {
    _teamNameCtrl.dispose();
    _favoriteTeamCtrl.dispose();
    super.dispose();
  }

  bool _isEnglish(AppState app) {
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  String _t(AppState app, String it, String en) => _isEnglish(app) ? en : it;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) return;

    final app = CassandraScope.of(context);
    _teamNameCtrl.text = app.teamName;
    _favoriteTeamCtrl.text = app.favoriteTeam;

    _language = app.language;
    _defaultVisibility = app.defaultVisibility;

    _initialized = true;
  }

  Future<void> _save(AppState app) async {
    await app.updateTeamName(_teamNameCtrl.text);
    await app.updateFavoriteTeam(_favoriteTeamCtrl.text);
    await app.updateLanguage(_language);
    await app.updateDefaultVisibility(_defaultVisibility);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t(app, 'Impostazioni salvate', 'Settings saved')),
      ),
    );
  }

  Future<void> _reset(AppState app) async {
    await app.resetAll();

    setState(() {
      _teamNameCtrl.text = app.teamName;
      _favoriteTeamCtrl.text = app.favoriteTeam;
      _language = app.language;
      _defaultVisibility = app.defaultVisibility;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t(app, 'Ripristinato', 'Reset done'))),
    );
  }

  Future<void> _refreshFixturesCache() async {
    if (_fixturesRefreshing) return;

    final app = CassandraScope.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _fixturesRefreshing = true);

    String? key;
    try {
      key = Env.apiFootballKey;
    } catch (_) {
      key = null;
    }

    if (key == null || key.trim().isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(_t(app, 'API key mancante', 'Missing API key'))),
      );
      if (mounted) setState(() => _fixturesRefreshing = false);
      return;
    }

    final client = ApiFootballClient(
      apiKey: key,
      baseUrl: Env.baseUrl,
      useRapidApi: Env.useRapidApi,
      rapidApiHost: Env.rapidApiHost,
    );

    try {
      final service = ApiFootballService(client);
      final fixtures = await service.getNextSerieAFixtures(count: 10);
      final matches = predictionMatchesFromFixtures(fixtures);

      app.setCachedPredictionMatches(
        matches,
        isReal: true,
        updatedAt: DateTime.now(),
      );

      messenger.showSnackBar(
        SnackBar(
          content: Text(_t(app, 'Fixtures aggiornate', 'Fixtures updated')),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _t(app, 'Errore aggiornando fixtures', 'Error refreshing fixtures'),
          ),
        ),
      );
    } finally {
      client.close();
      if (mounted) setState(() => _fixturesRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final hasFixturesCache = app.cachedPredictionMatches != null;
    final dataLabel = !hasFixturesCache
        ? _t(app, 'cache: vuota', 'cache: empty')
        : (app.cachedPredictionMatchesAreReal
              ? _t(app, 'dati: reali (API)', 'data: real (API)')
              : _t(app, 'dati: demo', 'data: demo'));
    final updatedLabel = app.cachedPredictionMatchesUpdatedAt != null
        ? ' • ${_t(app, 'agg.', 'upd.')} ${formatKickoff(app.cachedPredictionMatchesUpdatedAt!)}'
        : '';

    final isEn = _isEnglish(app);

    return Scaffold(
      appBar: AppBar(title: Text(_t(app, 'Impostazioni', 'Settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _t(app, 'Profilo', 'Profile'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _teamNameCtrl,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: _t(app, 'Nome squadra (handle)', 'Team name (handle)'),
              hintText: _t(app, 'Es: FC Cassandra', 'Ex: FC Cassandra'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _favoriteTeamCtrl,
            decoration: InputDecoration(
              labelText: _t(app, 'Squadra del cuore', 'Favorite team'),
              hintText: _t(app, 'Es: Roma', 'Ex: Roma'),
            ),
          ),

          const SizedBox(height: 24),
          Text(
            _t(app, 'Lingua', 'Language'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<CassandraLanguage>(
            segments: <ButtonSegment<CassandraLanguage>>[
              ButtonSegment(
                value: CassandraLanguage.system,
                label: Text(isEn ? 'System' : 'Sistema'),
              ),
              const ButtonSegment(
                value: CassandraLanguage.it,
                label: Text('IT'),
              ),
              const ButtonSegment(
                value: CassandraLanguage.en,
                label: Text('EN'),
              ),
            ],
            selected: <CassandraLanguage>{_language},
            onSelectionChanged: (value) {
              setState(() => _language = value.first);
            },
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              app,
              'Nota: per ora molte etichette sono ancora “hardcoded”. Tradurremo a blocchi.',
              'Note: many labels are still hardcoded for now. We will translate in batches.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),

          const SizedBox(height: 24),
          Text(
            _t(app, 'Privacy pronostici (default)', 'Picks privacy (default)'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<PredictionVisibility>(
            segments: <ButtonSegment<PredictionVisibility>>[
              ButtonSegment(
                value: PredictionVisibility.public,
                label: Text(isEn ? 'Public' : 'Pubblico'),
              ),
              ButtonSegment(
                value: PredictionVisibility.friends,
                label: Text(isEn ? 'Friends' : 'Amici'),
              ),
              ButtonSegment(
                value: PredictionVisibility.private,
                label: Text(isEn ? 'Private' : 'Privato'),
              ),
            ],
            selected: <PredictionVisibility>{_defaultVisibility},
            onSelectionChanged: (value) {
              setState(() => _defaultVisibility = value.first);
            },
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              app,
              'Questa preferenza verrà usata quando collegheremo invio pronostici + backend.',
              'This preference will be used once we connect picks submission + backend.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),

          const SizedBox(height: 24),
          Text(
            _t(app, 'Diagnostica', 'Diagnostics'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          // Fixtures cache (runtime)
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: Text(_t(app, 'Fixtures cache', 'Fixtures cache')),
                  subtitle: Text('$dataLabel$updatedLabel'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: Text(
                    _t(app, 'Aggiorna fixtures ora', 'Refresh fixtures now'),
                  ),
                  subtitle: Text(
                    _t(
                      app,
                      'Scarica i prossimi 10 match di Serie A e aggiorna la cache.',
                      'Fetch next 10 Serie A matches and update cache.',
                    ),
                  ),
                  trailing: _fixturesRefreshing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _fixturesRefreshing ? null : _refreshFixturesCache,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(
                    _t(app, 'Svuota cache fixtures', 'Clear fixtures cache'),
                  ),
                  subtitle: Text(
                    _t(
                      app,
                      'Torna ai dati demo fino al prossimo refresh.',
                      'Fallback to demo data until next refresh.',
                    ),
                  ),
                  onTap: () {
                    app.clearCachedPredictionMatches();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _t(app, 'Cache svuotata', 'Cache cleared'),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          Card(
            child: ListTile(
              title: Text(_t(app, 'Test API-FOOTBALL', 'Test API-FOOTBALL')),
              subtitle: Text(
                _t(
                  app,
                  'Verifica chiave e chiamate base (fixtures).',
                  'Verify key and basic calls (fixtures).',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ApiFootballDiagnosticsPage(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _save(app),
                  child: Text(_t(app, 'Salva', 'Save')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _reset(app),
                  child: Text(_t(app, 'Reset', 'Reset')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
