import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../app/navigation/home_shell.dart';
import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../../l10n/app_localizations.dart';
import '../profile/widgets/profile_image_picker.dart';
import 'login_page.dart';

class WelcomeBackPage extends StatefulWidget {
  const WelcomeBackPage({super.key});

  @override
  State<WelcomeBackPage> createState() => _WelcomeBackPageState();
}

class _WelcomeBackPageState extends State<WelcomeBackPage> {
  final _auth = LocalAuthentication();
  bool _loading = false;
  String? _error;

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
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
      return;
    }

    setState(() => _loading = false);
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
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
