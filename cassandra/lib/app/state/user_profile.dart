import 'package:firebase_auth/firebase_auth.dart';

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
  }) {
    final name =
        user.displayName ?? user.email?.split('@').first ?? 'Giocatore';
    return UserProfile(
      id: user.uid,
      displayName: name,
      teamName: existingTeamName ?? 'FC $name',
      favoriteTeam: existingFavoriteTeam,
      email: user.email,
      photoUrl: user.photoURL,
    );
  }
}
