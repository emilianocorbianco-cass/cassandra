import 'package:flutter/material.dart';
import 'package:cassandra/l10n/app_localizations.dart';

import '../../app/navigation/home_shell.dart';
import '../../app/state/app_settings.dart';
import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final app = CassandraScope.of(context);
      final authService = app.authService;
      if (authService == null) return;

      final credential = await authService.signInWithGoogle();
      if (credential == null) {
        // utente ha annullato
        if (mounted) setState(() => _loading = false);
        return;
      }

      final user = credential.user;
      if (user != null && mounted) {
        app.setProfileFromFirebaseUser(user);
        await app.hydrateProfileFromFirestore(user.uid);
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
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

      final credential = await authService.signInWithApple();
      if (credential == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final user = credential.user;
      if (user != null && mounted) {
        app.setProfileFromFirebaseUser(user);
        await app.hydrateProfileFromFirestore(user.uid);
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
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
    final app = CassandraScope.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: CassandraColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            // Selettore lingua in alto a destra
            Positioned(
              top: 8,
              right: 12,
              child: SegmentedButton<CassandraLanguage>(
                segments: [
                  ButtonSegment(
                    value: CassandraLanguage.system,
                    label: Text(l10n.settingsLanguageSystem),
                  ),
                  ButtonSegment(
                    value: CassandraLanguage.it,
                    label: Text(l10n.settingsLanguageIt),
                  ),
                  ButtonSegment(
                    value: CassandraLanguage.en,
                    label: Text(l10n.settingsLanguageEn),
                  ),
                ],
                selected: {app.language},
                onSelectionChanged: (value) {
                  app.updateLanguage(value.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: WidgetStatePropertyAll(
                    Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
            // Contenuto principale
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 3),
                    const Text(
                      'Cassandra',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        color: CassandraColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.loginSeriesAPredictions,
                      style: const TextStyle(
                        fontSize: 16,
                        color: CassandraColors.slate,
                      ),
                    ),
                    const Spacer(flex: 2),
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
                            foregroundColor: CassandraColors.slate,
                            side: const BorderSide(
                              color: CassandraColors.slate,
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
                            foregroundColor: CassandraColors.slate,
                            side: const BorderSide(
                              color: CassandraColors.slate,
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
                    const Spacer(flex: 1),
                    Text(
                      l10n.loginPrivacyNotice,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CassandraColors.slate,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
