import 'package:cassandra/app/state/app_settings.dart';
import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/app/state/cassandra_scope.dart';
import 'package:cassandra/core/tournament/tournament_modes.dart';
import 'package:cassandra/features/settings/widgets/account_section.dart';
import 'package:cassandra/features/settings/widgets/group_settings_section.dart';
import 'package:cassandra/features/settings/widgets/language_selector.dart';
import 'package:cassandra/features/settings/widgets/profile_settings_section.dart';
import 'package:flutter/material.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _displayNameCtrl = TextEditingController();
  final _teamNameCtrl = TextEditingController();

  bool _initialized = false;
  String? _selectedFavoriteTeam;
  CassandraLanguage _language = CassandraLanguage.system;
  AppState? _app;

  @override
  void dispose() {
    _displayNameCtrl.removeListener(_onDisplayNameChanged);
    _teamNameCtrl.removeListener(_onTeamNameChanged);
    _displayNameCtrl.dispose();
    _teamNameCtrl.dispose();
    super.dispose();
  }

  void _onDisplayNameChanged() {
    _app?.updateDisplayName(_displayNameCtrl.text);
  }

  void _onTeamNameChanged() {
    _app?.updateTeamName(_teamNameCtrl.text);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) return;

    final app = CassandraScope.of(context);
    _app = app;
    _displayNameCtrl.text = app.profile.displayName;
    _teamNameCtrl.text = normalizeHandleDraft(app.teamName);
    _selectedFavoriteTeam = app.favoriteTeam.trim().isEmpty
        ? null
        : app.favoriteTeam.trim();
    _language = app.language;

    _displayNameCtrl.addListener(_onDisplayNameChanged);
    _teamNameCtrl.addListener(_onTeamNameChanged);

    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = CassandraScope.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 90),
          children: [
            ProfileSettingsSection(
              app: app,
              displayNameController: _displayNameCtrl,
              teamNameController: _teamNameCtrl,
              selectedFavoriteTeam: _selectedFavoriteTeam,
              onFavoriteTeamChanged: (value) {
                setState(() => _selectedFavoriteTeam = value);
                _app?.updateFavoriteTeam(value ?? '');
              },
            ),
            GroupSettingsSection(app: app),
            AccountSection(app: app),
            LanguageSelector(
              currentValue: _language,
              onChanged: (value) {
                setState(() => _language = value);
                _app?.updateLanguage(value);
              },
            ),
            // ── Tournament switcher (testers only) ──
            if (app.isWorldCupTester) ...[
              const SizedBox(height: 24),
              Text(
                'Torneo',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue.shade800,
                        side: BorderSide(
                          color: app.activeTournament.id ==
                                  TournamentModes.serieA.id
                              ? Colors.blue.shade800
                              : Colors.grey.shade400,
                          width: app.activeTournament.id ==
                                  TournamentModes.serieA.id
                              ? 2
                              : 1,
                        ),
                      ),
                      onPressed: () => app.setActiveTournament(
                        TournamentModes.serieA,
                      ),
                      child: const Text('Serie A'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue.shade800,
                        side: BorderSide(
                          color: app.activeTournament.id ==
                                  TournamentModes.worldCup2026.id
                              ? Colors.blue.shade800
                              : Colors.grey.shade400,
                          width: app.activeTournament.id ==
                                  TournamentModes.worldCup2026.id
                              ? 2
                              : 1,
                        ),
                      ),
                      onPressed: () => app.setActiveTournament(
                        TournamentModes.worldCup2026,
                      ),
                      child: const Text('Mondiali 2026'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            // ── Debug ───────────────
            Text(
              'Debug',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.orange.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade800,
                      side: BorderSide(
                        color: app.debugLockOverride == false
                            ? Colors.orange.shade800
                            : Colors.grey.shade400,
                        width: app.debugLockOverride == false
                            ? 2
                            : 1,
                      ),
                    ),
                    onPressed: () =>
                        app.setDebugLockOverride(false),
                    child: const Text('Pre-lock'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade800,
                      side: BorderSide(
                        color: app.debugLockOverride == true
                            ? Colors.orange.shade800
                            : Colors.grey.shade400,
                        width: app.debugLockOverride == true
                            ? 2
                            : 1,
                      ),
                    ),
                    onPressed: () =>
                        app.setDebugLockOverride(true),
                    child: const Text('Post-lock'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade600,
                      side: BorderSide(
                        color: app.debugLockOverride == null
                            ? Colors.orange.shade800
                            : Colors.grey.shade400,
                        width: app.debugLockOverride == null
                            ? 2
                            : 1,
                      ),
                    ),
                    onPressed: () =>
                        app.setDebugLockOverride(null),
                    child: const Text('Natural'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
