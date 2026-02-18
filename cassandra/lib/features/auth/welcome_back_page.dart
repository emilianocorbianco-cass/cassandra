import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../app/navigation/home_shell.dart';
import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../services/notifications/push_notifications_service.dart';
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

    final destination = app.needsProfileSetup
        ? const ProfileSetupPage()
        : const HomeShell();
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

    if (provider == 'google') {
      final credential = await auth.signInWithGoogle();
      final user = credential?.user;
      if (user == null) return _resultCancelled;
      if (!_isExpectedUid(user.uid)) {
        await auth.signOut();
        return _resultMismatch;
      }
      await app.setRememberedAuthProvider('google');
      app.setProfileFromFirebaseUser(user);
      await _completeSignInFlow(user.uid);
      return _resultSuccess;
    }

    if (provider == 'apple') {
      final credential = await auth.signInWithApple();
      final user = credential?.user;
      if (user == null) return _resultCancelled;
      if (!_isExpectedUid(user.uid)) {
        await auth.signOut();
        return _resultMismatch;
      }
      await app.setRememberedAuthProvider('apple');
      app.setProfileFromFirebaseUser(user);
      await _completeSignInFlow(user.uid);
      return _resultSuccess;
    }

    return _resultUnavailable;
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
    } catch (_) {
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
    } catch (_) {
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
