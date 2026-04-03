import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/app/theme/cassandra_colors.dart';
import 'package:cassandra/features/group/group_hub_page.dart';
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

  Future<void> _pickGroupImage(AppState app) async {
    final path = await GroupImageHelper.pickAndSaveGroupImage(context);
    if (path == null || !mounted) return;
    await app.updateGroupImagePath(path);
  }

  Future<void> _confirmDeleteGroup(AppState app) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CassandraColors.inkBlack,
        title: Text(
          l10n.settingsDeleteGroup,
          style: const TextStyle(color: CassandraColors.brightSnow),
        ),
        content: Text(
          l10n.settingsDeleteGroupQuestion,
          style: const TextStyle(color: CassandraColors.brightSnow),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              l10n.settingsCancel,
              style: const TextStyle(color: CassandraColors.brightSnow),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: CassandraColors.primary,
            ),
            child: Text(l10n.settingsDelete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final error = await app.deleteActiveGroupIfAdmin();
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    Navigator.of(context, rootNavigator: true).pushReplacement(
      MaterialPageRoute(builder: (_) => const GroupHubPage()),
    );
  }

  Widget _buildCard(AppState app, AppLocalizations l10n, bool isAdmin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              if (isAdmin) ...[
                GestureDetector(
                  onTap: () => _pickGroupImage(app),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      children: [
                        GroupImageDisplay(
                          imagePath: app.groupImagePath,
                          radius: 30,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            l10n.settingsGroupImageTitle,
                            style: const TextStyle(
                              color: CassandraColors.inkBlack,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: CassandraColors.inkBlack,
                        ),
                      ],
                    ),
                  ),
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
              ],
              if (app.firestoreGroupIds.length >= 2) ...[
                if (isAdmin) const Divider(height: 1),
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
              if (isAdmin) ...[
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

    // Offline fallback: show card assuming admin.
    if (app.firestoreService == null) {
      return _buildCard(app, l10n, true);
    }

    if (_activeGroupDocFuture == null) {
      // No future yet — still show non-admin items (e.g. cambia gruppo).
      if (app.firestoreGroupIds.length >= 2) {
        return _buildCard(app, l10n, false);
      }
      return const SizedBox.shrink();
    }

    return FutureBuilder<GroupDocument?>(
      future: _activeGroupDocFuture,
      builder: (context, snapshot) {
        final doc = snapshot.data;
        final isAdmin = doc != null && doc.adminUid == app.profile.id;
        // Always show if admin or if there's a "Cambia gruppo" option.
        if (!isAdmin && app.firestoreGroupIds.length < 2) {
          return const SizedBox.shrink();
        }
        return _buildCard(app, l10n, isAdmin);
      },
    );
  }
}
