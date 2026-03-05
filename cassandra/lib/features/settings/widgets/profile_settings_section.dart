import 'package:cassandra/app/state/app_state.dart';
import 'package:cassandra/app/theme/cassandra_colors.dart';
import 'package:cassandra/features/profile/widgets/profile_image_picker.dart';
import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

String normalizeHandleDraft(String raw) {
  final compact = raw.trim().replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty || compact == '@') return '@';
  return compact.startsWith('@') ? compact : '@$compact';
}

class ProfileSettingsSection extends StatefulWidget {
  const ProfileSettingsSection({
    super.key,
    required this.app,
    required this.displayNameController,
    required this.teamNameController,
    required this.selectedFavoriteTeam,
    required this.onFavoriteTeamChanged,
  });

  final AppState app;
  final TextEditingController displayNameController;
  final TextEditingController teamNameController;
  final String? selectedFavoriteTeam;
  final ValueChanged<String?> onFavoriteTeamChanged;

  @override
  State<ProfileSettingsSection> createState() => _ProfileSettingsSectionState();
}

class _ProfileSettingsSectionState extends State<ProfileSettingsSection> {
  bool _favoriteTeamsLoading = false;
  bool _favoriteTeamsLoaded = false;
  List<_FavoriteTeamOption> _favoriteTeamOptions = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureFavoriteTeamsLoaded(widget.app);
  }

  @override
  void didUpdateWidget(covariant ProfileSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      _favoriteTeamsLoaded = false;
    }
    _ensureFavoriteTeamsLoaded(widget.app);
  }

  void _normalizeHandleController() {
    final normalized = normalizeHandleDraft(widget.teamNameController.text);
    if (widget.teamNameController.text == normalized) return;
    widget.teamNameController.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }

  void _ensureFavoriteTeamsLoaded(AppState app) {
    if (_favoriteTeamsLoaded || _favoriteTeamsLoading) return;
    _favoriteTeamsLoading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadFavoriteTeams(app);
    });
  }

  void _upsertFavoriteTeamOption(
    Map<String, _FavoriteTeamOption> out, {
    required String name,
    String? logoUrl,
  }) {
    final cleanedName = name.trim();
    if (cleanedName.isEmpty) return;
    final cleanedLogo = (logoUrl ?? '').trim();
    final key = cleanedName.toLowerCase();
    final prev = out[key];
    if (prev == null) {
      out[key] = _FavoriteTeamOption(
        name: cleanedName,
        logoUrl: cleanedLogo.isEmpty ? null : cleanedLogo,
      );
      return;
    }
    if ((prev.logoUrl == null || prev.logoUrl!.isEmpty) &&
        cleanedLogo.isNotEmpty) {
      out[key] = _FavoriteTeamOption(name: cleanedName, logoUrl: cleanedLogo);
    }
  }

  Future<void> _loadFavoriteTeams(AppState app) async {
    final optionsByKey = <String, _FavoriteTeamOption>{};

    final matches = app.cachedPredictionMatches;
    if (matches != null && matches.isNotEmpty) {
      for (final m in matches) {
        _upsertFavoriteTeamOption(
          optionsByKey,
          name: m.homeTeam,
          logoUrl: m.homeTeamLogo,
        );
        _upsertFavoriteTeamOption(
          optionsByKey,
          name: m.awayTeam,
          logoUrl: m.awayTeamLogo,
        );
      }
    }

    if (app.firestoreService != null && app.isAuthenticated) {
      try {
        final standings = await app.firestoreService!.getSeasonStandings(
          seasonKey: app.currentSeasonKey,
        );
        for (final s in standings) {
          _upsertFavoriteTeamOption(
            optionsByKey,
            name: s.teamName,
            logoUrl: s.teamLogo,
          );
        }
      } catch (_) {
        // Best effort.
      }
    }

    final options = optionsByKey.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final selected = (widget.selectedFavoriteTeam ?? '').trim();
    if (selected.isNotEmpty &&
        !options.any((o) => o.name.toLowerCase() == selected.toLowerCase())) {
      options.insert(0, _FavoriteTeamOption(name: selected, logoUrl: null));
    }

    if (!mounted) return;

    String? canonicalSelected;
    if (selected.isNotEmpty) {
      canonicalSelected = options
          .firstWhere(
            (o) => o.name.toLowerCase() == selected.toLowerCase(),
            orElse: () => _FavoriteTeamOption(name: selected, logoUrl: null),
          )
          .name;
    }

    setState(() {
      _favoriteTeamOptions = options;
      _favoriteTeamsLoading = false;
      _favoriteTeamsLoaded = true;
    });

    if (canonicalSelected != null &&
        canonicalSelected != widget.selectedFavoriteTeam) {
      widget.onFavoriteTeamChanged(canonicalSelected);
    }
  }

  Widget _favoriteTeamItem(_FavoriteTeamOption option) {
    final logo = option.logoUrl;
    return Row(
      children: [
        if (logo != null && logo.isNotEmpty)
          ClipOval(
            child: Image.network(
              logo,
              width: 18,
              height: 18,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 18,
                height: 18,
                child: Icon(Icons.shield_outlined, size: 16),
              ),
            ),
          )
        else
          const SizedBox(
            width: 18,
            height: 18,
            child: Icon(Icons.shield_outlined, size: 16),
          ),
        const SizedBox(width: 8),
        Expanded(child: Text(option.name, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Future<void> _pickProfileImage(AppState app) async {
    final path = await ProfileImageHelper.pickAndSaveProfileImage(context);
    if (path == null) return;
    await app.updateProfilePhotoPath(path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final app = widget.app;

    final selectedValue =
        _favoriteTeamOptions.any((o) => o.name == widget.selectedFavoriteTeam)
        ? widget.selectedFavoriteTeam
        : null;

    return Card(
      color: CassandraColors.platinum,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
        children: [
          GestureDetector(
            onTap: () => _pickProfileImage(app),
            child: Row(
              children: [
                ProfileImageDisplay(
                  imagePathOrUrl: app.profile.photoUrl,
                  radius: 30,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    l10n.settingsProfileImageLabel,
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
          const SizedBox(height: 12),
          TextField(
                controller: widget.displayNameController,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: CassandraColors.inkBlack, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  labelText: l10n.settingsDisplayNameLabel,
                  labelStyle: const TextStyle(color: CassandraColors.inkBlack),
                  hintText: l10n.settingsDisplayNameHint,
                  hintStyle: TextStyle(
                    color: CassandraColors.inkBlack.withValues(alpha: 0.5),
                  ),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: CassandraColors.inkBlack),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: CassandraColors.inkBlack, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.teamNameController,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _normalizeHandleController(),
                style: const TextStyle(color: CassandraColors.inkBlack, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  labelText: l10n.settingsHandleLabel,
                  labelStyle: const TextStyle(color: CassandraColors.inkBlack),
                  hintText: l10n.settingsHandleHint,
                  hintStyle: TextStyle(
                    color: CassandraColors.inkBlack.withValues(alpha: 0.5),
                  ),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: CassandraColors.inkBlack),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: CassandraColors.inkBlack, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'fav-team-${selectedValue ?? 'none'}-${_favoriteTeamOptions.length}',
                ),
                isExpanded: true,
                initialValue: selectedValue,
                style: const TextStyle(color: CassandraColors.inkBlack, fontWeight: FontWeight.w700),
                items: _favoriteTeamOptions
                    .map(
                      (o) => DropdownMenuItem<String>(
                        value: o.name,
                        child: _favoriteTeamItem(o),
                      ),
                    )
                    .toList(),
                onChanged: _favoriteTeamOptions.isEmpty
                    ? null
                    : widget.onFavoriteTeamChanged,
                decoration: InputDecoration(
                  labelText: l10n.settingsFavoriteTeamLabel,
                  labelStyle: const TextStyle(color: CassandraColors.inkBlack),
                  hintText: _favoriteTeamsLoading
                      ? l10n.groupDataRefreshing
                      : l10n.settingsFavoriteTeamHint,
                  hintStyle: TextStyle(
                    color: CassandraColors.inkBlack.withValues(alpha: 0.5),
                  ),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: CassandraColors.inkBlack),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: CassandraColors.inkBlack, width: 2),
                  ),
                  suffixIcon:
                      (widget.selectedFavoriteTeam != null &&
                          widget.selectedFavoriteTeam!.isNotEmpty)
                      ? IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: CassandraColors.inkBlack,
                          ),
                          onPressed: () => widget.onFavoriteTeamChanged(null),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      );
  }
}

class _FavoriteTeamOption {
  const _FavoriteTeamOption({required this.name, this.logoUrl});

  final String name;
  final String? logoUrl;
}
