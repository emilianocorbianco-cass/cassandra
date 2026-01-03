import 'package:flutter/material.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();

  TextEditingController? _teamController;
  TextEditingController? _favoriteController;

  bool _initialized = false;
  bool _saving = false;

  static const _suggestedTeams = <String>[
    'Inter',
    'Milan',
    'Juventus',
    'Napoli',
    'Roma',
    'Lazio',
    'Atalanta',
    'Bologna',
    'Fiorentina',
    'Torino',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) return;
    _initialized = true;

    final appState = CassandraScope.of(context);
    _teamController = TextEditingController(text: appState.profile.teamName);
    _favoriteController = TextEditingController(text: appState.profile.favoriteTeam ?? '');
  }

  @override
  void dispose() {
    _teamController?.dispose();
    _favoriteController?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _saving = true);

    final appState = CassandraScope.of(context);

    await appState.updateTeamName(_teamController!.text);
    await appState.updateFavoriteTeam(_favoriteController!.text);

    if (!mounted) return;
    FocusScope.of(context).unfocus();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impostazioni salvate')),
    );

    setState(() => _saving = false);
  }

  Future<void> _reset() async {
    final appState = CassandraScope.of(context);

    await appState.resetProfileToDefault();
    if (!mounted) return;

    _teamController!.text = appState.profile.teamName;
    _favoriteController!.text = appState.profile.favoriteTeam ?? '';

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profilo ripristinato ai valori di default')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teamCtrl = _teamController!;
    final favCtrl = _favoriteController!;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Qui imposti il tuo profilo locale.\n\n'
                  '• Il nome squadra appare in Gruppo/Classifiche e nel profilo.\n'
                  '• La squadra del cuore influenza il badge 🦉 (se la dai vincente e perde).',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextFormField(
                        controller: teamCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nome squadra',
                          hintText: 'Es: FC Cassandra',
                        ),
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.isEmpty) return 'Inserisci un nome squadra';
                          if (s.length < 3) return 'Troppo corto (min 3)';
                          if (s.length > 24) return 'Troppo lungo (max 24)';
                          return null;
                        },
                      ),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: favCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Squadra del cuore (opzionale)',
                              hintText: 'Es: Milan',
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Suggerimenti:',
                            style: TextStyle(fontSize: 12, color: CassandraColors.slate),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _suggestedTeams.map((t) {
                              return ActionChip(
                                label: Text(t),
                                onPressed: () => favCtrl.text = t,
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : _reset,
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: CassandraColors.primary,
                            foregroundColor: CassandraColors.bg,
                          ),
                          child: Text(_saving ? 'Salvo…' : 'Salva'),
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
