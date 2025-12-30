import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontSize: 36,
          letterSpacing: 1.2,
        );

    return Scaffold(
      body: Align(
        alignment: const Alignment(0, -0.12),
        child: Text(
          'Cassandra',
          style: titleStyle,
        ),
      ),
    );
  }
}
