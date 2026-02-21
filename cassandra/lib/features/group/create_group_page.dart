import 'package:flutter/foundation.dart';
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
  bool _creating = false;
  String? _error;
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

    setState(() {
      _creating = true;
      _error = null;
    });

    final appState = CassandraScope.of(context);
    final err = await appState.createGroup(name);

    if (!mounted) return;
    if (err != null) {
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _creating = false;
        _error = err == 'Not authenticated'
            ? l10n.groupSignInRequired
            : err == 'Backend unavailable'
            ? l10n.settingsBackendNotConfigured
            : err == 'Permission denied'
            ? l10n.backendPermissionDenied
            : l10n.createGroupError;
      });
      return;
    }

    if (_pickedImagePath != null) {
      await appState.updateGroupImagePath(_pickedImagePath);
    }

    setState(() {
      _creating = false;
      _created = true;
    });
  }

  Rect? _shareOriginFromContext(BuildContext sourceContext) {
    final renderObject = sourceContext.findRenderObject();
    if (renderObject is! RenderBox) return null;
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }

  Future<void> _onShare(BuildContext sourceContext) async {
    final appState = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;
    final name = appState.groupName ?? '';
    final code = appState.groupInviteCode ?? '';
    if (code.trim().isEmpty) return;
    final text = l10n.groupShareInviteMessage(name, code);
    final messenger = ScaffoldMessenger.of(context);
    final shareOrigin = _shareOriginFromContext(sourceContext);
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: shareOrigin),
      );
      if (!mounted) return;
      if (result.status == ShareResultStatus.unavailable) {
        await Clipboard.setData(ClipboardData(text: code));
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.groupShareUnavailableCodeCopied)),
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[create-group] share error: $e');
        debugPrint('$st');
      }
      await Clipboard.setData(ClipboardData(text: code));
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.groupShareUnavailableCodeCopied)),
      );
    }
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
                    onPressed: _creating || _nameController.text.trim().isEmpty
                        ? null
                        : _onCreate,
                    style: FilledButton.styleFrom(
                      backgroundColor: CassandraColors.primary,
                    ),
                    child: _creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(l10n.createGroupButton),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
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
                  child: Builder(
                    builder: (buttonContext) => FilledButton.icon(
                      onPressed: () => _onShare(buttonContext),
                      icon: const Icon(Icons.share),
                      label: Text(l10n.createGroupShareInviteCode),
                      style: FilledButton.styleFrom(
                        backgroundColor: CassandraColors.primary,
                      ),
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
