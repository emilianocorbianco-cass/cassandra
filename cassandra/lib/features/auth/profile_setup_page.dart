import 'package:flutter/material.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../../l10n/app_localizations.dart';
import '../group/group_hub_page.dart';
import '../profile/widgets/profile_image_picker.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _displayNameCtrl = TextEditingController();
  final _handleCtrl = TextEditingController();
  bool _rememberMe = true;
  bool _saving = false;
  bool _initialized = false;
  String? _photoPath;

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _handleCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final app = CassandraScope.of(context);
    _displayNameCtrl.text = app.profile.displayName;
    _handleCtrl.text = _normalizeHandleDraft(app.profile.teamName);
    _photoPath = app.profile.photoUrl;
    _rememberMe = app.rememberMeEnabled || app.rememberedUid == null;
  }

  String _normalizeHandleDraft(String raw) {
    final compact = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty || compact == '@') return '@';
    return compact.startsWith('@') ? compact : '@$compact';
  }

  bool get _canContinue {
    final nameOk = _displayNameCtrl.text.trim().isNotEmpty;
    final handleBody = _handleCtrl.text.trim().replaceFirst('@', '');
    return !_saving && nameOk && handleBody.isNotEmpty;
  }

  void _normalizeHandleController() {
    final normalized = _normalizeHandleDraft(_handleCtrl.text);
    if (_handleCtrl.text == normalized) return;
    _handleCtrl.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  Future<void> _pickProfileImage() async {
    final path = await ProfileImageHelper.pickAndSaveProfileImage(context);
    if (path == null || !mounted) return;
    setState(() => _photoPath = path);
  }

  Future<void> _continue() async {
    if (!_canContinue) return;
    final app = CassandraScope.of(context);
    setState(() => _saving = true);
    try {
      await app.updateDisplayName(_displayNameCtrl.text);
      await app.updateTeamName(_handleCtrl.text);
      await app.updateProfilePhotoPath(_photoPath);
      await app.completeProfileSetup(rememberMe: _rememberMe);
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const GroupHubPage()),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.profileSetupTitle,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l10n.profileSetupSubtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: CassandraColors.slate),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: ProfileImageDisplay(
                  imagePathOrUrl: _photoPath,
                  radius: 20,
                ),
                title: Text(l10n.settingsProfileImageLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickProfileImage,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _displayNameCtrl,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.settingsDisplayNameLabel,
                hintText: l10n.settingsDisplayNameHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _handleCtrl,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                _normalizeHandleController();
                setState(() {});
              },
              onSubmitted: (_) => _continue(),
              decoration: InputDecoration(
                labelText: l10n.settingsHandleLabel,
                hintText: l10n.settingsHandleHint,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _rememberMe,
              onChanged: (v) => setState(() => _rememberMe = v ?? false),
              title: Text(l10n.profileSetupRememberMe),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _canContinue ? _continue : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.profileSetupContinue),
            ),
          ],
        ),
      ),
    );
  }
}
