import 'package:flutter/material.dart';
import '../../app/widgets/cassandra_page.dart';

class LeaderboardsPage extends StatelessWidget {
  const LeaderboardsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CassandraPage(
      title: 'Classifiche',
      child: Center(child: Text('Generale + Giornate')),
    );
  }
}
