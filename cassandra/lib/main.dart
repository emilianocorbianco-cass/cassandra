import 'package:flutter/material.dart';

import 'splash_screen.dart';

void main() {
  runApp(const CassandraApp());
}

class CassandraApp extends StatelessWidget {
  const CassandraApp({super.key});

  @override
  Widget build(BuildContext context) {
    const baseBackground = Color(0xFFF1E6D1);
    const baseAccent = Color(0xFF804046);

    return MaterialApp(
      title: 'Cassandra',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: baseAccent,
          primary: baseAccent,
          secondary: baseBackground,
          surface: baseBackground,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: baseBackground,
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontWeight: FontWeight.w600,
            color: baseAccent,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
