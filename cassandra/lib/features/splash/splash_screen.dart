import 'package:flutter/material.dart';
import '../../app/theme/cassandra_colors.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: CassandraColors.bg,
      body: SafeArea(
        child: Align(
          // 0 = centro; -0.15 sposta verso l’alto “leggermente”
          alignment: Alignment(0, -0.15),
          child: Text(
            'Cassandra',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w600,
              color: CassandraColors.primary,
              // fontFamily viene già dal Theme, ma qui puoi forzarlo se vuoi:
              // fontFamily: 'Avenir',
            ),
          ),
        ),
      ),
    );
  }
}
