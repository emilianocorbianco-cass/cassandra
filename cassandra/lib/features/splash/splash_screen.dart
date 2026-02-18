import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/navigation/home_shell.dart';
import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../auth/profile_setup_page.dart';
import '../auth/welcome_back_page.dart';
import '../auth/login_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    // Splash più lunga: 900ms + 500ms = 1400ms
    _timer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;

      final app = CassandraScope.of(context);
      final Widget destination;

      if (app.authService == null) {
        // dev mode: Firebase non configurato → vai diretto a HomeShell
        destination = const HomeShell();
      } else if (app.isAuthenticated) {
        if (app.needsProfileSetup) {
          destination = const ProfileSetupPage();
        } else if (app.hasRememberedIdentity) {
          destination = const WelcomeBackPage();
        } else {
          // sessione persistita → vai a HomeShell
          destination = const HomeShell();
        }
      } else if (app.hasRememberedIdentity) {
        // Sessione Firebase scaduta ma device "trusted":
        // mostra comunque Bentornato e guida al provider corretto.
        destination = const WelcomeBackPage();
      } else {
        // non autenticato → mostra LoginPage
        destination = const LoginPage();
      }

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
    });
  }

  @override
  void dispose() {
    // IMPORTANTISSIMO: annulla il timer se il widget viene distrutto
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: CassandraColors.bg,
      body: SafeArea(
        child: Align(
          alignment: Alignment(0, -0.15),
          child: Text(
            'Cassandra',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w600,
              color: CassandraColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
