import 'package:flutter/material.dart';

import '../../app/navigation/home_shell.dart';
import '../../app/state/app_settings.dart';
import '../../app/state/app_state.dart';
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

  bool _isEnglish(AppState app) {
    final code = app.language == CassandraLanguage.system
        ? Localizations.localeOf(context).languageCode
        : (app.language == CassandraLanguage.en ? 'en' : 'it');
    return code.toLowerCase().startsWith('en');
  }

  String _t(AppState app, String it, String en) => _isEnglish(app) ? en : it;

  String _langLabel(CassandraLanguage lang) {
    switch (lang) {
      case CassandraLanguage.system:
        return 'Auto';
      case CassandraLanguage.it:
        return 'IT';
      case CassandraLanguage.en:
        return 'EN';
    }
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

      final credential = await authService.signInWithGoogle();
      if (credential == null) {
        // utente ha annullato
        if (mounted) setState(() => _loading = false);
        return;
      }

      final user = credential.user;
      if (user != null && mounted) {
        app.setProfileFromFirebaseUser(user);
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
      }
    } catch (e) {
      if (mounted) {
        final app = CassandraScope.of(context);
        setState(() {
          _loading = false;
          _error = _t(
            app,
            'Errore di accesso. Riprova.',
            'Sign-in error. Please try again.',
          );
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
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
      }
    } catch (e) {
      if (mounted) {
        final app = CassandraScope.of(context);
        setState(() {
          _loading = false;
          _error = _t(
            app,
            'Errore di accesso. Riprova.',
            'Sign-in error. Please try again.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = CassandraScope.of(context);

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
                    label: Text(_langLabel(CassandraLanguage.system)),
                  ),
                  ButtonSegment(
                    value: CassandraLanguage.it,
                    label: Text(_langLabel(CassandraLanguage.it)),
                  ),
                  ButtonSegment(
                    value: CassandraLanguage.en,
                    label: Text(_langLabel(CassandraLanguage.en)),
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
                      _t(app, 'Pronostici Serie A', 'Serie A Predictions'),
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
                          label: Text(
                            _t(app, 'Accedi con Google', 'Sign in with Google'),
                          ),
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
                          label: Text(
                            _t(app, 'Accedi con Apple', 'Sign in with Apple'),
                          ),
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
                      _t(
                        app,
                        'Usiamo solo il minimo necessario per identificarti.',
                        'We only use what\u0027s strictly necessary to identify you.',
                      ),
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
