import 'package:cassandra/app/state/app_settings.dart';
import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/app/state/cassandra_scope.dart';
import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import 'api_football_diagnostics_page.dart';
import 'package:cassandra/features/auth/login_page.dart';
import 'package:cassandra/features/group/widgets/group_image_picker.dart';
import 'package:cassandra/features/profile/widgets/profile_image_picker.dart';
import 'package:cassandra/features/stats/stats_page.dart';
import 'package:cassandra/services/firestore/models/group_document.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _displayNameCtrl = TextEditingController();
  final _teamNameCtrl = TextEditingController();

  bool _initialized = false;
  bool _favoriteTeamsLoading = false;
  bool _favoriteTeamsLoaded = false;
  List<_FavoriteTeamOption> _favoriteTeamOptions = const [];
  String? _selectedFavoriteTeam;
  int _settingsSegment = 0; // 0 = my settings, 1 = my stats

  CassandraLanguage _language = CassandraLanguage.system;
  Future<GroupDocument?>? _activeGroupDocFuture;
  String? _activeGroupDocFutureGroupId;

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _teamNameCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) return;

    final app = CassandraScope.of(context);
    _displayNameCtrl.text = app.profile.displayName;
    _teamNameCtrl.text = _normalizeHandleDraft(app.teamName);
    _selectedFavoriteTeam = app.favoriteTeam.trim().isEmpty
        ? null
        : app.favoriteTeam.trim();

    _language = app.language;

    _initialized = true;
    _ensureFavoriteTeamsLoaded(app);
  }

  String _normalizeHandleDraft(String raw) {
    final compact = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty || compact == '@') return '@';
    return compact.startsWith('@') ? compact : '@$compact';
  }

  void _normalizeHandleController() {
    final normalized = _normalizeHandleDraft(_teamNameCtrl.text);
    if (_teamNameCtrl.text == normalized) return;
    _teamNameCtrl.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  void _ensureFavoriteTeamsLoaded(AppState app) {
    if (_favoriteTeamsLoaded || _favoriteTeamsLoading) return;
    _favoriteTeamsLoading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadFavoriteTeams(app);
    });
  }

  void _upsertFavoriteTeamOption(
    Map<String, _FavoriteTeamOption> out, {
    required String name,
    String? logoUrl,
  }) {
    final cleanedName = name.trim();
    if (cleanedName.isEmpty) return;
    final cleanedLogo = (logoUrl ?? '').trim();
    final key = cleanedName.toLowerCase();
    final prev = out[key];
    if (prev == null) {
      out[key] = _FavoriteTeamOption(
        name: cleanedName,
        logoUrl: cleanedLogo.isEmpty ? null : cleanedLogo,
      );
      return;
    }
    if ((prev.logoUrl == null || prev.logoUrl!.isEmpty) &&
        cleanedLogo.isNotEmpty) {
      out[key] = _FavoriteTeamOption(name: cleanedName, logoUrl: cleanedLogo);
    }
  }

  Future<void> _loadFavoriteTeams(AppState app) async {
    final optionsByKey = <String, _FavoriteTeamOption>{};

    final matches = app.cachedPredictionMatches;
    if (matches != null && matches.isNotEmpty) {
      for (final m in matches) {
        _upsertFavoriteTeamOption(
          optionsByKey,
          name: m.homeTeam,
          logoUrl: m.homeTeamLogo,
        );
        _upsertFavoriteTeamOption(
          optionsByKey,
          name: m.awayTeam,
          logoUrl: m.awayTeamLogo,
        );
      }
    }

    if (app.firestoreService != null && app.isAuthenticated) {
      try {
        final standings = await app.firestoreService!.getSeasonStandings(
          seasonKey: app.currentSeasonKey,
        );
        for (final s in standings) {
          _upsertFavoriteTeamOption(
            optionsByKey,
            name: s.teamName,
            logoUrl: s.teamLogo,
          );
        }
      } catch (_) {
        // Best effort.
      }
    }

    final options = optionsByKey.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final selected = (_selectedFavoriteTeam ?? '').trim();
    if (selected.isNotEmpty &&
        !options.any((o) => o.name.toLowerCase() == selected.toLowerCase())) {
      options.insert(0, _FavoriteTeamOption(name: selected, logoUrl: null));
    }

    if (!mounted) return;
    setState(() {
      _favoriteTeamOptions = options;
      _favoriteTeamsLoading = false;
      _favoriteTeamsLoaded = true;
      if (selected.isNotEmpty) {
        _selectedFavoriteTeam = options
            .firstWhere(
              (o) => o.name.toLowerCase() == selected.toLowerCase(),
              orElse: () => _FavoriteTeamOption(name: selected, logoUrl: null),
            )
            .name;
      }
    });
  }

  Widget _favoriteTeamItem(_FavoriteTeamOption option) {
    final logo = option.logoUrl;
    return Row(
      children: [
        if (logo != null && logo.isNotEmpty)
          ClipOval(
            child: Image.network(
              logo,
              width: 18,
              height: 18,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 18,
                height: 18,
                child: Icon(Icons.shield_outlined, size: 16),
              ),
            ),
          )
        else
          const SizedBox(
            width: 18,
            height: 18,
            child: Icon(Icons.shield_outlined, size: 16),
          ),
        const SizedBox(width: 8),
        Expanded(child: Text(option.name, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Future<void> _save(AppState app) async {
    final l10n = AppLocalizations.of(context)!;
    await app.updateDisplayName(_displayNameCtrl.text);
    await app.updateTeamName(_teamNameCtrl.text);
    await app.updateFavoriteTeam(_selectedFavoriteTeam ?? '');
    await app.updateLanguage(_language);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.settingsSaved)));
  }

  Future<void> _reset(AppState app) async {
    final l10n = AppLocalizations.of(context)!;
    await app.resetAll();

    setState(() {
      _displayNameCtrl.text = app.profile.displayName;
      _teamNameCtrl.text = _normalizeHandleDraft(app.teamName);
      _selectedFavoriteTeam = app.favoriteTeam.trim().isEmpty
          ? null
          : app.favoriteTeam.trim();
      _language = app.language;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.settingsResetDone)));
  }

  Future<void> _pickProfileImage(AppState app) async {
    final path = await ProfileImageHelper.pickAndSaveProfileImage();
    if (path == null) return;
    await app.updateProfilePhotoPath(path);
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

  void _syncActiveGroupDocFuture(AppState app) {
    final groupId = app.activeGroupId;
    if (!app.hasGroup || groupId == null || app.firestoreService == null) {
      _activeGroupDocFuture = null;
      _activeGroupDocFutureGroupId = null;
      return;
    }
    if (_activeGroupDocFuture != null &&
        _activeGroupDocFutureGroupId == groupId) {
      return;
    }
    _activeGroupDocFutureGroupId = groupId;
    _activeGroupDocFuture = app.fetchActiveGroupDocument();
  }

  Future<void> _confirmDeleteGroup(AppState app) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsDeleteGroup),
        content: Text(l10n.settingsDeleteGroupQuestion),
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

    final err = await app.deleteActiveGroupIfAdmin();
    if (!mounted) return;

    if (err == null) {
      _activeGroupDocFuture = null;
      _activeGroupDocFutureGroupId = null;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.settingsDeleteGroupDone)));
      return;
    }

    final msg = err == 'Not admin'
        ? l10n.settingsDeleteGroupOnlyAdmin
        : err == 'Not authenticated'
        ? l10n.groupSignInRequired
        : l10n.settingsDeleteGroupFailed;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    _ensureFavoriteTeamsLoaded(app);
    _syncActiveGroupDocFuture(app);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.bug_report_outlined),
          tooltip: l10n.settingsBackendDiagnosticsTitle,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ApiFootballDiagnosticsPage(),
              ),
            );
          },
        ),
        title: Text(
          l10n.tabSettings,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: 0,
                        label: Text(
                          l10n.settingsSegmentMySettings,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text(
                          l10n.settingsSegmentMyStats,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                    selected: {_settingsSegment},
                    onSelectionChanged: (selected) {
                      setState(() => _settingsSegment = selected.first);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _settingsSegment == 1
                  ? const StatsPage(embedded: true, lockToPersonal: true)
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          l10n.settingsProfile,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: ListTile(
                            leading: ProfileImageDisplay(
                              imagePathOrUrl: app.profile.photoUrl,
                              radius: 20,
                            ),
                            title: Text(l10n.settingsProfileImageLabel),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _pickProfileImage(app),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _displayNameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: l10n.settingsDisplayNameLabel,
                            hintText: l10n.settingsDisplayNameHint,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _teamNameCtrl,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => _normalizeHandleController(),
                          decoration: InputDecoration(
                            labelText: l10n.settingsHandleLabel,
                            hintText: l10n.settingsHandleHint,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Builder(
                          builder: (_) {
                            final selectedValue =
                                _favoriteTeamOptions.any(
                                  (o) => o.name == _selectedFavoriteTeam,
                                )
                                ? _selectedFavoriteTeam
                                : null;

                            return DropdownButtonFormField<String>(
                              key: ValueKey(
                                'fav-team-${selectedValue ?? 'none'}-${_favoriteTeamOptions.length}',
                              ),
                              isExpanded: true,
                              initialValue: selectedValue,
                              items: _favoriteTeamOptions
                                  .map(
                                    (o) => DropdownMenuItem<String>(
                                      value: o.name,
                                      child: _favoriteTeamItem(o),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _favoriteTeamOptions.isEmpty
                                  ? null
                                  : (value) => setState(
                                      () => _selectedFavoriteTeam = value,
                                    ),
                              decoration: InputDecoration(
                                labelText: l10n.settingsFavoriteTeamLabel,
                                hintText: _favoriteTeamsLoading
                                    ? l10n.groupDataRefreshing
                                    : l10n.settingsFavoriteTeamHint,
                                suffixIcon:
                                    (_selectedFavoriteTeam != null &&
                                        _selectedFavoriteTeam!.isNotEmpty)
                                    ? IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          setState(
                                            () => _selectedFavoriteTeam = null,
                                          );
                                        },
                                      )
                                    : null,
                              ),
                            );
                          },
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
                                  subtitle: Text(
                                    l10n.settingsGroupImageSubtitle,
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
                                  title: Text(l10n.settingsAdminApprovalTitle),
                                  subtitle: Text(
                                    l10n.settingsAdminApprovalSubtitle,
                                  ),
                                  value: app.groupAdminApproval,
                                  onChanged: (value) {
                                    app.updateGroupAdminApproval(value);
                                  },
                                ),
                                if (app.firestoreService == null) ...[
                                  const Divider(height: 1),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.delete_forever,
                                      color: Colors.red,
                                    ),
                                    title: Text(
                                      l10n.settingsDeleteGroup,
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                    onTap: () => _confirmDeleteGroup(app),
                                  ),
                                ] else if (_activeGroupDocFuture != null)
                                  FutureBuilder<GroupDocument?>(
                                    future: _activeGroupDocFuture,
                                    builder: (context, snapshot) {
                                      final doc = snapshot.data;
                                      final isAdmin =
                                          doc != null &&
                                          doc.adminUid == app.profile.id;
                                      if (!isAdmin) {
                                        return const SizedBox.shrink();
                                      }
                                      return Column(
                                        children: [
                                          const Divider(height: 1),
                                          ListTile(
                                            leading: const Icon(
                                              Icons.delete_forever,
                                              color: Colors.red,
                                            ),
                                            title: Text(
                                              l10n.settingsDeleteGroup,
                                              style: const TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                            onTap: () =>
                                                _confirmDeleteGroup(app),
                                          ),
                                        ],
                                      );
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
                          showSelectedIcon: false,
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
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteTeamOption {
  const _FavoriteTeamOption({required this.name, this.logoUrl});

  final String name;
  final String? logoUrl;
}
