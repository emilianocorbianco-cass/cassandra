import 'package:cassandra/app/state/app_settings.dart';
import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/app/state/cassandra_scope.dart';
import 'package:cassandra/features/settings/widgets/account_section.dart';
import 'package:cassandra/features/settings/widgets/group_settings_section.dart';
import 'package:cassandra/features/settings/widgets/language_selector.dart';
import 'package:cassandra/features/settings/widgets/profile_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import 'api_football_diagnostics_page.dart';
import 'package:cassandra/features/stats/stats_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _displayNameCtrl = TextEditingController();
  final _teamNameCtrl = TextEditingController();

  bool _initialized = false;
  String? _selectedFavoriteTeam;
  int _settingsSegment = 0; // 0 = my settings, 1 = my stats
  CassandraLanguage _language = CassandraLanguage.system;

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
    _teamNameCtrl.text = normalizeHandleDraft(app.teamName);
    _selectedFavoriteTeam = app.favoriteTeam.trim().isEmpty
        ? null
        : app.favoriteTeam.trim();
    _language = app.language;

    _initialized = true;
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
      _teamNameCtrl.text = normalizeHandleDraft(app.teamName);
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

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;

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
                        ProfileSettingsSection(
                          app: app,
                          displayNameController: _displayNameCtrl,
                          teamNameController: _teamNameCtrl,
                          selectedFavoriteTeam: _selectedFavoriteTeam,
                          onFavoriteTeamChanged: (value) {
                            setState(() => _selectedFavoriteTeam = value);
                          },
                        ),
                        GroupSettingsSection(app: app),
                        AccountSection(app: app),
                        LanguageSelector(
                          currentValue: _language,
                          onChanged: (value) {
                            setState(() => _language = value);
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
