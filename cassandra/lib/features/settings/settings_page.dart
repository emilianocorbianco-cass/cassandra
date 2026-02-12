import 'package:cassandra/app/state/app_settings.dart';
import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/app/state/cassandra_scope.dart';
import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context)!;
    await app.updateTeamName(_teamNameCtrl.text);
    await app.updateFavoriteTeam(_favoriteTeamCtrl.text);
    await app.updateLanguage(_language);
    await app.updateDefaultVisibility(_defaultVisibility);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.settingsSaved)));
  }

  Future<void> _reset(AppState app) async {
    final l10n = AppLocalizations.of(context)!;
    await app.resetAll();

    setState(() {
      _teamNameCtrl.text = app.teamName;
      _favoriteTeamCtrl.text = app.favoriteTeam;
      _language = app.language;
      _defaultVisibility = app.defaultVisibility;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.settingsResetDone)));
  }

  Future<void> _refreshFixturesCache() async {
    if (_fixturesRefreshing) return;

    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _fixturesRefreshing = true);

    final fs = app.firestoreService;
    if (fs == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsBackendNotConfigured)),
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
          SnackBar(content: Text(l10n.settingsNoBackendDataCurrentMatchday)),
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
        SnackBar(content: Text(l10n.settingsCacheRefreshedFromBackend)),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsCacheRefreshError)),
      );
    } finally {
      if (mounted) setState(() => _fixturesRefreshing = false);
    }
  }

  Widget _buildAccountSection(AppState app) {
    final l10n = AppLocalizations.of(context)!;
    // Firebase non configurato (dev mode)
    if (app.authService == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.settingsDevModeNoFirebase),
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
              title: Text(l10n.settingsSignOut),
              onTap: () => _confirmSignOut(app),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: Text(
                l10n.settingsDeleteAccount,
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
        title: Text(l10n.settingsSignIn),
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
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsConfirm),
        content: Text(l10n.settingsSignOutQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.settingsCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.settingsSignOut),
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
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsDeleteAccount),
        content: Text(l10n.settingsDeleteAccountQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.settingsCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.settingsDelete),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.settingsReauthError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final hasFixturesCache = app.cachedPredictionMatches != null;
    final dataLabel = !hasFixturesCache
        ? l10n.settingsCacheEmpty
        : (app.cachedPredictionMatchesAreReal
              ? l10n.settingsDataBackendCache
              : l10n.settingsDataDemo);
    final updatedLabel = app.cachedPredictionMatchesUpdatedAt != null
        ? ' • ${l10n.shortUpdated} ${formatKickoff(app.cachedPredictionMatchesUpdatedAt!)}'
        : '';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
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
                      ? l10n.settingsKindBackendCache
                      : (matchCount > 0
                            ? l10n.settingsKindDemo
                            : l10n.settingsKindEmpty);
                  final updated = app.cachedPredictionMatchesUpdatedAt;
                  String fmt(DateTime dt) {
                    final dd = dt.day.toString().padLeft(2, '0');
                    final mm = dt.month.toString().padLeft(2, '0');
                    final hh = dt.hour.toString().padLeft(2, '0');
                    final mi = dt.minute.toString().padLeft(2, '0');
                    return '$dd/$mm $hh:$mi';
                  }

                  final updatedLabel = (updated == null)
                      ? l10n.settingsNever
                      : fmt(updated);

                  void snack(String msg) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(msg)));
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.settingsDebugCacheTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(l10n.settingsDebugFixturesLine(kind)),
                      Text(l10n.settingsDebugMatchInCacheLine(matchCount)),
                      Text(
                        l10n.settingsDebugOutcomesInCacheLine(outcomesCount),
                      ),
                      Text(l10n.settingsDebugUpdateLine(updatedLabel)),
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
                                    l10n.settingsSimulationGroupTitle,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    l10n.settingsSimulationSavedPicksLine(
                                      app.memberPicksByMemberId.length,
                                    ),
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
                                                  l10n.settingsGeneratedPicksForMembers(
                                                    others.length,
                                                  ),
                                                );
                                              }
                                            : null,
                                        child: Text(l10n.settingsGeneratePicks),
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
                                                  l10n.settingsCopiedMyPicksToMembers(
                                                    others.length,
                                                  ),
                                                );
                                              }
                                            : null,
                                        child: Text(l10n.settingsCopyMyPicks),
                                      ),
                                      FilledButton.tonal(
                                        onPressed: () {
                                          app.clearMemberPicks();
                                          snack(
                                            l10n.settingsSimulatedPicksCleared,
                                          );
                                        },
                                        child: Text(
                                          l10n.settingsClearSimulatedPicks,
                                        ),
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
                              snack(l10n.settingsFixturesCacheCleared);
                            },
                            child: Text(l10n.settingsClearFixtures),
                          ),
                          FilledButton.tonal(
                            onPressed: () {
                              app.clearCachedPredictionOutcomes();
                              snack(l10n.settingsOutcomesCacheCleared);
                            },
                            child: Text(l10n.settingsClearOutcomes),
                          ),
                          FilledButton(
                            onPressed: () {
                              app.clearAllPredictionCache();
                              snack(l10n.settingsPredictionCacheCleared);
                            },
                            child: Text(l10n.settingsClearAll),
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
            l10n.settingsProfile,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _teamNameCtrl,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.settingsTeamNameLabel,
              hintText: l10n.settingsTeamNameHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _favoriteTeamCtrl,
            decoration: InputDecoration(
              labelText: l10n.settingsFavoriteTeamLabel,
              hintText: l10n.settingsFavoriteTeamHint,
            ),
          ),

          if (app.hasGroup) ...[
            const SizedBox(height: 24),
            Text(
              l10n.settingsGroup,
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
                    title: Text(l10n.settingsGroupImageTitle),
                    subtitle: Text(l10n.settingsGroupImageSubtitle),
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
                    title: Text(l10n.settingsAdminApprovalTitle),
                    subtitle: Text(l10n.settingsAdminApprovalSubtitle),
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
          Text(
            l10n.settingsAccount,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _buildAccountSection(app),
          const SizedBox(height: 24),
          Text(
            l10n.settingsLanguage,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<CassandraLanguage>(
            segments: <ButtonSegment<CassandraLanguage>>[
              ButtonSegment(
                value: CassandraLanguage.system,
                label: Text(l10n.settingsLanguageSystem),
              ),
              ButtonSegment(
                value: CassandraLanguage.it,
                label: Text(l10n.settingsLanguageIt),
              ),
              ButtonSegment(
                value: CassandraLanguage.en,
                label: Text(l10n.settingsLanguageEn),
              ),
            ],
            selected: <CassandraLanguage>{_language},
            onSelectionChanged: (value) {
              setState(() => _language = value.first);
            },
          ),
          const SizedBox(height: 8),
          Text(
            l10n.settingsTranslationNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),

          const SizedBox(height: 24),
          Text(
            l10n.settingsPicksPrivacyDefault,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<PredictionVisibility>(
            segments: <ButtonSegment<PredictionVisibility>>[
              ButtonSegment(
                value: PredictionVisibility.public,
                label: Text(l10n.settingsPrivacyPublic),
              ),
              ButtonSegment(
                value: PredictionVisibility.friends,
                label: Text(l10n.settingsPrivacyFriends),
              ),
              ButtonSegment(
                value: PredictionVisibility.private,
                label: Text(l10n.settingsPrivacyPrivate),
              ),
            ],
            selected: <PredictionVisibility>{_defaultVisibility},
            onSelectionChanged: (value) {
              setState(() => _defaultVisibility = value.first);
            },
          ),
          const SizedBox(height: 8),
          Text(
            l10n.settingsPrivacyNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),

          const SizedBox(height: 24),
          Text(
            l10n.settingsDiagnostics,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          // Fixtures cache (runtime)
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: Text(l10n.settingsFixturesCacheTitle),
                  subtitle: Text('$dataLabel$updatedLabel'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: Text(l10n.settingsRefreshCacheNowTitle),
                  subtitle: Text(l10n.settingsRefreshCacheNowSubtitle),
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
                  title: Text(l10n.settingsClearFixturesCacheTitle),
                  subtitle: Text(l10n.settingsClearFixturesCacheSubtitle),
                  onTap: () {
                    app.clearCachedPredictionMatches();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.settingsCacheCleared)),
                    );
                  },
                ),
              ],
            ),
          ),

          Card(
            child: ListTile(
              title: Text(l10n.settingsBackendDiagnosticsTitle),
              subtitle: Text(l10n.settingsBackendDiagnosticsSubtitle),
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
                  child: Text(l10n.settingsSave),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _reset(app),
                  child: Text(l10n.settingsReset),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
