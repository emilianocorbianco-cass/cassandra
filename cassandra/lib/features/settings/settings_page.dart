import 'package:flutter/material.dart';
import '../../app/widgets/cassandra_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CassandraPage(
      title: 'Settings',
      child: Center(child: Text('Nome squadra, password, tutorial, contatti')),
    );
  }
}
