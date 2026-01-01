import 'package:flutter/material.dart';
import '../../app/navigation/home_shell.dart';
import '../../app/theme/cassandra_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    // Per ora: dopo un breve delay vai alla Home.
    // Più avanti qui decideremo: se loggato -> Home, altrimenti -> Login.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    });
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
