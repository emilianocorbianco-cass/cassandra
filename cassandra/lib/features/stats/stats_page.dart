import 'package:flutter/material.dart';
import '../../app/widgets/cassandra_page.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CassandraPage(
      title: 'Statistiche',
      child: Center(child: Text('Stats personali e/o gruppo (upgrade)')),
    );
  }
}
