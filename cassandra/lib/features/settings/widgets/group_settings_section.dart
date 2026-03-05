import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/features/group/group_hub_page.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:cassandra/services/firestore/models/group_document.dart';
import 'package:flutter/material.dart';

class GroupSettingsSection extends StatefulWidget {
  const GroupSettingsSection({super.key, required this.app});

  final AppState app;

  @override
  State<GroupSettingsSection> createState() => _GroupSettingsSectionState();
}

class _GroupSettingsSectionState extends State<GroupSettingsSection> {
  Future<GroupDocument?>? _activeGroupDocFuture;
  String? _activeGroupDocFutureGroupId;

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

  Widget _buildAdminCard(AppState app, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: Text(l10n.settingsAdminApprovalTitle),
                subtitle: Text(l10n.settingsAdminApprovalSubtitle),
                value: app.groupAdminApproval,
                onChanged: (value) {
                  app.updateGroupAdminApproval(value);
                },
              ),
              if (app.firestoreGroupIds.length >= 2) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(l10n.settingsSwitchGroup),
                  onTap: () {
                    Navigator.of(context, rootNavigator: true).pushReplacement(
                      MaterialPageRoute(builder: (_) => const GroupHubPage()),
                    );
                  },
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: Text(
                  l10n.settingsDeleteGroup,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () => _confirmDeleteGroup(app),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final l10n = AppLocalizations.of(context)!;

    if (!app.hasGroup) {
      return const SizedBox.shrink();
    }

    _syncActiveGroupDocFuture(app);

    // Offline fallback: show card unconditionally.
    if (app.firestoreService == null) {
      return _buildAdminCard(app, l10n);
    }

    // Online: only show for admin.
    if (_activeGroupDocFuture == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<GroupDocument?>(
      future: _activeGroupDocFuture,
      builder: (context, snapshot) {
        final doc = snapshot.data;
        final isAdmin = doc != null && doc.adminUid == app.profile.id;
        if (!isAdmin) {
          return const SizedBox.shrink();
        }
        return _buildAdminCard(app, l10n);
      },
    );
  }
}
