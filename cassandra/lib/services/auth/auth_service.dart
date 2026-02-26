import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Result of a sign-in attempt.
sealed class AuthSignInResult {}

class AuthSignInSuccess extends AuthSignInResult {
  final UserCredential credential;
  AuthSignInSuccess(this.credential);
}

class AuthSignInCancelled extends AuthSignInResult {}

class AuthSignInAccountConflict extends AuthSignInResult {
  final String email;
  final AuthCredential pendingCredential;
  final String existingProvider;
  AuthSignInAccountConflict({
    required this.email,
    required this.pendingCredential,
    required this.existingProvider,
  });
}

class AuthService {
  final FirebaseAuth _auth;

  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  bool get isSignedIn => _auth.currentUser != null;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<AuthSignInResult> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return AuthSignInCancelled();

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    try {
      final result = await _auth.signInWithCredential(credential);
      return AuthSignInSuccess(result);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        return AuthSignInAccountConflict(
          email: e.email ?? googleUser.email,
          pendingCredential: credential,
          existingProvider: 'apple',
        );
      }
      rethrow;
    }
  }

  Future<AuthSignInResult> signInWithApple() async {
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email],
      nonce: nonce,
    );

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
      accessToken: appleCredential.authorizationCode,
    );

    try {
      final result = await _auth.signInWithCredential(oauthCredential);
      return AuthSignInSuccess(result);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        final email = e.email ?? appleCredential.email ?? '';
        return AuthSignInAccountConflict(
          email: email,
          pendingCredential: oauthCredential,
          existingProvider: 'google',
        );
      }
      rethrow;
    }
  }

  Future<UserCredential?> linkPendingCredential(
    AuthCredential pendingCredential,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return user.linkWithCredential(pendingCredential);
  }

  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }

  Future<void> deleteAccount() async {
    await _auth.currentUser?.delete();
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
