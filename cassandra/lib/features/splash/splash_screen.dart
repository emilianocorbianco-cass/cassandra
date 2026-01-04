import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/navigation/home_shell.dart';
import '../../app/theme/cassandra_colors.dart';

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
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
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
