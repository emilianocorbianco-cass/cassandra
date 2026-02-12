import 'package:cassandra/app/state/app_settings.dart';
import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/app/state/cassandra_scope.dart';
import 'package:flutter/material.dart';

import 'api_football_diagnostics_page.dart';
import 'package:cassandra/features/auth/login_page.dart';
import 'package:cassandra/features/predictions/models/formatters.dart';
import 'package:cassandra/features/group/mock_group_data.dart';
import 'package:cassandra/features/group/models/group_member.dart';
import 'package:cassandra/features/predictions/models/pick_option.dart';
import 'package:cassandra/features/group/widgets/group_image_picker.dart';

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

    final fs = app.firestoreService;
    if (fs == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _t(
              app,
              'Backend non configurato su questo device',
              'Backend not configured on this device',
            ),
          ),
        ),
      );
      if (mounted) setState(() => _fixturesRefreshing = false);
      return;
    }

    try {
      final doc = await fs.getMatchdayData(
        seasonKey: app.currentSeasonKey,
        dayNumber: app.cassandraMatchdayCursor,
      );
      if (doc == null || doc.matches.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _t(
                app,
                'Nessun dato backend disponibile per la giornata corrente',
                'No backend data available for the current matchday',
              ),
            ),
          ),
        );
        return;
      }

      app.setCachedPredictionMatches(
        doc.matches,
        isReal: true,
        updatedAt: doc.updatedAt,
      );
      app.setCachedPredictionOutcomesByMatchId(doc.outcomesByMatchId);

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _t(
              app,
              'Cache aggiornata da backend',
              'Cache refreshed from backend',
            ),
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _t(
              app,
              'Errore aggiornando da backend',
              'Error refreshing from backend',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _fixturesRefreshing = false);
    }
  }

  Widget _buildAccountSection(AppState app) {
    // Firebase non configurato (dev mode)
    if (app.authService == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(
            _t(
              app,
              'Modalita\u0027 sviluppo — Firebase non configurato',
              'Dev mode — Firebase not configured',
            ),
          ),
        ),
      );
    }

    // Autenticato
    if (app.isAuthenticated) {
      return Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(app.profile.displayName),
              subtitle: app.profile.email != null
                  ? Text(app.profile.email!)
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(_t(app, 'Esci', 'Sign out')),
              onTap: () => _confirmSignOut(app),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: Text(
                _t(app, 'Elimina account', 'Delete account'),
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () => _confirmDeleteAccount(app),
            ),
          ],
        ),
      );
    }

    // Non autenticato ma Firebase configurato
    return Card(
      child: ListTile(
        leading: const Icon(Icons.login),
        title: Text(_t(app, 'Accedi', 'Sign in')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const LoginPage()));
        },
      ),
    );
  }

  Future<void> _confirmSignOut(AppState app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t(app, 'Conferma', 'Confirm')),
        content: Text(
          _t(app, 'Vuoi uscire dal tuo account?', 'Sign out of your account?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_t(app, 'Annulla', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_t(app, 'Esci', 'Sign out')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await app.signOut();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _confirmDeleteAccount(AppState app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t(app, 'Elimina account', 'Delete account')),
        content: Text(
          _t(
            app,
            'Questa azione e\u0027 irreversibile. Vuoi continuare?',
            'This action is irreversible. Continue?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_t(app, 'Annulla', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(_t(app, 'Elimina', 'Delete')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await app.deleteAccount();
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              app,
              'Errore: riaccedi e riprova.',
              'Error: sign in again and retry.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final hasFixturesCache = app.cachedPredictionMatches != null;
    final dataLabel = !hasFixturesCache
        ? _t(app, 'cache: vuota', 'cache: empty')
        : (app.cachedPredictionMatchesAreReal
              ? _t(app, 'dati: cache backend', 'data: backend cache')
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Builder(
                builder: (context) {
                  final app = CassandraScope.of(context);
                  final matchCount = app.cachedPredictionMatches?.length ?? 0;
                  final outcomesCount =
                      app.cachedPredictionOutcomesByMatchId.length;
                  final kind = app.cachedPredictionMatchesAreReal
                      ? 'cache backend'
                      : (matchCount > 0 ? 'demo' : 'vuota');
                  final updated = app.cachedPredictionMatchesUpdatedAt;
                  String fmt(DateTime dt) {
                    final dd = dt.day.toString().padLeft(2, '0');
                    final mm = dt.month.toString().padLeft(2, '0');
                    final hh = dt.hour.toString().padLeft(2, '0');
                    final mi = dt.minute.toString().padLeft(2, '0');
                    return '$dd/$mm $hh:$mi';
                  }

                  final updatedLabel = (updated == null) ? 'mai' : fmt(updated);

                  void snack(String msg) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(msg)));
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Debug cache',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('fixtures: $kind'),
                      Text('match in cache: $matchCount'),
                      Text('outcomes in cache: $outcomesCount'),
                      Text('aggiornamento: $updatedLabel'),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Builder(
                            builder: (context) {
                              final app = CassandraScope.of(context);
                              app.ensureCurrentUserPicksLoaded();
                              app.ensureMemberPicksLoaded();

                              final matches = app.cachedPredictionMatches;
                              final canSeed =
                                  matches != null && matches.isNotEmpty;

                              final me = GroupMember(
                                id: app.profile.id,
                                displayName: app.profile.displayName,
                                teamName: app.profile.teamName,
                                avatarSeed: app.currentUserAvatarSeed,
                                favoriteTeam: app.profile.favoriteTeam,
                              );

                              final members = mockGroupMembers(
                                overrideMember: me,
                              );
                              final others = members
                                  .where((m) => m.id != me.id)
                                  .toList();

                              void snack(String msg) {
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(SnackBar(content: Text(msg)));
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Simulazione gruppo',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'picks simulati salvati: ${app.memberPicksByMemberId.length}',
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.tonal(
                                        onPressed: canSeed
                                            ? () {
                                                final seedKey = matches.isEmpty
                                                    ? ''
                                                    : matches.first.id;
                                                final map =
                                                    <
                                                      String,
                                                      Map<String, PickOption>
                                                    >{};
                                                for (final m in others) {
                                                  map[m.id] =
                                                      mockPicksForMember(
                                                        '${m.id}_$seedKey',
                                                        matches,
                                                      );
                                                }
                                                app.setMemberPicksBulk(
                                                  map,
                                                  replace: true,
                                                );
                                                snack(
                                                  'Picks generati per ${others.length} membri',
                                                );
                                              }
                                            : null,
                                        child: const Text('Genera picks'),
                                      ),
                                      FilledButton.tonal(
                                        onPressed: canSeed
                                            ? () {
                                                final map =
                                                    <
                                                      String,
                                                      Map<String, PickOption>
                                                    >{};
                                                final mine = app
                                                    .currentUserPicksByMatchId;
                                                for (final m in others) {
                                                  map[m.id] = mine;
                                                }
                                                app.setMemberPicksBulk(
                                                  map,
                                                  replace: true,
                                                );
                                                snack(
                                                  'Copiati i tuoi pick su ${others.length} membri',
                                                );
                                              }
                                            : null,
                                        child: const Text('Copia i miei'),
                                      ),
                                      FilledButton.tonal(
                                        onPressed: () {
                                          app.clearMemberPicks();
                                          snack('Picks simulati svuotati');
                                        },
                                        child: const Text('Svuota simulati'),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: () {
                              app.clearCachedPredictionMatches();
                              snack('Cache fixtures svuotata');
                            },
                            child: const Text('Svuota fixtures'),
                          ),
                          FilledButton.tonal(
                            onPressed: () {
                              app.clearCachedPredictionOutcomes();
                              snack('Cache outcomes svuotata');
                            },
                            child: const Text('Svuota outcomes'),
                          ),
                          FilledButton(
                            onPressed: () {
                              app.clearAllPredictionCache();
                              snack('Cache pronostici svuotata');
                            },
                            child: const Text('Svuota tutto'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
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

          if (app.hasGroup) ...[
            const SizedBox(height: 24),
            Text(
              _t(app, 'Gruppo', 'Group'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: GroupImageDisplay(
                      imagePath: app.groupImagePath,
                      radius: 20,
                    ),
                    title: Text(_t(app, 'Immagine del gruppo', 'Group image')),
                    subtitle: Text(
                      _t(
                        app,
                        'Tocca per cambiare la foto',
                        'Tap to change the photo',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final path =
                          await GroupImageHelper.pickAndSaveGroupImage();
                      if (path != null) {
                        app.updateGroupImagePath(path);
                      }
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(
                      _t(app, 'Approvazione admin', 'Admin approval'),
                    ),
                    subtitle: Text(
                      _t(
                        app,
                        'Solo l\'admin può accettare nuovi membri',
                        'Only the admin can accept new members',
                      ),
                    ),
                    value: app.groupAdminApproval,
                    onChanged: (value) {
                      app.updateGroupAdminApproval(value);
                    },
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          Text('Account', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildAccountSection(app),
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
                    _t(app, 'Aggiorna cache ora', 'Refresh cache now'),
                  ),
                  subtitle: Text(
                    _t(
                      app,
                      'Legge la matchday corrente dalla cache backend.',
                      'Reads current matchday from backend cache.',
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
                      'Torna ai dati demo locali fino al prossimo refresh.',
                      'Fallback to local demo data until next refresh.',
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
              title: Text(
                _t(app, 'Diagnostica backend', 'Backend diagnostics'),
              ),
              subtitle: Text(
                _t(
                  app,
                  'Verifica cache matchday letta da Firestore.',
                  'Verify matchday cache loaded from Firestore.',
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
