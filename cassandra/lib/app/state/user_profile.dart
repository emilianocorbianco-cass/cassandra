import 'package:firebase_auth/firebase_auth.dart';

String _normalizeHandleValue(String raw, {String fallback = '@cassandra'}) {
  final compact = raw.trim().replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty || compact == '@') return fallback;
  final body = compact.startsWith('@') ? compact.substring(1) : compact;
  if (body.isEmpty) return fallback;
  return '@$body';
}

class UserProfile {
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
    final name =
        user.displayName ?? user.email?.split('@').first ?? 'Giocatore';
    final defaultHandle =
        '@${name.trim().replaceAll(RegExp(r"\s+"), "").toLowerCase()}';
    return UserProfile(
      id: user.uid,
      displayName: name,
      teamName: _normalizeHandleValue(
        existingTeamName ?? defaultHandle,
        fallback: '@cassandra',
      ),
      favoriteTeam: existingFavoriteTeam,
      email: user.email,
      photoUrl: user.photoURL ?? existingPhotoUrl,
    );
  }
}
