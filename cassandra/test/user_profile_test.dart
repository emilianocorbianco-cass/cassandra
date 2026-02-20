import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/app/state/user_profile.dart';

void main() {
  const base = UserProfile(
    id: 'uid-1',
    displayName: 'Test User',
    teamName: '@testuser',
    favoriteTeam: 'Inter',
    email: 'test@example.com',
    photoUrl: 'https://example.com/photo.png',
  );

  // ==========================================================================
  // copyWith
  // ==========================================================================
  group('UserProfile.copyWith', () {
    test('returns identical profile when no overrides', () {
      final copy = base.copyWith();
      expect(copy.id, base.id);
      expect(copy.displayName, base.displayName);
      expect(copy.teamName, base.teamName);
      expect(copy.favoriteTeam, base.favoriteTeam);
      expect(copy.email, base.email);
      expect(copy.photoUrl, base.photoUrl);
    });

    test('overrides id', () {
      expect(base.copyWith(id: 'uid-2').id, 'uid-2');
    });

    test('overrides displayName', () {
      expect(base.copyWith(displayName: 'New Name').displayName, 'New Name');
    });

    test('overrides teamName', () {
      expect(base.copyWith(teamName: '@new').teamName, '@new');
    });

    test('overrides favoriteTeam', () {
      expect(base.copyWith(favoriteTeam: 'Milan').favoriteTeam, 'Milan');
    });

    test('clearFavoriteTeam sets to null', () {
      final copy = base.copyWith(clearFavoriteTeam: true);
      expect(copy.favoriteTeam, isNull);
    });

    test('clearFavoriteTeam takes priority over new value', () {
      final copy = base.copyWith(favoriteTeam: 'Juve', clearFavoriteTeam: true);
      // clearFavoriteTeam → null regardless of favoriteTeam param
      expect(copy.favoriteTeam, isNull);
    });

    test('clearEmail sets email to null', () {
      final copy = base.copyWith(clearEmail: true);
      expect(copy.email, isNull);
    });

    test('clearPhotoUrl sets photoUrl to null', () {
      final copy = base.copyWith(clearPhotoUrl: true);
      expect(copy.photoUrl, isNull);
    });

    test('preserves nullable fields when not cleared', () {
      final copy = base.copyWith(id: 'uid-2');
      expect(copy.favoriteTeam, 'Inter');
      expect(copy.email, 'test@example.com');
      expect(copy.photoUrl, 'https://example.com/photo.png');
    });

    test('copyWith on profile without optionals preserves nulls', () {
      const minimal = UserProfile(
        id: 'uid-1',
        displayName: 'Name',
        teamName: '@name',
      );
      final copy = minimal.copyWith(displayName: 'Updated');
      expect(copy.favoriteTeam, isNull);
      expect(copy.email, isNull);
      expect(copy.photoUrl, isNull);
    });
  });

  // ==========================================================================
  // Basic construction
  // ==========================================================================
  group('UserProfile construction', () {
    test('required fields are set', () {
      const p = UserProfile(id: 'a', displayName: 'b', teamName: 'c');
      expect(p.id, 'a');
      expect(p.displayName, 'b');
      expect(p.teamName, 'c');
      expect(p.favoriteTeam, isNull);
      expect(p.email, isNull);
      expect(p.photoUrl, isNull);
    });
  });
}
