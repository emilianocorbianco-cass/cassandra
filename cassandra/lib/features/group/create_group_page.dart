import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import 'join_group_page.dart';
import 'widgets/group_image_picker.dart';

class CreateGroupPage extends StatefulWidget {
  final VoidCallback? onGroupCreated;

  const CreateGroupPage({super.key, this.onGroupCreated});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _nameController = TextEditingController();
  bool _created = false;
  String? _pickedImagePath;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final path = await GroupImageHelper.pickAndSaveGroupImage();
    if (path != null) {
      setState(() => _pickedImagePath = path);
    }
  }

  Future<void> _onCreate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final appState = CassandraScope.of(context);
    await appState.createGroup(name);

    if (_pickedImagePath != null) {
      await appState.updateGroupImagePath(_pickedImagePath);
    }

    setState(() => _created = true);
  }

  void _onShare() {
    final appState = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final name = appState.groupName ?? '';
    final code = appState.groupInviteCode ?? '';
    final text = l10n.groupShareInviteMessage(name, code);

    SharePlus.instance.share(ShareParams(text: text));
  }

  void _onContinue() {
    widget.onGroupCreated?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_created) {
      return _buildInviteView(context);
    }
    return _buildFormView(context);
  }

  Widget _buildFormView(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: CassandraColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.createGroupTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: CassandraColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.createGroupSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CassandraColors.slate,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _pickImage,
                  child: Column(
                    children: [
                      GroupImageDisplay(
                        imagePath: _pickedImagePath,
                        radius: 40,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.createGroupTapAddPhoto,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: CassandraColors.slate,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameController,
                  maxLength: 30,
                  decoration: InputDecoration(
                    labelText: l10n.createGroupNameLabel,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _nameController.text.trim().isEmpty
                        ? null
                        : _onCreate,
                    style: FilledButton.styleFrom(
                      backgroundColor: CassandraColors.primary,
                    ),
                    child: Text(l10n.createGroupButton),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (_) => JoinGroupPage(
                            onJoined: () {
                              Navigator.of(context, rootNavigator: true).pop();
                              widget.onGroupCreated?.call();
                            },
                          ),
                        ),
                      );
                    },
                    child: Text(l10n.createGroupHaveInviteCode),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInviteView(BuildContext context) {
    final appState = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final groupName = appState.groupName ?? '';
    final inviteCode = appState.groupInviteCode ?? '';

    return Scaffold(
      backgroundColor: CassandraColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pickedImagePath != null)
                  GroupImageDisplay(imagePath: _pickedImagePath, radius: 40)
                else
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: CassandraColors.primary,
                  ),
                const SizedBox(height: 16),
                Text(
                  l10n.createGroupCreated,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: CassandraColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          groupName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.createGroupInviteCode,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: CassandraColors.slate),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: inviteCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.createGroupCodeCopied),
                              ),
                            );
                          },
                          child: Text(
                            inviteCode,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                  color: CassandraColors.primary,
                                ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.createGroupTapToCopy,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: CassandraColors.slate,
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _onShare,
                    icon: const Icon(Icons.share),
                    label: Text(l10n.createGroupShareInviteCode),
                    style: FilledButton.styleFrom(
                      backgroundColor: CassandraColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _onContinue,
                    child: Text(l10n.createGroupContinue),
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
