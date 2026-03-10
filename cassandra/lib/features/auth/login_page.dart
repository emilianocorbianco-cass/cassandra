import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../../services/auth/auth_service.dart';
import '../../services/notifications/push_notifications_service.dart';
import '../group/group_hub_page.dart';
import 'profile_setup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  String? _error;

  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final Animation<double> _fadeAnim = CurvedAnimation(
    parent: _fadeCtrl,
    curve: Curves.easeIn,
  );

  @override
  void initState() {
    super.initState();
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<bool> _confirmSwitchRememberedIdentity({
    required String rememberedHandle,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final decision = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.loginDifferentAccountTitle),
          content: Text(l10n.loginDifferentAccountBody(rememberedHandle)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.settingsCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.loginDifferentAccountContinue),
            ),
          ],
        );
      },
    );
    return decision ?? false;
  }

  Future<bool> _acceptSignedInUser({
    required String provider,
    required User? user,
  }) async {
    if (user == null || !mounted) return false;
    final app = CassandraScope.of(context);

    final rememberedUid = app.rememberedUid?.trim() ?? '';
    final signedUid = user.uid.trim();
    if (app.hasRememberedIdentity &&
        rememberedUid.isNotEmpty &&
        rememberedUid != signedUid) {
      final rememberedHandleRaw = app.rememberedHandle.trim();
      final rememberedHandle = rememberedHandleRaw.isEmpty
          ? '@cassandra'
          : rememberedHandleRaw;
      final confirmed = await _confirmSwitchRememberedIdentity(
        rememberedHandle: rememberedHandle,
      );
      if (!confirmed) {
        await app.authService?.signOut();
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          setState(() {
            _error = l10n.loginDifferentAccountCancelled;
          });
        }
        return false;
      }
      await app.forgetRememberedIdentity();
    }

    await app.setRememberedAuthProvider(provider);
    app.setProfileFromFirebaseUser(user);
    await _goAfterSignIn(user.uid);
    return true;
  }

  Future<void> _showAccountConflictDialog(
    AuthSignInAccountConflict conflict,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final providerLabel = conflict.existingProvider == 'google'
        ? l10n.loginSignInGoogle
        : l10n.loginSignInApple;

    final shouldLink = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.loginAccountConflictTitle),
        content: Text(
          l10n.loginAccountConflictBody(conflict.email, providerLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.settingsCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.loginAccountConflictLink),
          ),
        ],
      ),
    );

    if (shouldLink != true || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final app = CassandraScope.of(context);
      final authService = app.authService;
      if (authService == null) return;

      // Sign in with the existing provider first.
      AuthSignInResult existingResult;
      if (conflict.existingProvider == 'google') {
        existingResult = await authService.signInWithGoogle();
      } else {
        existingResult = await authService.signInWithApple();
      }

      if (existingResult is! AuthSignInSuccess) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = l10n.loginSignInError;
          });
        }
        return;
      }

      // Link the pending credential to the existing account.
      await authService.linkPendingCredential(conflict.pendingCredential);

      final accepted = await _acceptSignedInUser(
        provider: conflict.existingProvider,
        user: existingResult.credential.user,
      );
      if (!accepted && mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = l10n.loginSignInError;
        });
      }
    }
  }

  Future<void> _goAfterSignIn(String uid) async {
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

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final app = CassandraScope.of(context);
      final authService = app.authService;
      if (authService == null) return;

      final result = await authService.signInWithGoogle();
      switch (result) {
        case AuthSignInCancelled():
          if (mounted) setState(() => _loading = false);
          return;
        case AuthSignInAccountConflict():
          if (mounted) {
            setState(() => _loading = false);
            await _showAccountConflictDialog(result);
          }
          return;
        case AuthSignInSuccess():
          final accepted = await _acceptSignedInUser(
            provider: 'google',
            user: result.credential.user,
          );
          if (!accepted && mounted) {
            setState(() => _loading = false);
          }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _loading = false;
          _error = l10n.loginSignInError;
        });
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final app = CassandraScope.of(context);
      final authService = app.authService;
      if (authService == null) return;

      final result = await authService.signInWithApple();
      switch (result) {
        case AuthSignInCancelled():
          if (mounted) setState(() => _loading = false);
          return;
        case AuthSignInAccountConflict():
          if (mounted) {
            setState(() => _loading = false);
            await _showAccountConflictDialog(result);
          }
          return;
        case AuthSignInSuccess():
          final accepted = await _acceptSignedInUser(
            provider: 'apple',
            user: result.credential.user,
          );
          if (!accepted && mounted) {
            setState(() => _loading = false);
          }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _loading = false;
          _error = l10n.loginSignInError;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: CassandraColors.charcoal,
      body: SafeArea(
        child: Stack(
          children: [
            // Logo — identical to splash screen
            Align(
              alignment: const Alignment(0, -0.55),
              child: Image.asset(
                'assets/icon/testicon2.png',
                width: 280,
                height: 280,
              ),
            ),
            // Sign-in buttons fade in below logo
            Align(
              alignment: const Alignment(0, 0.65),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_loading)
                        const CircularProgressIndicator()
                      else ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _signInWithGoogle,
                            icon: const Icon(Icons.g_mobiledata, size: 24),
                            label: Text(l10n.loginSignInGoogle),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              foregroundColor: CassandraColors.brightSnow,
                              side: const BorderSide(
                                color: CassandraColors.brightSnow,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _signInWithApple,
                            icon: const Icon(Icons.apple, size: 24),
                            label: Text(l10n.loginSignInApple),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              foregroundColor: CassandraColors.brightSnow,
                              side: const BorderSide(
                                color: CassandraColors.brightSnow,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
