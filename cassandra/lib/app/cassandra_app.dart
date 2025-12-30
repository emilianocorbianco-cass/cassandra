import 'package:flutter/material.dart';
import '../features/splash/splash_screen.dart';
import 'theme/cassandra_theme.dart';

class CassandraApp extends StatelessWidget {
  const CassandraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cassandra',
      theme: CassandraTheme.light(),
      home: const SplashScreen(),
    );
  }
}
