import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/features/group/widgets/group_image_picker.dart';
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

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final l10n = AppLocalizations.of(context)!;

    if (!app.hasGroup) {
      return const SizedBox.shrink();
    }

    _syncActiveGroupDocFuture(app);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  final path = await GroupImageHelper.pickAndSaveGroupImage();
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
              if (app.firestoreService == null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
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
                        doc != null && doc.adminUid == app.profile.id;
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
                            style: const TextStyle(color: Colors.red),
                          ),
                          onTap: () => _confirmDeleteGroup(app),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
