import 'package:firebase_auth/firebase_auth.dart';

class UserProfile {
  /// Maximum length for [displayName] (after trim).
  static const int kMaxDisplayNameLength = 40;

  /// Maximum length for the handle body (without the '@' prefix).
  static const int kMaxHandleBodyLength = 24;

  /// Maximum length for [favoriteTeam] (after trim).
  static const int kMaxFavoriteTeamLength = 40;

  /// Trims [raw] and clamps it to [kMaxDisplayNameLength].
  /// Returns an empty string when [raw] is blank after trimming.
  static String sanitizeDisplayName(String raw) {
    final t = raw.trim();
    return t.length > kMaxDisplayNameLength
        ? t.substring(0, kMaxDisplayNameLength)
        : t;
  }

  /// Normalises a team handle: strips whitespace, prepends '@', clamps the
  /// body to [kMaxHandleBodyLength]. Returns [fallback] when blank after
  /// normalization.
  static String normalizeHandle(String raw, {String fallback = '@cassandra'}) {
    final compact = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty || compact == '@') return fallback;
    final body = compact.startsWith('@') ? compact.substring(1) : compact;
    if (body.isEmpty) return fallback;
    final limited = body.length > kMaxHandleBodyLength
        ? body.substring(0, kMaxHandleBodyLength)
        : body;
    return '@$limited';
  }

  /// Trims [raw] and clamps it to [kMaxFavoriteTeamLength].
  /// Returns null when [raw] is null or blank after trimming.
  static String? sanitizeFavoriteTeam(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;
    return t.length > kMaxFavoriteTeamLength
        ? t.substring(0, kMaxFavoriteTeamLength)
        : t;
  }

  final String id;
  final String displayName;

  /// Nome squadra/handle
  final String teamName;

  /// Squadra del cuore (opzionale)
  final String? favoriteTeam;

  /// Email (opzionale, da Firebase)
  final String? email;

  /// URL foto profilo (opzionale, da Firebase)
  final String? photoUrl;

  const UserProfile({
    required this.id,
    required this.displayName,
    required this.teamName,
    this.favoriteTeam,
    this.email,
    this.photoUrl,
  });

  UserProfile copyWith({
    String? id,
    String? displayName,
    String? teamName,
    String? favoriteTeam,
    bool clearFavoriteTeam = false,
    String? email,
    bool clearEmail = false,
    String? photoUrl,
    bool clearPhotoUrl = false,
  }) {
    return UserProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      teamName: teamName ?? this.teamName,
      favoriteTeam: clearFavoriteTeam
          ? null
          : (favoriteTeam ?? this.favoriteTeam),
      email: clearEmail ? null : (email ?? this.email),
      photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
    );
  }

  factory UserProfile.fromFirebaseUser(
    User user, {
    String? existingTeamName,
    String? existingFavoriteTeam,
    String? existingPhotoUrl,
  }) {
    final rawName =
        user.displayName ?? user.email?.split('@').first ?? 'Giocatore';
    final name = sanitizeDisplayName(rawName);
    final defaultHandle =
        '@${name.trim().replaceAll(RegExp(r"\s+"), "").toLowerCase()}';
    return UserProfile(
      id: user.uid,
      displayName: name,
      teamName: normalizeHandle(
        existingTeamName ?? defaultHandle,
        fallback: '@cassandra',
      ),
      favoriteTeam: sanitizeFavoriteTeam(existingFavoriteTeam),
      email: user.email,
      // Prefer a custom-uploaded photo (storage:// or data:image/) over the
      // social-provider avatar (user.photoURL) so the user's chosen image
      // survives re-authentication.
      photoUrl: (existingPhotoUrl != null && existingPhotoUrl.isNotEmpty)
          ? existingPhotoUrl
          : user.photoURL,
    );
  }
}
