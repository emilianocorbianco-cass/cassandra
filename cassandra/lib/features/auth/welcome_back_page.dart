import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth/auth_service.dart';
import '../../services/notifications/push_notifications_service.dart';
import '../group/group_hub_page.dart';
import 'profile_setup_page.dart';
import '../profile/widgets/profile_image_picker.dart';
import 'login_page.dart';

class WelcomeBackPage extends StatefulWidget {
  const WelcomeBackPage({super.key});

  @override
  State<WelcomeBackPage> createState() => _WelcomeBackPageState();
}

class _WelcomeBackPageState extends State<WelcomeBackPage> {
  static const _resultSuccess = 'success';
  static const _resultUnavailable = 'unavailable';
  static const _resultCancelled = 'cancelled';
  static const _resultMismatch = 'mismatch';

  final _auth = LocalAuthentication();
  bool _loading = false;
  String? _error;

  Future<void> _completeSignInFlow(String uid) async {
    final app = CassandraScope.of(context);
    await app.hydrateProfileFromFirestore(uid);
    await app.hydrateCurrentUserHistoryFromFirestore();
    await PushNotificationsService.instance.initializeForAppState(app);
    if (!mounted) return;

    Widget destination;
    if (app.needsProfileSetup) {
      destination = const ProfileSetupPage();
    } else {
      destination = const GroupHubPage();
    }
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
  }

  bool _isExpectedUid(String uid) {
    final expected = CassandraScope.of(context).rememberedUid?.trim() ?? '';
    if (expected.isEmpty) return true;
    return uid.trim() == expected;
  }

  Future<String> _signInWithRememberedProvider() async {
    final app = CassandraScope.of(context);
    final auth = app.authService;
    final provider = app.rememberedAuthProvider;
    if (auth == null || provider == null) return _resultUnavailable;

    AuthSignInResult result;
    if (provider == 'google') {
      result = await auth.signInWithGoogle();
    } else if (provider == 'apple') {
      result = await auth.signInWithApple();
    } else {
      return _resultUnavailable;
    }

    switch (result) {
      case AuthSignInCancelled():
        return _resultCancelled;
      case AuthSignInAccountConflict():
        // Conflict is unexpected on welcome-back (user previously signed in
        // successfully with this provider). Treat as unavailable.
        return _resultUnavailable;
      case AuthSignInSuccess():
        final user = result.credential.user;
        if (user == null) return _resultCancelled;
        if (!_isExpectedUid(user.uid)) {
          await auth.signOut();
          return _resultMismatch;
        }
        await app.setRememberedAuthProvider(provider);
        app.setProfileFromFirebaseUser(user);
        await _completeSignInFlow(user.uid);
        return _resultSuccess;
    }
  }

  Future<bool> _verifyDeviceOwner(String reason) async {
    try {
      final available = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      if (!available && !supported) return true;
      return _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[welcome-back] biometric check error: $e');
        debugPrint('$st');
      }
      return false;
    }
  }

  Future<void> _enter() async {
    if (_loading) return;
    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _loading = true;
      _error = null;
    });

    final ok = await _verifyDeviceOwner(l10n.welcomeBackAuthReason);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _loading = false;
        _error = l10n.welcomeBackAuthCancelled;
      });
      return;
    }

    if (app.isAuthenticated) {
      final uid = app.profile.id.trim();
      if (!_isExpectedUid(uid)) {
        setState(() {
          _loading = false;
          _error = l10n.welcomeBackUidMismatch;
        });
        return;
      }
      await _completeSignInFlow(uid);
      return;
    }

    try {
      final resumed = await _signInWithRememberedProvider();
      if (!mounted) return;
      if (resumed == _resultSuccess) return;

      String errorMessage;
      if (resumed == _resultMismatch) {
        errorMessage = l10n.welcomeBackUidMismatch;
      } else if (resumed == _resultCancelled) {
        errorMessage = l10n.welcomeBackAuthCancelled;
      } else if (resumed == _resultUnavailable) {
        errorMessage = l10n.welcomeBackQuickSignInUnavailable;
      } else {
        errorMessage = l10n.loginSignInError;
      }

      setState(() {
        _loading = false;
        _error = errorMessage;
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[welcome-back] sign-in error: $e');
        debugPrint('$st');
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = l10n.loginSignInError;
      });
    }
  }

  Future<void> _notYou() async {
    final app = CassandraScope.of(context);
    await app.signOut();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;

    final rawHandle = app.rememberedHandle.trim();
    final handle = rawHandle.isEmpty
        ? '@cassandra'
        : (rawHandle.startsWith('@') ? rawHandle : '@$rawHandle');

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProfileImageDisplay(
                  imagePathOrUrl: app.rememberedPhotoUrl,
                  radius: 36,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.welcomeBackTitle(handle),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _enter,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.welcomeBackEnter),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _loading ? null : _notYou,
                    child: Text(l10n.welcomeBackNotYou),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: const TextStyle(color: CassandraColors.primary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
