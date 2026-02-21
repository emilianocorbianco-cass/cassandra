import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cassandra/app/state/group_state.dart';
import 'package:cassandra/app/config/storage_keys.dart';
import 'package:cassandra/app/state/user_profile.dart';

void main() {
  group('GroupState.inMemory', () {
    test('initial state has no group', () {
      final state = GroupState.inMemory();
      expect(state.hasGroup, isFalse);
      expect(state.groupName, isNull);
      expect(state.groupInviteCode, isNull);
      expect(state.groupImagePath, isNull);
      expect(state.groupAdminApproval, isFalse);
      expect(state.activeGroupId, isNull);
      expect(state.firestoreGroupIds, isEmpty);
    });
  });

  group('createGroup (no Firestore)', () {
    test('creates local group with invite code', () async {
      final state = GroupState.inMemory();
      final error = await state.createGroup(
        name: 'Test Group',
        uid: 'uid-1',
        isAuthenticated: false,
        profile: _dummyProfile(),
        avatarSeed: 42,
        firestoreService: null,
      );
      expect(error, isNull);
      expect(state.hasGroup, isTrue);
      expect(state.groupName, 'Test Group');
      expect(state.groupInviteCode, isNotNull);
      expect(state.groupInviteCode!, startsWith('CASS-'));
      expect(state.groupInviteCode!.length, 9);
    });

    test('rejects empty name', () async {
      final state = GroupState.inMemory();
      final error = await state.createGroup(
        name: '',
        uid: 'uid-1',
        isAuthenticated: false,
        profile: _dummyProfile(),
        avatarSeed: 42,
        firestoreService: null,
      );
      expect(error, 'Invalid name');
      expect(state.hasGroup, isFalse);
    });

    test('trims whitespace name', () async {
      final state = GroupState.inMemory();
      final error = await state.createGroup(
        name: '   ',
        uid: 'uid-1',
        isAuthenticated: false,
        profile: _dummyProfile(),
        avatarSeed: 42,
        firestoreService: null,
      );
      expect(error, 'Invalid name');
    });

    test('notifies listeners on success', () async {
      final state = GroupState.inMemory();
      var notified = 0;
      state.addListener(() => notified++);
      await state.createGroup(
        name: 'Group',
        uid: 'uid-1',
        isAuthenticated: false,
        profile: _dummyProfile(),
        avatarSeed: 42,
        firestoreService: null,
      );
      expect(notified, greaterThan(0));
    });
  });

  group('updateGroupName', () {
    test('updates name', () async {
      final state = GroupState.inMemory();
      await state.createGroup(
        name: 'Original',
        uid: 'uid-1',
        isAuthenticated: false,
        profile: _dummyProfile(),
        avatarSeed: 42,
        firestoreService: null,
      );
      await state.updateGroupName('Updated');
      expect(state.groupName, 'Updated');
    });

    test('ignores empty name', () async {
      final state = GroupState.inMemory();
      await state.createGroup(
        name: 'Original',
        uid: 'uid-1',
        isAuthenticated: false,
        profile: _dummyProfile(),
        avatarSeed: 42,
        firestoreService: null,
      );
      await state.updateGroupName('');
      expect(state.groupName, 'Original');
    });

    test('ignores same name', () async {
      final state = GroupState.inMemory();
      await state.createGroup(
        name: 'Same',
        uid: 'uid-1',
        isAuthenticated: false,
        profile: _dummyProfile(),
        avatarSeed: 42,
        firestoreService: null,
      );
      var notified = 0;
      state.addListener(() => notified++);
      await state.updateGroupName('Same');
      expect(notified, 0);
    });
  });

  group('updateGroupImagePath', () {
    test('sets and clears image path', () async {
      final state = GroupState.inMemory();
      await state.updateGroupImagePath('/path/to/image.png');
      expect(state.groupImagePath, '/path/to/image.png');
      await state.updateGroupImagePath(null);
      expect(state.groupImagePath, isNull);
    });
  });

  group('updateGroupAdminApproval', () {
    test('toggles approval', () async {
      final state = GroupState.inMemory();
      expect(state.groupAdminApproval, isFalse);
      await state.updateGroupAdminApproval(true);
      expect(state.groupAdminApproval, isTrue);
      await state.updateGroupAdminApproval(false);
      expect(state.groupAdminApproval, isFalse);
    });
  });

  group('Firestore group IDs', () {
    test('setFirestoreGroupIds sets first as active', () {
      final state = GroupState.inMemory();
      state.setFirestoreGroupIds(['g1', 'g2']);
      expect(state.firestoreGroupIds, ['g1', 'g2']);
      expect(state.activeGroupId, 'g1');
    });

    test('firestoreGroupIds is immutable for callers', () {
      final state = GroupState.inMemory();
      state.setFirestoreGroupIds(['g1', 'g2']);
      final ids = state.firestoreGroupIds;
      expect(() => ids.add('g3'), throwsUnsupportedError);
    });

    test('setActiveGroupId changes active', () {
      final state = GroupState.inMemory();
      state.setFirestoreGroupIds(['g1', 'g2']);
      state.setActiveGroupId('g2');
      expect(state.activeGroupId, 'g2');
    });

    test('empty group IDs result in null activeGroupId', () {
      final state = GroupState.inMemory();
      state.setFirestoreGroupIds([]);
      expect(state.activeGroupId, isNull);
    });

    test('setFirestoreGroupIds resets invalid activeGroupId', () {
      final state = GroupState.inMemory();
      state.setFirestoreGroupIds(['g1', 'g2']);
      state.setActiveGroupId('g2');
      state.setFirestoreGroupIds(['g3', 'g4']);
      // g2 not in new list, should reset to first
      expect(state.activeGroupId, 'g3');
    });
  });

  group('active group persistence', () {
    test(
      'fromPrefs restores activeGroupId and keeps it when present in ids',
      () async {
        SharedPreferences.setMockInitialValues({
          StorageKeys.groupActiveGroupIdV1: 'g2',
        });
        final prefs = await SharedPreferences.getInstance();
        final state = GroupState.fromPrefs(prefs);
        state.setFirestoreGroupIds(['g1', 'g2', 'g3']);
        expect(state.activeGroupId, 'g2');
      },
    );

    test('setActiveGroupId persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final state = GroupState.fromPrefs(prefs);
      state.setFirestoreGroupIds(['g1', 'g2']);
      state.setActiveGroupId('g2');

      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString(StorageKeys.groupActiveGroupIdV1), 'g2');
    });

    test('invalid restored activeGroupId is corrected and persisted', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.groupActiveGroupIdV1: 'old-group',
      });
      final prefs = await SharedPreferences.getInstance();
      final state = GroupState.fromPrefs(prefs);
      state.setFirestoreGroupIds(['g3', 'g4']);

      await Future<void>.delayed(Duration.zero);
      expect(state.activeGroupId, 'g3');
      expect(prefs.getString(StorageKeys.groupActiveGroupIdV1), 'g3');
    });
  });

  group('deleteActiveGroupIfAdmin (no Firestore)', () {
    test('clears local group', () async {
      final state = GroupState.inMemory();
      await state.createGroup(
        name: 'To Delete',
        uid: 'uid-1',
        isAuthenticated: false,
        profile: _dummyProfile(),
        avatarSeed: 42,
        firestoreService: null,
      );
      final error = await state.deleteActiveGroupIfAdmin(
        uid: 'uid-1',
        isAuthenticated: false,
        firestoreService: null,
      );
      expect(error, isNull);
      expect(state.hasGroup, isFalse);
      expect(state.groupName, isNull);
      expect(state.groupInviteCode, isNull);
    });

    test('returns error when no group', () async {
      final state = GroupState.inMemory();
      final error = await state.deleteActiveGroupIfAdmin(
        uid: 'uid-1',
        isAuthenticated: false,
        firestoreService: null,
      );
      expect(error, 'No group');
    });
  });

  group('clearAll', () {
    test('resets everything', () async {
      final state = GroupState.inMemory();
      await state.createGroup(
        name: 'Group',
        uid: 'uid-1',
        isAuthenticated: false,
        profile: _dummyProfile(),
        avatarSeed: 42,
        firestoreService: null,
      );
      await state.updateGroupImagePath('/some/path.png');
      await state.updateGroupAdminApproval(true);
      state.setFirestoreGroupIds(['g1']);

      await state.clearAll();

      expect(state.hasGroup, isFalse);
      expect(state.groupName, isNull);
      expect(state.groupInviteCode, isNull);
      expect(state.groupImagePath, isNull);
      expect(state.groupAdminApproval, isFalse);
      expect(state.firestoreGroupIds, isEmpty);
      expect(state.activeGroupId, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Member photo fallback: portable vs non-portable image references
  //
  // GroupState.fetchFirestoreGroupMembers uses isPortableImageRef to decide
  // whether a user-profile photo URL fetched as a fallback can be displayed
  // on any device (network/data URI) or must be discarded (local file path).
  // The tests below cover the predicate directly.
  // ---------------------------------------------------------------------------

  group('GroupState.isPortableImageRef – portable references', () {
    test('https URL is portable', () {
      expect(
        GroupState.isPortableImageRef('https://example.com/avatar.jpg'),
        isTrue,
      );
    });

    test('http URL is portable', () {
      expect(
        GroupState.isPortableImageRef('http://cdn.example.com/photo.png'),
        isTrue,
      );
    });

    test('data:image/png URI is portable', () {
      expect(
        GroupState.isPortableImageRef(
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA',
        ),
        isTrue,
      );
    });

    test('data:image/jpeg URI is portable', () {
      expect(
        GroupState.isPortableImageRef('data:image/jpeg;base64,/9j/4AAQ'),
        isTrue,
      );
    });

    test('data:image/webp URI is portable', () {
      expect(
        GroupState.isPortableImageRef('data:image/webp;base64,UklGRg=='),
        isTrue,
      );
    });

    test('HTTPS scheme is checked case-insensitively', () {
      expect(
        GroupState.isPortableImageRef('HTTPS://example.com/photo.jpg'),
        isTrue,
      );
    });

    test('leading/trailing whitespace is stripped before the check', () {
      expect(
        GroupState.isPortableImageRef('  https://example.com/a.jpg  '),
        isTrue,
      );
    });
  });

  group('GroupState.isPortableImageRef – non-portable references', () {
    test('absolute local file path is not portable', () {
      expect(
        GroupState.isPortableImageRef(
          '/data/user/0/com.example.app/cache/photo.jpg',
        ),
        isFalse,
      );
    });

    test('relative file path is not portable', () {
      expect(GroupState.isPortableImageRef('images/avatar.png'), isFalse);
    });

    test('empty string is not portable', () {
      expect(GroupState.isPortableImageRef(''), isFalse);
    });

    test('whitespace-only string is not portable', () {
      expect(GroupState.isPortableImageRef('   '), isFalse);
    });

    test('bare file name without scheme is not portable', () {
      expect(GroupState.isPortableImageRef('photo.jpg'), isFalse);
    });

    test('data: URI for non-image type is not portable', () {
      // data:text/plain is not an image reference
      expect(
        GroupState.isPortableImageRef('data:text/plain;base64,SGVsbG8='),
        isFalse,
      );
    });

    test('Firebase Storage gs:// path is not portable', () {
      expect(
        GroupState.isPortableImageRef(
          'gs://my-project.appspot.com/avatars/uid.jpg',
        ),
        isFalse,
      );
    });
  });
}

UserProfile _dummyProfile() => const UserProfile(
  id: 'uid-1',
  displayName: 'Test User',
  teamName: '@testuser',
);
