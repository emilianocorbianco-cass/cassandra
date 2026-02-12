import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/state/app_settings.dart';
import '../../app/state/app_state.dart';
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

  bool _isEnglish(AppState app) {
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  String _t(AppState app, String it, String en) => _isEnglish(app) ? en : it;

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
    final name = appState.groupName ?? '';
    final code = appState.groupInviteCode ?? '';

    final text = _isEnglish(appState)
        ? 'Join my group "$name" on Cassandra! Code: $code'
        : 'Unisciti al mio gruppo «$name» su Cassandra! Codice: $code';

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
    final app = CassandraScope.of(context);

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
                  _t(app, 'Crea il tuo gruppo', 'Create your group'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: CassandraColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _t(
                    app,
                    'Sfida i tuoi amici sui pronostici di Serie A',
                    'Challenge your friends on Serie A predictions',
                  ),
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
                        _t(
                          app,
                          'Tocca per aggiungere foto',
                          'Tap to add photo',
                        ),
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
                    labelText: _t(app, 'Nome del gruppo', 'Group name'),
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
                    child: Text(_t(app, 'Crea gruppo', 'Create group')),
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
                    child: Text(
                      _t(app, 'Hai un codice invito?', 'Have an invite code?'),
                    ),
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
                  _t(appState, 'Gruppo creato!', 'Group created!'),
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
                          _t(appState, 'Codice invito', 'Invite code'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: CassandraColors.slate),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: inviteCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _t(
                                    appState,
                                    'Codice copiato!',
                                    'Code copied!',
                                  ),
                                ),
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
                          _t(appState, 'Tocca per copiare', 'Tap to copy'),
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
                    label: Text(
                      _t(
                        appState,
                        'Condividi codice invito',
                        'Share invite code',
                      ),
                    ),
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
                    child: Text(_t(appState, 'Continua', 'Continue')),
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
