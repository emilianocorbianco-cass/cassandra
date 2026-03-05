import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/navigation/home_shell.dart';
import '../../app/state/cassandra_scope.dart';
import '../../app/theme/cassandra_colors.dart';
import '../auth/profile_setup_page.dart';
import '../auth/welcome_back_page.dart';
import '../auth/login_page.dart';
import '../group/group_hub_page.dart';
import '../profile/widgets/profile_image_picker.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();

    // Pre-warm profile image cache during splash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = CassandraScope.of(context);
      ProfileImageDisplay.preWarmCache(app.profile.photoUrl);
    });

    _timer = Timer(const Duration(milliseconds: 4200), () {
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
          // sessione persistita → selezione gruppo
          destination = const GroupHubPage();
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
    _fadeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CassandraColors.charcoal,
      body: SafeArea(
        child: Align(
          alignment: const Alignment(0, -0.55),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Image.asset(
              'assets/icon/testicon2.png',
              width: 280,
              height: 280,
            ),
          ),
        ),
      ),
    );
  }
}
