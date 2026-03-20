import 'package:flutter/foundation.dart';
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
    String? err;
    try {
      err = await appState.joinGroupByInviteCode(code);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[join-group] unexpected error: $e');
        debugPrint('$st');
      }
      err = 'Permission denied';
    }

    if (!mounted) return;

    if (err != null && err != 'Pending approval') {
      setState(() {
        _loading = false;
        _error = err == 'Invalid code'
            ? l10n.joinGroupInvalidCode
            : err == 'Already a member'
            ? l10n.joinGroupAlreadyMember
            : err == 'Group full'
            ? l10n.joinGroupFull
            : err == 'Group unavailable'
            ? l10n.joinGroupUnavailable
            : err == 'Not authenticated'
            ? l10n.groupSignInRequired
            : err == 'Backend unavailable'
            ? l10n.settingsBackendNotConfigured
            : err == 'Permission denied'
            ? l10n.backendPermissionDenied
            : err;
      });
    } else if (err == 'Pending approval') {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.joinGroupPendingApproval)),
        );
        Navigator.of(context).pop();
      }
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
      body: SafeArea(
        child: Column(
          children: [
            // ── Back button ──
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.chevron_left,
                  color: CassandraColors.brightSnow,
                  size: 28,
                ),
              ),
            ),
            // ── Top third: title + subtitle ──
            Expanded(
              flex: 1,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.joinGroupTitle,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: CassandraColors.brightSnow,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.joinGroupEnterInviteCode,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: CassandraColors.slate,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            // ── Middle: icon + code field ──
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 50),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.group_add,
                          size: 84,
                          color: CassandraColors.primary,
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _codeController,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 9,
                          style: const TextStyle(color: CassandraColors.brightSnow),
                          decoration: InputDecoration(
                            labelText: l10n.joinGroupInviteCode,
                            labelStyle: const TextStyle(color: CassandraColors.brightSnow),
                            hintText: l10n.joinGroupCodeHint,
                            hintStyle: TextStyle(
                              color: CassandraColors.brightSnow.withValues(alpha: 0.5),
                            ),
                            counterStyle: const TextStyle(color: CassandraColors.brightSnow),
                            errorText: _error,
                            border: const OutlineInputBorder(
                              borderSide: BorderSide(color: CassandraColors.brightSnow),
                            ),
                            enabledBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: CassandraColors.brightSnow),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: CassandraColors.brightSnow, width: 2),
                            ),
                          ),
                          onChanged: (_) => setState(() => _error = null),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ── Bottom fifth: button ──
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Center(
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _loading || _codeController.text.trim().isEmpty
                          ? null
                          : _onJoin,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CassandraColors.brightSnow,
                        disabledForegroundColor: CassandraColors.brightSnow.withValues(alpha: 0.5),
                        side: const BorderSide(color: CassandraColors.brightSnow),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: CassandraColors.brightSnow,
                              ),
                            )
                          : Text(l10n.joinGroupButton),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
