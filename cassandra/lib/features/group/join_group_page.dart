import 'package:flutter/material.dart';

import '../../app/state/app_settings.dart';
import '../../app/state/app_state.dart';
import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';

class JoinGroupPage extends StatefulWidget {
  final VoidCallback? onJoined;

  const JoinGroupPage({super.key, this.onJoined});

  @override
  State<JoinGroupPage> createState() => _JoinGroupPageState();
}

class _JoinGroupPageState extends State<JoinGroupPage> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  bool _isEnglish(AppState app) {
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  String _t(AppState app, String it, String en) => _isEnglish(app) ? en : it;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _onJoin() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final appState = CassandraScope.of(context);
    final en = _isEnglish(appState);
    final err = await appState.joinGroupByInviteCode(code);

    if (!mounted) return;

    if (err != null) {
      setState(() {
        _loading = false;
        _error = err == 'Invalid code'
            ? (en ? 'Invalid invite code' : 'Codice invito non valido')
            : err == 'Already a member'
            ? (en
                  ? 'Already a member of this group'
                  : 'Fai già parte di questo gruppo')
            : err;
      });
    } else {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(en ? 'Joined group!' : 'Entrato nel gruppo!')),
        );
        widget.onJoined?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);

    return Scaffold(
      backgroundColor: CassandraColors.bg,
      appBar: AppBar(
        title: Text(_t(app, 'Unisciti a un gruppo', 'Join a group')),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.group_add, size: 64, color: CassandraColors.primary),
                const SizedBox(height: 16),
                Text(
                  _t(
                    app,
                    'Inserisci il codice invito del gruppo',
                    'Enter the group invite code',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CassandraColors.slate,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 9, // CASS-XXXX
                  decoration: InputDecoration(
                    labelText: _t(app, 'Codice invito', 'Invite code'),
                    hintText: 'CASS-XXXX',
                    border: const OutlineInputBorder(),
                    errorText: _error,
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading || _codeController.text.trim().isEmpty
                        ? null
                        : _onJoin,
                    style: FilledButton.styleFrom(
                      backgroundColor: CassandraColors.primary,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_t(app, 'Unisciti', 'Join')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
