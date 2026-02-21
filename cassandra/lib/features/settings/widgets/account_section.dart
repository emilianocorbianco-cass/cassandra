import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/features/auth/login_page.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AccountSection extends StatelessWidget {
  const AccountSection({super.key, required this.app});

  final AppState app;

  Future<void> _confirmSignOut(BuildContext context, AppState app) async {
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

    if (confirmed != true || !context.mounted) return;

    await app.signOut();
    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context, AppState app) async {
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

    if (confirmed != true || !context.mounted) return;

    try {
      await app.deleteAccount();
      if (!context.mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[delete-account] error: $e');
        debugPrint('$st');
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.settingsReauthError)));
    }
  }

  Widget _buildAccountSection(BuildContext context, AppState app) {
    final l10n = AppLocalizations.of(context)!;
    if (app.authService == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.settingsDevModeNoFirebase),
        ),
      );
    }

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
              onTap: () => _confirmSignOut(context, app),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: Text(
                l10n.settingsDeleteAccount,
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () => _confirmDeleteAccount(context, app),
            ),
          ],
        ),
      );
    }

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          l10n.settingsAccount,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _buildAccountSection(context, app),
      ],
    );
  }
}
