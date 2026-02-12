import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context)!;
    final err = await appState.joinGroupByInviteCode(code);

    if (!mounted) return;

    if (err != null) {
      setState(() {
        _loading = false;
        _error = err == 'Invalid code'
            ? l10n.joinGroupInvalidCode
            : err == 'Already a member'
            ? l10n.joinGroupAlreadyMember
            : err;
      });
    } else {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.joinGroupJoined)));
        widget.onJoined?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: CassandraColors.bg,
      appBar: AppBar(title: Text(l10n.joinGroupTitle)),
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
                  l10n.joinGroupEnterInviteCode,
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
                    labelText: l10n.joinGroupInviteCode,
                    hintText: l10n.joinGroupCodeHint,
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
                        : Text(l10n.joinGroupButton),
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
